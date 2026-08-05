use crate::client::{self, LeaseClient};
use crate::model::{MAX_LID_LEASE_MS, TripReason};
use crate::process::{spawn_process_group, terminate_process_group};
use crate::protocol::{Event, Reply, Request, Status};
use clap::{Parser, Subcommand};
use std::io;
use std::os::unix::process::ExitStatusExt as _;
use std::process::{Command, ExitCode, ExitStatus};
use std::sync::Arc;
use std::sync::atomic::{AtomicI32, Ordering};
use std::thread;
use std::time::{Duration, Instant};

const EXIT_USAGE: u8 = 2;
const EXIT_DAEMON: u8 = 3;
const EXIT_REFUSED: u8 = 4;
const EXIT_TRIP: u8 = 5;
const EXIT_CLEANUP: u8 = 6;
const EXIT_STOPPED: u8 = 7;

#[derive(Parser)]
#[command(
    name = "sleepctl",
    version,
    about = "Deadline-bound macOS sleep leases"
)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    Run {
        #[arg(long)]
        lid_closed: bool,
        #[arg(long = "for", value_parser = parse_duration)]
        duration: Duration,
        #[arg(last = true, required = true)]
        command: Vec<String>,
    },
    Hold {
        #[arg(long)]
        lid_closed: bool,
        #[arg(long = "for", value_parser = parse_duration)]
        duration: Duration,
    },
    Status {
        #[arg(long)]
        json: bool,
    },
    Doctor,
    Stop {
        #[arg(long)]
        all: bool,
    },
    Recover,
}

fn parse_duration(value: &str) -> Result<Duration, String> {
    let duration = humantime::parse_duration(value).map_err(|error| error.to_string())?;
    if duration.is_zero() {
        return Err("duration must be greater than zero".into());
    }
    Ok(duration)
}

pub fn run() -> ExitCode {
    let cli = match Cli::try_parse() {
        Ok(cli) => cli,
        Err(error) => {
            let code = u8::try_from(error.exit_code()).unwrap_or(EXIT_USAGE);
            let _ = error.print();
            return ExitCode::from(code);
        }
    };
    match execute(cli.command) {
        Ok(code) => code,
        Err(error) => {
            match &error {
                CliError::Daemon(message) => eprintln!("sleepctl: daemon: {message}"),
                CliError::Refused(message) => eprintln!("sleepctl: refused: {message}"),
                CliError::Trip(message) => eprintln!("sleepctl: safety trip: {message}"),
                CliError::Cleanup(message) => eprintln!("sleepctl: cleanup: {message}"),
                CliError::Stopped => eprintln!("sleepctl: stopped by operator"),
                CliError::Usage(message) => eprintln!("sleepctl: {message}"),
            }
            ExitCode::from(error_exit_code(&error))
        }
    }
}

#[derive(Debug)]
enum CliError {
    Usage(String),
    Daemon(io::Error),
    Refused(String),
    Trip(String),
    Cleanup(io::Error),
    Stopped,
}

fn execute(command: Commands) -> Result<ExitCode, CliError> {
    match command {
        Commands::Run {
            lid_closed,
            duration,
            command,
        } => {
            if lid_closed {
                run_lid(duration, command)
            } else {
                run_idle(duration, command)
            }
        }
        Commands::Hold {
            lid_closed,
            duration,
        } => {
            if !lid_closed {
                return Err(CliError::Usage(
                    "hold currently requires --lid-closed".into(),
                ));
            }
            hold_lid(duration)
        }
        Commands::Status { json } => status(json),
        Commands::Doctor => doctor(),
        Commands::Stop { all } => {
            if !all {
                return Err(CliError::Usage("stop requires --all".into()));
            }
            match client::request(Request::StopAll).map_err(CliError::Daemon)? {
                Reply::Stopped { leases } => {
                    println!("stopped {leases} lid lease(s)");
                    Ok(ExitCode::SUCCESS)
                }
                Reply::Error { message, .. } => Err(CliError::Cleanup(io::Error::other(message))),
                other => Err(CliError::Daemon(io::Error::new(
                    io::ErrorKind::InvalidData,
                    format!("unexpected stop response: {other:?}"),
                ))),
            }
        }
        Commands::Recover => {
            recover_reply(client::request(Request::Recover).map_err(CliError::Daemon)?)
        }
    }
}

