use std::io;
use std::os::unix::process::CommandExt as _;
use std::process::{Child, Command, ExitStatus};
use std::thread;
use std::time::{Duration, Instant};

const SIGTERM: i32 = 15;
const SIGKILL: i32 = 9;
const ESRCH: i32 = 3;
const TERMINATION_GRACE: Duration = Duration::from_secs(5);

#[cfg(test)]
pub(crate) static PROCESS_TEST_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());

pub fn spawn_process_group(program: &str, args: &[String]) -> io::Result<Child> {
    let mut command = Command::new(program);
    command.args(args);
    command.process_group(0);
    command.spawn()
}

pub fn terminate_process_group(child: &mut Child) -> io::Result<ExitStatus> {
    terminate_process_group_with_grace(child, TERMINATION_GRACE)
}

fn terminate_process_group_with_grace(
    child: &mut Child,
    grace: Duration,
) -> io::Result<ExitStatus> {
    let process_group = i32::try_from(child.id())
        .map_err(|_| io::Error::other("child process ID exceeded pid_t"))?;
    let mut direct_status = child.try_wait()?;
    if !process_group_exists(process_group)?
        && let Some(status) = direct_status
    {
        return Ok(status);
    }
    signal_process_group(process_group, SIGTERM).map_err(|error| {
        io::Error::new(
            error.kind(),
            format!("could not send SIGTERM to process group {process_group}: {error}"),
        )
    })?;
    let deadline = Instant::now() + grace;
    while Instant::now() < deadline {
        if direct_status.is_none() {
            direct_status = child.try_wait()?;
        }
        if !process_group_exists(process_group)?
            && let Some(status) = direct_status
        {
            return Ok(status);
        }
        thread::sleep(Duration::from_millis(50));
    }
    let kill_error = if process_group_exists(process_group)? {
        signal_process_group(process_group, SIGKILL).err()
    } else {
        None
    };
    let kill_deadline = Instant::now() + Duration::from_secs(1);
    while Instant::now() < kill_deadline {
        if direct_status.is_none() {
            direct_status = child.try_wait()?;
        }
        if !process_group_exists(process_group)?
            && let Some(status) = direct_status
        {
            return Ok(status);
        }
        thread::sleep(Duration::from_millis(10));
    }
    if process_group_exists(process_group)? {
        match kill_error {
            Some(error) => Err(io::Error::new(
                error.kind(),
                format!(
                    "could not send SIGKILL to process group {process_group}, \
                     which still exists: {error}"
                ),
            )),
            None => Err(io::Error::other("process group still exists after SIGKILL")),
        }
    } else if let Some(status) = direct_status {
        Ok(status)
    } else {
        Err(io::Error::new(
            io::ErrorKind::TimedOut,
            "process group exited but its leader could not be reaped",
        ))
    }
}

fn signal_process_group(process_group: i32, signal: i32) -> io::Result<()> {
    // The child is its process-group leader. A negative PID therefore targets
    // only that CLI-owned group and descendants that inherited it.
    // SAFETY: kill reads no pointers; the PID came from a live Child handle.
    if unsafe { libc::kill(-process_group, signal) } == 0 {
        return Ok(());
    }
    let error = io::Error::last_os_error();
    if error.raw_os_error() == Some(ESRCH) {
        Ok(())
    } else {
        Err(error)
    }
}

fn process_group_exists(process_group: i32) -> io::Result<bool> {
    // SAFETY: signal 0 performs permission/existence checking only and reads no
    // pointers. The process-group ID originated from a spawned child.
    if unsafe { libc::kill(-process_group, 0) } == 0 {
        return Ok(true);
    }
    let error = io::Error::last_os_error();
    match error.raw_os_error() {
        Some(ESRCH) => Ok(false),
        Some(libc::EPERM) => Ok(true),
        _ => Err(error),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::os::unix::process::ExitStatusExt as _;

    #[test]
    fn escalates_to_sigkill_when_group_ignores_sigterm() {
        let _guard = PROCESS_TEST_LOCK.lock().unwrap();
        let temp = tempfile::tempdir().unwrap();
        let ready = temp.path().join("ready");
        let script = format!(
            "trap '' TERM; : > '{}'; while :; do sleep 1; done",
            ready.display()
        );
        let mut child = spawn_process_group("/bin/sh", &[String::from("-c"), script]).unwrap();
        let deadline = Instant::now() + Duration::from_secs(2);
        while !ready.exists() && Instant::now() < deadline {
            thread::sleep(Duration::from_millis(10));
        }
        assert!(fs::metadata(ready).is_ok());

        let status =
            terminate_process_group_with_grace(&mut child, Duration::from_millis(20)).unwrap();
        assert_eq!(status.signal(), Some(SIGKILL));
    }

    #[test]
    fn production_termination_grace_is_five_seconds() {
        assert_eq!(TERMINATION_GRACE, Duration::from_secs(5));
    }

    #[test]
    fn an_already_exited_process_group_is_reaped_successfully() {
        let _guard = PROCESS_TEST_LOCK.lock().unwrap();
        let mut child = spawn_process_group("/usr/bin/true", &[]).unwrap();
        let deadline = Instant::now() + Duration::from_secs(2);
        while child.try_wait().unwrap().is_none() && Instant::now() < deadline {
            thread::yield_now();
        }

        assert!(
            terminate_process_group_with_grace(&mut child, Duration::ZERO)
                .unwrap()
                .success()
        );
    }

    #[test]
    fn kills_descendants_after_group_leader_exits_on_sigterm() {
        let _guard = PROCESS_TEST_LOCK.lock().unwrap();
        let temp = tempfile::tempdir().unwrap();
        let ready = temp.path().join("ready");
        let descendant_pid = temp.path().join("descendant-pid");
        let script = format!(
            "trap 'exit 0' TERM; \
             /bin/sh -c 'trap \"\" TERM; while :; do sleep 1; done' & \
             echo $! > '{}'; : > '{}'; wait",
            descendant_pid.display(),
            ready.display(),
        );
        let mut child = spawn_process_group("/bin/sh", &[String::from("-c"), script]).unwrap();
        let process_group = i32::try_from(child.id()).unwrap();
        let deadline = Instant::now() + Duration::from_secs(2);
        while !ready.exists() && Instant::now() < deadline {
            thread::sleep(Duration::from_millis(10));
        }
        assert!(ready.exists());

        let status = match terminate_process_group_with_grace(&mut child, Duration::from_millis(20))
        {
            Ok(status) => status,
            Err(error) => {
                let pid = fs::read_to_string(descendant_pid)
                    .ok()
                    .and_then(|pid| pid.trim().parse::<i32>().ok());
                if let Some(pid) = pid {
                    // Test-only fallback: keep a failed assertion from
                    // leaking a deliberately SIGTERM-resistant process
                    // into later tests.
                    // SAFETY: the PID was written by the child this test
                    // spawned.
                    let _ = unsafe { libc::kill(pid, SIGKILL) };
                }
                panic!("process-group cleanup failed: {error}");
            }
        };
        assert!(status.success());
        assert!(!process_group_exists(process_group).unwrap());
    }
}