fn recover_reply(reply: Reply) -> Result<ExitCode, CliError> {
    match reply {
        Reply::Recovered => {
            println!("sleep state is recovered");
            Ok(ExitCode::SUCCESS)
        }
        Reply::Error { code, message } if code == "recover_refused" => {
            Err(CliError::Refused(message))
        }
        Reply::Error { message, .. } => Err(CliError::Cleanup(io::Error::other(message))),
        other => Err(CliError::Daemon(io::Error::new(
            io::ErrorKind::InvalidData,
            format!("unexpected recover response: {other:?}"),
        ))),
    }
}

fn validate_lid_duration(duration: Duration) -> Result<u64, CliError> {
    let duration_ms = u64::try_from(duration.as_millis())
        .map_err(|_| CliError::Usage("duration is too large".into()))?;
    if duration_ms > MAX_LID_LEASE_MS {
        return Err(CliError::Usage(
            "lid-closed duration cannot exceed 4 hours".into(),
        ));
    }
    Ok(duration_ms)
}

fn run_lid(duration: Duration, command: Vec<String>) -> Result<ExitCode, CliError> {
    let received_signal = install_signal_forwarding()?;
    let duration_ms = validate_lid_duration(duration)?;
    let lease = LeaseClient::acquire(duration_ms).map_err(classify_acquire_error)?;
    let (program, args) = split_command(command)?;
    let mut child = match spawn_process_group(&program, &args) {
        Ok(child) => child,
        Err(spawn_error) => {
            return match lease.release() {
                Ok(()) => Err(CliError::Cleanup(spawn_error)),
                Err(release_error) => Err(CliError::Cleanup(io::Error::other(format!(
                    "could not start child: {spawn_error}; lease release also failed: \
                     {release_error}"
                )))),
            };
        }
    };

    loop {
        if let Some(signal) = received_signal() {
            terminate_and_release(&mut child, &lease)?;
            return Ok(signal_exit_code(signal));
        }
        if let Some(status) = child.try_wait().map_err(CliError::Cleanup)? {
            lease.release().map_err(CliError::Cleanup)?;
            return Ok(exit_code(status));
        }
        let event = match lease.try_event() {
            Ok(event) => event,
            Err(error) => {
                lease.deactivate();
                let _ = terminate_process_group(&mut child).map_err(CliError::Cleanup)?;
                return Err(CliError::Daemon(error));
            }
        };
        match event {
            Some(Event::Warning { thermal }) => {
                eprintln!("sleepctl: thermal warning: {thermal:?}");
            }
            Some(Event::LeaseExpired { .. }) => {
                lease.disconnect();
                eprintln!(
                    "sleepctl: lid lease expired; command continues without sleep prevention"
                );
                return wait_for_child(&mut child, &received_signal);
            }
            Some(Event::LeaseRevoked { .. }) => {
                lease.disconnect();
                let _ = terminate_process_group(&mut child).map_err(CliError::Cleanup)?;
                return Err(lease_revoked_error());
            }
            Some(Event::Trip { reason, .. }) => {
                lease.deactivate();
                if reason == TripReason::PowerRestoreFailed {
                    terminate_process_group(&mut child).map_err(CliError::Cleanup)?;
                    return Err(CliError::Cleanup(io::Error::other(
                        "daemon could not verify restoration of SleepDisabled",
                    )));
                }
                terminate_and_confirm_restore(&mut child, &lease)?;
                return Err(CliError::Trip(format!("{reason:?}")));
            }
            Some(Event::OperatorStopped { .. }) => {
                lease.deactivate();
                terminate_and_confirm_restore(&mut child, &lease)?;
                return Err(CliError::Stopped);
            }
            Some(Event::PowerRestored { .. }) => {}
            None => thread::sleep(Duration::from_millis(100)),
        }
    }
}

fn hold_lid(duration: Duration) -> Result<ExitCode, CliError> {
    let received_signal = install_signal_forwarding()?;
    let duration_ms = validate_lid_duration(duration)?;
    let lease = LeaseClient::acquire(duration_ms).map_err(classify_acquire_error)?;
    // Hold deliberately owns no Child or process-group handle. Its signal and
    // safety paths may release/revoke only the lease, so this command can
    // never target an unrelated process.
    loop {
        if let Some(signal) = received_signal() {
            lease.release().map_err(CliError::Cleanup)?;
            return Ok(signal_exit_code(signal));
        }
        match lease.try_event().map_err(CliError::Daemon)? {
            Some(Event::Warning { thermal }) => {
                eprintln!("sleepctl: thermal warning: {thermal:?}");
            }
            Some(Event::LeaseExpired { .. }) => {
                lease.disconnect();
                return Ok(ExitCode::SUCCESS);
            }
            Some(Event::LeaseRevoked { .. }) => {
                lease.disconnect();
                return Err(lease_revoked_error());
            }
            Some(Event::Trip { reason, .. }) => {
                lease.deactivate();
                if reason == TripReason::PowerRestoreFailed {
                    return Err(CliError::Cleanup(io::Error::other(
                        "daemon could not verify restoration of SleepDisabled",
                    )));
                }
                lease.wait_for_power_restore().map_err(CliError::Cleanup)?;
                return Err(CliError::Trip(format!("{reason:?}")));
            }
            Some(Event::OperatorStopped { .. }) => {
                lease.deactivate();
                lease.wait_for_power_restore().map_err(CliError::Cleanup)?;
                return Err(CliError::Stopped);
            }
            Some(Event::PowerRestored { .. }) => {}
            None => thread::sleep(Duration::from_millis(100)),
        }
    }
}

fn run_idle(duration: Duration, command: Vec<String>) -> Result<ExitCode, CliError> {
    let received_signal = install_signal_forwarding()?;
    let deadline = Instant::now()
        .checked_add(duration)
        .ok_or_else(|| CliError::Usage("duration is too large".into()))?;
    let (program, args) = split_command(command)?;
    let mut child = spawn_process_group(&program, &args).map_err(CliError::Cleanup)?;
    let mut caffeinate = match Command::new("/usr/bin/caffeinate")
        .args(["-i", "-w", &child.id().to_string()])
        .spawn()
    {
        Ok(caffeinate) => caffeinate,
        Err(error) => {
            return match terminate_process_group(&mut child) {
                Ok(_) => Err(CliError::Cleanup(error)),
                Err(cleanup_error) => Err(CliError::Cleanup(io::Error::other(format!(
                    "could not start caffeinate: {error}; child cleanup also failed: \
                     {cleanup_error}"
                )))),
            };
        }
    };
    let mut keeping_awake = true;
    loop {
        if let Some(signal) = received_signal() {
            let _ = terminate_process_group(&mut child).map_err(CliError::Cleanup)?;
            let _ = caffeinate.kill();
            let _ = caffeinate.wait();
            return Ok(signal_exit_code(signal));
        }
        if let Some(status) = child.try_wait().map_err(CliError::Cleanup)? {
            if keeping_awake {
                let _ = caffeinate.kill();
            }
            let _ = caffeinate.wait();
            return Ok(exit_code(status));
        }
        if keeping_awake && let Some(status) = caffeinate.try_wait().map_err(CliError::Cleanup)? {
            let helper_error = io::Error::other(format!(
                "caffeinate exited before the idle-sleep deadline: {status}"
            ));
            return match terminate_process_group(&mut child) {
                Ok(_) => Err(CliError::Cleanup(helper_error)),
                Err(cleanup_error) => Err(CliError::Cleanup(io::Error::other(format!(
                    "{helper_error}; child cleanup also failed: {cleanup_error}"
                )))),
            };
        }
        if keeping_awake && Instant::now() >= deadline {
            let _ = caffeinate.kill();
            let _ = caffeinate.wait();
            keeping_awake = false;
            eprintln!("sleepctl: idle sleep lease expired; command continues");
        }
        thread::sleep(Duration::from_millis(100));
    }
}

fn split_command(command: Vec<String>) -> Result<(String, Vec<String>), CliError> {
    let mut command = command.into_iter();
    let program = command
        .next()
        .ok_or_else(|| CliError::Usage("missing command after --".into()))?;
    Ok((program, command.collect()))
}

fn wait_for_child(
    child: &mut std::process::Child,
    received_signal: &impl Fn() -> Option<i32>,
) -> Result<ExitCode, CliError> {
    loop {
        if let Some(signal) = received_signal() {
            terminate_process_group(child).map_err(CliError::Cleanup)?;
            return Ok(signal_exit_code(signal));
        }
        if let Some(status) = child.try_wait().map_err(CliError::Cleanup)? {
            return Ok(exit_code(status));
        }
        thread::sleep(Duration::from_millis(100));
    }
}

fn terminate_and_release(
    child: &mut std::process::Child,
    lease: &LeaseClient,
) -> Result<(), CliError> {
    let terminate_result = terminate_process_group(child);
    let release_result = lease.release();
    match (terminate_result, release_result) {
        (Ok(_), Ok(())) => Ok(()),
        (Err(error), Ok(())) | (Ok(_), Err(error)) => Err(CliError::Cleanup(error)),
        (Err(terminate_error), Err(release_error)) => {
            Err(CliError::Cleanup(io::Error::other(format!(
                "child termination failed: {terminate_error}; lease release also failed: \
                 {release_error}"
            ))))
        }
    }
}

fn terminate_and_confirm_restore(
    child: &mut std::process::Child,
    lease: &LeaseClient,
) -> Result<(), CliError> {
    let terminate_result = terminate_process_group(child);
    let restore_result = lease.wait_for_power_restore();
    match (terminate_result, restore_result) {
        (Ok(_), Ok(())) => Ok(()),
        (Err(error), Ok(())) | (Ok(_), Err(error)) => Err(CliError::Cleanup(error)),
        (Err(terminate_error), Err(restore_error)) => {
            Err(CliError::Cleanup(io::Error::other(format!(
                "child termination failed: {terminate_error}; power restoration also failed: \
                 {restore_error}"
            ))))
        }
    }
}

fn classify_acquire_error(error: io::Error) -> CliError {
    if error.kind() == io::ErrorKind::PermissionDenied {
        CliError::Refused(error.to_string())
    } else {
        CliError::Daemon(error)
    }
}

fn lease_revoked_error() -> CliError {
    CliError::Daemon(io::Error::new(
        io::ErrorKind::ConnectionAborted,
        "lease was revoked after heartbeat or client failure",
    ))
}

fn error_exit_code(error: &CliError) -> u8 {
    match error {
        CliError::Usage(_) => EXIT_USAGE,
        CliError::Daemon(_) => EXIT_DAEMON,
        CliError::Refused(_) => EXIT_REFUSED,
        CliError::Trip(_) => EXIT_TRIP,
        CliError::Cleanup(_) => EXIT_CLEANUP,
        CliError::Stopped => EXIT_STOPPED,
    }
}

fn status(json: bool) -> Result<ExitCode, CliError> {
    let reply = client::request(Request::Status).map_err(CliError::Daemon)?;
    let Reply::Status(status) = reply else {
        return Err(reply_error(reply, "status"));
    };
    if json {
        println!(
            "{}",
            serde_json::to_string_pretty(&status)
                .map_err(|error| CliError::Daemon(io::Error::other(error)))?
        );
    } else {
        print_status(&status);
    }
    Ok(ExitCode::SUCCESS)
}

fn print_status(status: &Status) {
    println!("daemon reachable: {}", status.daemon_reachable);
    println!("healthy: {}", status.healthy);
    if let Some(problem) = &status.health_problem {
        println!("health problem: {problem}");
    }
    println!("thermal: {:?}", status.thermal);
    println!("thermal latch: {}", status.thermal_latched);
    println!("battery: {:?}", status.battery);
    println!("SleepDisabled: {:?}", status.sleep_disabled);
    println!("foreign state: {}", status.foreign_state);
    println!("active leases: {}", status.active_leases.len());
    for lease in &status.active_leases {
        println!(
            "  {}: {} remaining",
            lease.id,
            humantime::format_duration(Duration::from_millis(lease.remaining_ms))
        );
    }
    println!("last trip: {:?}", status.last_trip);
}

fn install_signal_forwarding() -> Result<impl Fn() -> Option<i32>, CliError> {
    let received = Arc::new(AtomicI32::new(0));
    let mut signals = signal_hook::iterator::Signals::new([
        signal_hook::consts::SIGINT,
        signal_hook::consts::SIGTERM,
    ])
    .map_err(CliError::Cleanup)?;
    let handler_state = Arc::clone(&received);
    thread::spawn(move || {
        if let Some(signal) = signals.forever().next() {
            handler_state.store(signal, Ordering::Release);
        }
    });
    Ok(move || {
        let signal = received.load(Ordering::Acquire);
        (signal != 0).then_some(signal)
    })
}

fn signal_exit_code(signal: i32) -> ExitCode {
    let code = 128_i32.saturating_add(signal);
    ExitCode::from(u8::try_from(code).unwrap_or(1))
}

fn doctor() -> Result<ExitCode, CliError> {
    let reply = client::request(Request::Doctor).map_err(CliError::Daemon)?;
    let Reply::Doctor(status) = reply else {
        return Err(reply_error(reply, "doctor"));
    };
    println!(
        "{}",
        serde_json::to_string_pretty(&status)
            .map_err(|error| CliError::Daemon(io::Error::other(error)))?
    );
    if status.problems.is_empty() {
        Ok(ExitCode::SUCCESS)
    } else {
        Err(CliError::Refused(status.problems.join("; ")))
    }
}

fn reply_error(reply: Reply, operation: &str) -> CliError {
    match reply {
        Reply::Error { message, .. } => CliError::Refused(message),
        other => CliError::Daemon(io::Error::new(
            io::ErrorKind::InvalidData,
            format!("unexpected {operation} response: {other:?}"),
        )),
    }
}

fn exit_code(status: ExitStatus) -> ExitCode {
    if let Some(code) = status.code() {
        ExitCode::from(u8::try_from(code).unwrap_or(1))
    } else if let Some(signal) = status.signal() {
        signal_exit_code(signal)
    } else {
        ExitCode::from(1)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn duration_rejects_zero() {
        assert!(parse_duration("0s").is_err());
    }

    #[test]
    fn lid_duration_accepts_four_hours_and_rejects_more() {
        assert_eq!(
            validate_lid_duration(Duration::from_secs(4 * 60 * 60)).unwrap(),
            MAX_LID_LEASE_MS
        );
        assert!(validate_lid_duration(Duration::from_secs(4 * 60 * 60 + 1)).is_err());
    }

    #[test]
    fn split_command_preserves_arguments() {
        assert_eq!(
            split_command(vec!["printf".into(), "%s".into(), "hello world".into()]).unwrap(),
            ("printf".into(), vec!["%s".into(), "hello world".into()])
        );
    }

    #[test]
    fn child_signal_status_maps_to_shell_convention() {
        let status = ExitStatus::from_raw(libc::SIGTERM);
        assert_eq!(exit_code(status), ExitCode::from(143));
    }

    #[test]
    fn clap_help_is_success_and_invalid_usage_is_two() {
        let help = Cli::try_parse_from(["sleepctl", "--help"])
            .err()
            .expect("help should short-circuit parsing");
        assert_eq!(help.exit_code(), 0);
        let invalid = Cli::try_parse_from(["sleepctl"])
            .err()
            .expect("missing subcommand should fail");
        assert_eq!(invalid.exit_code(), i32::from(EXIT_USAGE));
    }

    #[test]
    fn recover_refusal_is_not_reported_as_cleanup_failure() {
        let result = recover_reply(Reply::Error {
            code: "recover_refused".into(),
            message: "foreign state".into(),
        });
        assert!(matches!(result, Err(CliError::Refused(message)) if message == "foreign state"));
    }

    #[test]
    fn lease_revocation_is_a_daemon_failure_not_a_cleanup_failure() {
        assert_eq!(error_exit_code(&lease_revoked_error()), EXIT_DAEMON);
    }

    #[test]
    fn post_deadline_wait_still_handles_signals() {
        let _guard = crate::process::PROCESS_TEST_LOCK.lock().unwrap();
        let mut child = spawn_process_group("/bin/sleep", &["60".into()]).unwrap();
        let code = wait_for_child(&mut child, &|| Some(libc::SIGTERM)).unwrap();
        assert_eq!(code, ExitCode::from(143));
    }

    #[test]
    fn post_deadline_wait_propagates_the_child_status() {
        let _guard = crate::process::PROCESS_TEST_LOCK.lock().unwrap();
        let mut child = spawn_process_group("/bin/sh", &["-c".into(), "exit 23".into()]).unwrap();
        let code = wait_for_child(&mut child, &|| None).unwrap();
        assert_eq!(code, ExitCode::from(23));
    }
}
