use crate::model::{
    BatteryState, HEARTBEAT_TIMEOUT_MS, Lease, LeaseBook, MAX_ACTIVE_LID_LEASES, MAX_LID_LEASE_MS,
    SafetyPolicy, THERMAL_POLL_INTERVAL_MS, ThermalDecision, ThermalState, TripReason,
};
use crate::power::{PowerController, SystemPowerController};
use crate::protocol::{
    DoctorStatus, Envelope, Event, LeaseStatus, PROTOCOL_VERSION, Reply, Request, ServerMessage,
    Status, read_frame, require_version, write_frame,
};
use crate::thermal::{FoundationThermalSource, ThermalSource};
use clap::Parser;
use std::collections::BTreeMap;
use std::ffi::CString;
use std::fs::{self, File, OpenOptions};
use std::io;
use std::net::Shutdown;
use std::os::fd::AsRawFd as _;
use std::os::unix::fs::{
    FileTypeExt as _, MetadataExt as _, OpenOptionsExt as _, PermissionsExt as _,
};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::Path;
use std::process::ExitCode;
use std::sync::atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering};
use std::sync::mpsc::{SyncSender, TrySendError, sync_channel};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

const SOCKET_PATH: &str = "/var/run/sleepctld.sock";
const LOCK_PATH: &str = "/var/db/sleepctl/daemon.lock";
const MAX_CLIENT_CONNECTIONS: usize = 64;
const CLIENT_READ_TIMEOUT: Duration = Duration::from_secs(20);
const CLIENT_EVENT_QUEUE: usize = 16;

#[derive(Parser)]
#[command(
    name = "sleepctld",
    version,
    about = "Privileged sleepctl lease daemon"
)]
struct Args {
    #[arg(long)]
    allowed_user: String,
}

#[derive(Clone)]
struct ClientSink {
    sender: SyncSender<ServerMessage>,
    shutdown: Arc<UnixStream>,
}

impl ClientSink {
    fn new(stream: &UnixStream) -> io::Result<Self> {
        let mut writer = stream.try_clone()?;
        writer.set_write_timeout(Some(Duration::from_millis(200)))?;
        let shutdown = Arc::new(stream.try_clone()?);
        let worker_shutdown = Arc::clone(&shutdown);
        let (sender, receiver) = sync_channel(CLIENT_EVENT_QUEUE);
        thread::spawn(move || {
            while let Ok(message) = receiver.recv() {
                if write_frame(&mut writer, &Envelope::new(message)).is_err() {
                    break;
                }
            }
            let _ = worker_shutdown.shutdown(Shutdown::Both);
        });
        Ok(Self { sender, shutdown })
    }

    fn send(&self, message: ServerMessage) -> io::Result<()> {
        match self.sender.try_send(message) {
            Ok(()) => Ok(()),
            Err(TrySendError::Full(_)) => {
                let _ = self.shutdown.shutdown(Shutdown::Both);
                Err(io::Error::new(
                    io::ErrorKind::WouldBlock,
                    "client event queue is full",
                ))
            }
            Err(TrySendError::Disconnected(_)) => Err(io::Error::new(
                io::ErrorKind::BrokenPipe,
                "client writer is disconnected",
            )),
        }
    }
}

struct ConnectedLease {
    sink: ClientSink,
}

struct RuntimeState {
    leases: LeaseBook,
    connections: BTreeMap<String, ConnectedLease>,
    policy: SafetyPolicy,
    latest_thermal: Option<ThermalState>,
    latest_battery: Option<BatteryState>,
    foreign_state: bool,
    unhealthy: Option<String>,
    lease_epoch: u64,
}

impl RuntimeState {
    fn new(foreign_state: bool) -> Self {
        Self {
            leases: LeaseBook::default(),
            connections: BTreeMap::new(),
            policy: SafetyPolicy::default(),
            latest_thermal: None,
            latest_battery: None,
            foreign_state,
            unhealthy: None,
            lease_epoch: 0,
        }
    }
}

trait Clock: Send + Sync {
    fn now_ms(&self) -> u64;
}

struct MonotonicClock {
    started: Instant,
}

impl MonotonicClock {
    fn new() -> Self {
        Self {
            started: Instant::now(),
        }
    }
}

impl Clock for MonotonicClock {
    fn now_ms(&self) -> u64 {
        u64::try_from(self.started.elapsed().as_millis()).unwrap_or(u64::MAX)
    }
}

struct Manager {
    power: Arc<dyn PowerController>,
    thermal: Arc<dyn ThermalSource>,
    clock: Arc<dyn Clock>,
    state: Mutex<RuntimeState>,
    operation: Mutex<()>,
    next_lease: AtomicU64,
    power_epoch: AtomicU64,
    accepting: AtomicBool,
    fatal: AtomicBool,
}

impl Manager {
    fn new(power: Arc<dyn PowerController>, thermal: Arc<dyn ThermalSource>) -> io::Result<Self> {
        Self::new_with_clock(power, thermal, Arc::new(MonotonicClock::new()))
    }

    fn new_with_clock(
        power: Arc<dyn PowerController>,
        thermal: Arc<dyn ThermalSource>,
        clock: Arc<dyn Clock>,
    ) -> io::Result<Self> {
        power.ensure_state_directory()?;
        if !power.fixed_commands_available()? {
            return Err(io::Error::new(
                io::ErrorKind::PermissionDenied,
                "fixed pmset or ioreg executable is not secure",
            ));
        }
        let sentinel = power.sentinel_exists()?;
        let foreign_state = if sentinel {
            // An owned sentinel means a previous mutation may still be active.
            // Restore first; a read failure must not prevent the reset attempt.
            power.set_sleep_disabled(false)?;
            power.remove_sentinel()?;
            false
        } else {
            power.sleep_disabled()?
        };
        Ok(Self {
            power,
            thermal,
            clock,
            state: Mutex::new(RuntimeState::new(foreign_state)),
            operation: Mutex::new(()),
            next_lease: AtomicU64::new(1),
            power_epoch: AtomicU64::new(0),
            accepting: AtomicBool::new(true),
            fatal: AtomicBool::new(false),
        })
    }

    fn now_ms(&self) -> u64 {
        self.clock.now_ms()
    }

    fn acquire(&self, duration_ms: u64, sink: ClientSink) -> Result<String, String> {
        if !self.accepting.load(Ordering::Acquire) {
            return Err("daemon is shutting down".into());
        }
        if duration_ms == 0 || duration_ms > MAX_LID_LEASE_MS {
            return Err("lid lease duration must be between 1 ms and 4 hours".into());
        }

        let sampled_epoch = self.state.lock().map_err(lock_error)?.lease_epoch;
        let mut thermal = self
            .thermal
            .thermal_state()
            .map_err(|error| format!("thermal state unavailable: {error}"))?;
        if matches!(
            thermal,
            ThermalState::Serious | ThermalState::Critical | ThermalState::Unknown
        ) {
            return Err(format!(
                "thermal state {thermal:?} does not permit a new lid lease"
            ));
        }
        let mut battery = self
            .power
            .battery_state()
            .map_err(|error| format!("battery state unavailable: {error}"))?;
        let _operation = self.operation.lock().map_err(lock_error)?;
        if !self.accepting.load(Ordering::Acquire) {
            return Err("daemon is shutting down".into());
        }
        thermal = self
            .thermal
            .thermal_state()
            .map_err(|error| format!("thermal state unavailable: {error}"))?;
        if matches!(
            thermal,
            ThermalState::Serious | ThermalState::Critical | ThermalState::Unknown
        ) {
            return Err(format!(
                "thermal state {thermal:?} does not permit a new lid lease"
            ));
        }

        let mut state = self.state.lock().map_err(lock_error)?;
        if state.lease_epoch != sampled_epoch {
            return Err("lease state changed during safety probes; retry acquisition".into());
        }
        state.latest_thermal = Some(thermal);
        state.latest_battery = Some(battery);
        if state.foreign_state {
            let externally_restored = !self.power.sleep_disabled().map_err(io_string)?
                && !self.power.sentinel_exists().map_err(io_string)?;
            if externally_restored {
                state.foreign_state = false;
            } else {
                return Err("foreign SleepDisabled state is active".into());
            }
        }
        if state.leases.len() >= MAX_ACTIVE_LID_LEASES {
            return Err(format!(
                "at most {MAX_ACTIVE_LID_LEASES} lid leases may be active"
            ));
        }
        if let Some(problem) = &state.unhealthy {
            return Err(format!("daemon is unhealthy: {problem}"));
        }
        if state.policy.is_latched() {
            return Err("thermal safety latch is active".into());
        }
        if let Some(reason) = state.policy.observe_battery(Ok(battery), false) {
            return Err(format!("battery safety refused the lease: {reason:?}"));
        }

        let first = state.leases.is_empty();
        if first {
            if self.power.sleep_disabled().map_err(io_string)? {
                state.foreign_state = true;
                return Err("foreign SleepDisabled state appeared before acquisition".into());
            }
            let instance = format!(
                "{}-{}",
                std::process::id(),
                SystemTime::now()
                    .duration_since(UNIX_EPOCH)
                    .unwrap_or_default()
                    .as_nanos()
            );
            // Persist ownership before changing global power state. A crash in
            // the following mutation then leaves startup recovery enough
            // evidence to restore normal sleep without claiming foreign state.
            if let Err(error) = self.mutate_power(|| self.power.write_sentinel(&instance)) {
                let cleanup_verified = matches!(self.power.sentinel_exists(), Ok(false));
                if !cleanup_verified {
                    let problem =
                        format!("sentinel write failed and cleanup could not be verified: {error}");
                    state.unhealthy = Some(problem.clone());
                    self.accepting.store(false, Ordering::Release);
                    self.fatal.store(true, Ordering::Release);
                    return Err(problem);
                }
                return Err(format!("could not write sleepctl sentinel: {error}"));
            }
            if let Err(error) = self.mutate_power(|| self.power.set_sleep_disabled(true)) {
                let rollback = self
                    .mutate_power(|| self.power.set_sleep_disabled(false))
                    .and_then(|()| self.mutate_power(|| self.power.remove_sentinel()));
                let problem = match rollback {
                    Ok(()) => format!(
                        "failed to enable and verify SleepDisabled; rollback succeeded: {error}"
                    ),
                    Err(rollback_error) => format!(
                        "failed to enable and verify SleepDisabled: {error}; \
                         rollback also failed: {rollback_error}"
                    ),
                };
                state.unhealthy = Some(problem.clone());
                self.accepting.store(false, Ordering::Release);
                self.fatal.store(true, Ordering::Release);
                return Err(format!(
                    "failed to enable and verify SleepDisabled: {problem}"
                ));
            }
            thermal = match self.thermal.thermal_state() {
                Ok(thermal) => thermal,
                Err(error) => {
                    drop(state);
                    let restore_result = self.restore();
                    return match restore_result {
                        Ok(()) => Err(format!(
                            "thermal state unavailable after power mutation: {error}"
                        )),
                        Err(restore_error) => Err(format!(
                            "thermal state unavailable after power mutation: {error}; \
                             restore also failed: {restore_error}"
                        )),
                    };
                }
            };
            if matches!(
                thermal,
                ThermalState::Serious | ThermalState::Critical | ThermalState::Unknown
            ) {
                drop(state);
                self.restore()?;
                return Err(format!(
                    "thermal state {thermal:?} became unsafe during acquisition"
                ));
            }
            battery = match self.power.battery_state() {
                Ok(battery) => battery,
                Err(error) => {
                    drop(state);
                    let restore_result = self.restore();
                    return match restore_result {
                        Ok(()) => Err(format!(
                            "battery state unavailable after power mutation: {error}"
                        )),
                        Err(restore_error) => Err(format!(
                            "battery state unavailable after power mutation: {error}; \
                             restore also failed: {restore_error}"
                        )),
                    };
                }
            };
            if let Some(reason) = state.policy.observe_battery(Ok(battery), false) {
                drop(state);
                self.restore()?;
                return Err(format!(
                    "battery safety became unsafe during acquisition: {reason:?}"
                ));
            }
        }
        if !self.accepting.load(Ordering::Acquire) {
            drop(state);
            if first {
                self.restore()?;
            }
            return Err("daemon is shutting down".into());
        }
        state.latest_thermal = Some(thermal);
        state.latest_battery = Some(battery);

        let id = format!(
            "{}-{}",
            std::process::id(),
            self.next_lease.fetch_add(1, Ordering::Relaxed)
        );
        let now_ms = self.now_ms();
        state
            .leases
            .acquire(Lease {
                id: id.clone(),
                deadline_ms: now_ms.saturating_add(duration_ms),
                heartbeat_deadline_ms: now_ms.saturating_add(HEARTBEAT_TIMEOUT_MS),
            })
            .map_err(str::to_owned)?;
        // Acceptance is queued while the operation lock is still held and
        // before this sink becomes visible to watchdogs. This guarantees that
        // no warning or terminal event can overtake LeaseAccepted.
        let acceptance = sink
            .send(ServerMessage::Reply(Reply::LeaseAccepted {
                lease_id: id.clone(),
            }))
            .and_then(|()| {
                if thermal == ThermalState::Fair {
                    sink.send(ServerMessage::Event(Event::Warning { thermal }))
                } else {
                    Ok(())
                }
            });
        if let Err(error) = acceptance {
            state.leases.release(&id);
            drop(state);
            if first {
                self.restore()?;
            }
            return Err(format!("could not acknowledge lease acquisition: {error}"));
        }
        state.lease_epoch = state.lease_epoch.wrapping_add(1);
        state
            .connections
            .insert(id.clone(), ConnectedLease { sink });
        Ok(id)
    }

    fn heartbeat(&self, lease_id: &str) -> Result<(), String> {
        let _operation = self.operation.lock().map_err(lock_error)?;
        let mut state = self.state.lock().map_err(lock_error)?;
        if state
            .leases
            .heartbeat(lease_id, self.now_ms().saturating_add(HEARTBEAT_TIMEOUT_MS))
        {
            Ok(())
        } else {
            Err("unknown lease".into())
        }
    }

    fn release(&self, lease_id: &str) -> Result<(), String> {
        let _operation = self.operation.lock().map_err(lock_error)?;
        let mut state = self.state.lock().map_err(lock_error)?;
        let previous_len = state.leases.len();
        let became_empty = state.leases.release(lease_id);
        if state.leases.len() != previous_len {
            state.lease_epoch = state.lease_epoch.wrapping_add(1);
        }
        state.connections.remove(lease_id);
        drop(state);
        if became_empty {
            self.restore()?;
        }
        Ok(())
    }

    fn restore(&self) -> Result<(), String> {
        if let Err(error) = self.mutate_power(|| self.power.set_sleep_disabled(false)) {
            let message = format!("failed to restore and verify SleepDisabled: {error}");
            self.mark_fatal(message.clone());
            return Err(message);
        }
        // Keep the sentinel until the read-backed restore has succeeded. Its
        // presence is the crash-recovery obligation, not merely a lease flag.
        if let Err(error) = self.mutate_power(|| self.power.remove_sentinel()) {
            let message = format!("restored SleepDisabled but could not remove sentinel: {error}");
            self.mark_fatal(message.clone());
            return Err(message);
        }
        Ok(())
    }

    fn mutate_power<T>(&self, operation: impl FnOnce() -> io::Result<T>) -> io::Result<T> {
        // An odd epoch marks an in-progress global power-state mutation.
        // Diagnostics can take a coherent snapshot without delaying the
        // thermal watchdog on the operation mutex.
        self.power_epoch.fetch_add(1, Ordering::AcqRel);
        let result = operation();
        self.power_epoch.fetch_add(1, Ordering::Release);
        result
    }

    #[cfg(test)]
    fn watchdog_tick(&self) -> Result<(), String> {
        if self.thermal_watchdog_tick()? {
            return Ok(());
        }
        self.battery_watchdog_tick()
    }

    fn thermal_watchdog_tick(&self) -> Result<bool, String> {
        let _operation = self.operation.lock().map_err(lock_error)?;
        let now_ms = self.now_ms();
        let thermal = self.thermal.thermal_state().map_err(|_| ());

        let mut state = self.state.lock().map_err(lock_error)?;
        let had_leases = !state.leases.is_empty();
        let previous_thermal = state.latest_thermal;
        if let Ok(value) = thermal {
            state.latest_thermal = Some(value);
        }

        let thermal_decision = state.policy.observe_thermal(now_ms, thermal, had_leases);
        if let ThermalDecision::Trip(reason) = &thermal_decision {
            let revoked = state.leases.revoke_all();
            if !revoked.is_empty() {
                state.lease_epoch = state.lease_epoch.wrapping_add(1);
            }
            let writers = take_connections(&mut state.connections, &revoked);
            drop(state);
            notify_trip(&writers, reason.clone());
            let restore_result = self.restore();
            notify_restore_result(&writers, restore_result.is_ok());
            restore_result?;
            self.request_sleep_if_lid_closed()?;
            return Ok(true);
        }

        if let ThermalDecision::Warn(thermal) = thermal_decision
            && previous_thermal != Some(thermal)
        {
            eprintln!("sleepctld: thermal warning: {thermal:?}");
            for connection in state.connections.values() {
                let _ = send_server_message(
                    &connection.sink,
                    ServerMessage::Event(Event::Warning { thermal }),
                );
            }
        }

        let expiry_now_ms = self.now_ms();
        let expired_details = state
            .leases
            .values()
            .filter(|lease| {
                expiry_now_ms >= lease.deadline_ms || expiry_now_ms >= lease.heartbeat_deadline_ms
            })
            .map(|lease| (lease.id.clone(), expiry_now_ms >= lease.deadline_ms))
            .collect::<Vec<_>>();
        let expired = state.leases.expire(expiry_now_ms);
        if !expired.is_empty() {
            state.lease_epoch = state.lease_epoch.wrapping_add(1);
        }
        let became_empty = had_leases && state.leases.is_empty();
        let writers = take_connections(&mut state.connections, &expired);
        drop(state);

        let expired_by_id = expired_details.into_iter().collect::<BTreeMap<_, _>>();
        let restore_result = if became_empty { self.restore() } else { Ok(()) };
        for (id, writer) in writers {
            let deadline = expired_by_id.get(&id).copied().unwrap_or(false);
            let event = if restore_result.is_err() {
                Event::Trip {
                    lease_id: id,
                    reason: TripReason::PowerRestoreFailed,
                }
            } else if deadline {
                Event::LeaseExpired { lease_id: id }
            } else {
                Event::LeaseRevoked { lease_id: id }
            };
            let _ = send_server_message(&writer, ServerMessage::Event(event));
        }
        restore_result.map(|()| false)
    }

    fn battery_watchdog_tick(&self) -> Result<(), String> {
        let sampled_epoch = {
            let state = self.state.lock().map_err(lock_error)?;
            if state.leases.is_empty() {
                return Ok(());
            }
            state.lease_epoch
        };
        // The potentially slow pmset probe runs outside the operation lock and
        // on a separate watchdog thread. The probe itself therefore does not
        // hold the operation lock or stretch the next thermal sample.
        let battery = self.power.battery_state().map_err(|_| ());
        let _operation = self.operation.lock().map_err(lock_error)?;
        let mut state = self.state.lock().map_err(lock_error)?;
        if state.lease_epoch != sampled_epoch {
            return Ok(());
        }
        let had_leases = !state.leases.is_empty();
        if let Ok(value) = battery {
            state.latest_battery = Some(value);
        }
        if let Some(reason) = state.policy.observe_battery(battery, had_leases)
            && had_leases
        {
            let revoked = state.leases.revoke_all();
            if !revoked.is_empty() {
                state.lease_epoch = state.lease_epoch.wrapping_add(1);
            }
            let writers = take_connections(&mut state.connections, &revoked);
            drop(state);
            notify_trip(&writers, reason);
            let restore_result = self.restore();
            notify_restore_result(&writers, restore_result.is_ok());
            restore_result?;
            self.request_sleep_if_lid_closed()?;
        }
        Ok(())
    }

    fn stop_all(&self) -> Result<usize, String> {
        let _operation = self.operation.lock().map_err(lock_error)?;
        let mut state = self.state.lock().map_err(lock_error)?;
        let ids = state.leases.revoke_all();
        if !ids.is_empty() {
            state.lease_epoch = state.lease_epoch.wrapping_add(1);
        }
        let count = ids.len();
        let writers = take_connections(&mut state.connections, &ids);
        drop(state);
        for (id, writer) in &writers {
            let _ = send_server_message(
                writer,
                ServerMessage::Event(Event::OperatorStopped {
                    lease_id: id.clone(),
                }),
            );
        }
        let restore_result = if count > 0 { self.restore() } else { Ok(()) };
        notify_restore_result(&writers, restore_result.is_ok());
        restore_result.map(|()| count)
    }

    fn shutdown(&self) -> Result<(), String> {
        self.stop_accepting();
        let stop_result = self.stop_all().map(|_| ());
        let _operation = self.operation.lock().map_err(lock_error)?;
        let cleanup_result = match self.power.sentinel_exists() {
            Ok(true) => self.restore(),
            Ok(false) => Ok(()),
            Err(error) => Err(format!("cannot inspect cleanup sentinel: {error}")),
        };
        stop_result.and(cleanup_result)
    }

    fn stop_accepting(&self) {
        self.accepting.store(false, Ordering::Release);
        // Drain any acquisition that was already inside the serialized
        // operation. Such an acquisition rechecks the gate before publishing
        // its lease and rolls back a first-lease power mutation.
        drop(
            self.operation
                .lock()
                .unwrap_or_else(|error| error.into_inner()),
        );
    }

    fn mark_fatal(&self, message: String) {
        self.accepting.store(false, Ordering::Release);
        self.fatal.store(true, Ordering::Release);
        if let Ok(mut state) = self.state.lock() {
            state.unhealthy = Some(message);
        }
    }

    fn request_sleep_if_lid_closed(&self) -> Result<(), String> {
        let result = self
            .power
            .lid_closed()
            .map_err(|error| format!("cannot inspect lid after safety trip: {error}"))
            .and_then(|closed| {
                if closed {
                    self.power
                        .sleep_now()
                        .map_err(|error| format!("cannot request sleep after safety trip: {error}"))
                } else {
                    Ok(())
                }
            });
        if let Err(message) = &result {
            self.mark_fatal(message.clone());
        }
        result
    }

    fn fatal_message(&self) -> Option<String> {
        if !self.fatal.load(Ordering::Acquire) {
            return None;
        }
        let state = self.state.lock().unwrap_or_else(|error| error.into_inner());
        Some(
            state
                .unhealthy
                .clone()
                .unwrap_or_else(|| "fatal daemon health failure".into()),
        )
    }

    fn recover(&self) -> Result<(), RecoverError> {
        let _operation = self
            .operation
            .lock()
            .map_err(lock_error)
            .map_err(RecoverError::Cleanup)?;
        let mut state = self
            .state
            .lock()
            .map_err(lock_error)
            .map_err(RecoverError::Cleanup)?;
        if !state.leases.is_empty() {
            return Err(RecoverError::Refused(
                "cannot recover while leases are active".into(),
            ));
        }
        let sentinel = self
            .power
            .sentinel_exists()
            .map_err(io_string)
            .map_err(RecoverError::Cleanup)?;
        let sleep_disabled = self
            .power
            .sleep_disabled()
            .map_err(io_string)
            .map_err(RecoverError::Cleanup)?;
        reconcile_foreign_state(&mut state, Some(sleep_disabled), Some(sentinel));
        if !sentinel {
            if state.foreign_state {
                return Err(RecoverError::Refused(
                    "refusing to alter foreign SleepDisabled state".into(),
                ));
            }
            return Ok(());
        }
        drop(state);
        self.restore().map_err(RecoverError::Cleanup)
    }

    fn status(&self) -> Status {
        let now_ms = self.now_ms();
        let (sleep_disabled, sentinel) = self.power_snapshot();
        let sleep_disabled = sleep_disabled.ok();
        let sentinel = sentinel.ok();
        let mut state = self.state.lock().unwrap_or_else(|error| error.into_inner());
        reconcile_foreign_state(&mut state, sleep_disabled, sentinel);
        Status {
            schema_version: PROTOCOL_VERSION,
            daemon_reachable: true,
            healthy: state.unhealthy.is_none(),
            health_problem: state.unhealthy.clone(),
            thermal: state.latest_thermal,
            thermal_latched: state.policy.is_latched(),
            battery: state.latest_battery,
            sleep_disabled,
            foreign_state: state.foreign_state,
            active_leases: state
                .leases
                .values()
                .map(|lease| LeaseStatus {
                    id: lease.id.clone(),
                    remaining_ms: lease.deadline_ms.saturating_sub(now_ms),
                })
                .collect(),
            last_trip: state.policy.last_trip.clone(),
        }
    }

    fn doctor(&self) -> DoctorStatus {
        let mut problems = Vec::new();
        let thermal_available = self.thermal.thermal_state().is_ok();
        if !thermal_available {
            problems.push("Foundation thermal state is unavailable".into());
        }
        let (sleep_disabled_result, sentinel_result) = self.power_snapshot();
        let sleep_disabled = match sleep_disabled_result {
            Ok(value) => Some(value),
            Err(error) => {
                problems.push(format!("cannot read SleepDisabled: {error}"));
                None
            }
        };
        let sentinel = match sentinel_result {
            Ok(value) => Some(value),
            Err(error) => {
                problems.push(format!("cannot inspect sleepctl sentinel: {error}"));
                None
            }
        };
        let fixed_commands_available = match self.power.fixed_commands_available() {
            Ok(value) => value,
            Err(error) => {
                problems.push(format!("cannot validate fixed power commands: {error}"));
                false
            }
        };
        if !fixed_commands_available {
            problems.push("pmset or ioreg is missing, mutable, or not root-owned".into());
        }
        let battery_available = match self.power.battery_state() {
            Ok(_) => true,
            Err(error) => {
                problems.push(format!("cannot read battery state with pmset: {error}"));
                false
            }
        };
        let lid_available = match self.power.lid_closed() {
            Ok(_) => true,
            Err(error) => {
                problems.push(format!("cannot read lid state with ioreg: {error}"));
                false
            }
        };
        let power_commands_available = fixed_commands_available
            && sleep_disabled.is_some()
            && battery_available
            && lid_available;
        let state_directory_secure = self.power.state_directory_secure().unwrap_or(false);
        if !state_directory_secure {
            problems.push("state directory is missing or not mode 0700".into());
        }
        let mut state = self.state.lock().unwrap_or_else(|error| error.into_inner());
        reconcile_foreign_state(&mut state, sleep_disabled, sentinel);
        if state.foreign_state {
            problems.push("foreign SleepDisabled state is active".into());
        }
        if let Some(problem) = &state.unhealthy {
            problems.push(format!("daemon is unhealthy: {problem}"));
        }
        DoctorStatus {
            daemon_reachable: true,
            daemon_healthy: state.unhealthy.is_none(),
            health_problem: state.unhealthy.clone(),
            peer_authenticated: true,
            thermal_available,
            power_commands_available,
            state_directory_secure,
            sleep_disabled,
            foreign_state: state.foreign_state,
            problems,
        }
    }

    fn power_snapshot(&self) -> (io::Result<bool>, io::Result<bool>) {
        const SNAPSHOT_ATTEMPTS: usize = 3;
        for _ in 0..SNAPSHOT_ATTEMPTS {
            let before = self.power_epoch.load(Ordering::Acquire);
            if !before.is_multiple_of(2) {
                thread::yield_now();
                continue;
            }
            let sleep_disabled = self.power.sleep_disabled();
            let sentinel = self.power.sentinel_exists();
            let after = self.power_epoch.load(Ordering::Acquire);
            if before == after {
                return (sleep_disabled, sentinel);
            }
        }
        (
            Err(io::Error::new(
                io::ErrorKind::WouldBlock,
                "power state changed during diagnostic snapshot",
            )),
            Err(io::Error::new(
                io::ErrorKind::WouldBlock,
                "sentinel changed during diagnostic snapshot",
            )),
        )
    }
}

enum RecoverError {
    Refused(String),
    Cleanup(String),
}

fn reconcile_foreign_state(
    state: &mut RuntimeState,
    sleep_disabled: Option<bool>,
    sentinel: Option<bool>,
) {
    if !state.leases.is_empty() || sentinel != Some(false) {
        return;
    }
    if let Some(sleep_disabled) = sleep_disabled {
        state.foreign_state = sleep_disabled;
    }
}

fn take_connections(
    connections: &mut BTreeMap<String, ConnectedLease>,
    ids: &[String],
) -> Vec<(String, ClientSink)> {
    ids.iter()
        .filter_map(|id| {
            connections
                .remove(id)
                .map(|connection| (id.clone(), connection.sink))
        })
        .collect()
}

fn notify_trip(sinks: &[(String, ClientSink)], reason: TripReason) {
    for (id, sink) in sinks {
        let _ = send_server_message(
            sink,
            ServerMessage::Event(Event::Trip {
                lease_id: id.clone(),
                reason: reason.clone(),
            }),
        );
    }
}

fn notify_restore_result(sinks: &[(String, ClientSink)], restored: bool) {
    for (id, sink) in sinks {
        let event = if restored {
            Event::PowerRestored {
                lease_id: id.clone(),
            }
        } else {
            Event::Trip {
                lease_id: id.clone(),
                reason: TripReason::PowerRestoreFailed,
            }
        };
        let _ = send_server_message(sink, ServerMessage::Event(event));
    }
}

fn send_server_message(sink: &ClientSink, message: ServerMessage) -> io::Result<()> {
    sink.send(message)
}

fn handle_client(stream: UnixStream, allowed_uid: u32, manager: Arc<Manager>) -> io::Result<()> {
    // Darwin inherits O_NONBLOCK from the listening socket on accept. Client
    // handlers use bounded blocking I/O, so normalize the accepted descriptor
    // before an empty read can be mistaken for a failed connection.
    stream.set_nonblocking(false)?;
    let peer_uid = peer_uid(&stream)?;
    if peer_uid != allowed_uid {
        return Err(io::Error::new(
            io::ErrorKind::PermissionDenied,
            "peer UID is not authorized",
        ));
    }

    stream.set_read_timeout(Some(CLIENT_READ_TIMEOUT))?;
    let sink = ClientSink::new(&stream)?;
    let mut reader = stream;
    let mut owned_lease: Option<String> = None;
    let result = loop {
        let envelope = match read_frame::<Envelope<Request>>(&mut reader) {
            Ok(envelope) => envelope,
            Err(error) if error.kind() == io::ErrorKind::UnexpectedEof => break Ok(()),
            Err(error) => break Err(error),
        };
        let request = match require_version(envelope) {
            Ok(request) => request,
            Err(error) => break Err(error),
        };
        let reply = match request {
            Request::Acquire { duration_ms } => {
                if owned_lease.is_some() {
                    Reply::Error {
                        code: "duplicate_acquire".into(),
                        message: "one connection may own only one lease".into(),
                    }
                } else {
                    match manager.acquire(duration_ms, sink.clone()) {
                        Ok(lease_id) => {
                            owned_lease = Some(lease_id);
                            continue;
                        }
                        Err(message) => Reply::Error {
                            code: "acquire_refused".into(),
                            message,
                        },
                    }
                }
            }
            Request::Heartbeat { lease_id } => {
                if owned_lease.as_deref() != Some(lease_id.as_str()) {
                    Reply::Error {
                        code: "lease_not_owned".into(),
                        message: "connection does not own this lease".into(),
                    }
                } else {
                    match manager.heartbeat(&lease_id) {
                        Ok(()) => Reply::HeartbeatAck,
                        Err(message) => Reply::Error {
                            code: "heartbeat_failed".into(),
                            message,
                        },
                    }
                }
            }
            Request::Release { lease_id } => {
                if owned_lease.as_deref() != Some(lease_id.as_str()) {
                    Reply::Error {
                        code: "lease_not_owned".into(),
                        message: "connection does not own this lease".into(),
                    }
                } else {
                    let result = manager.release(&lease_id);
                    owned_lease = None;
                    match result {
                        Ok(()) => Reply::Released,
                        Err(message) => Reply::Error {
                            code: "release_failed".into(),
                            message,
                        },
                    }
                }
            }
            Request::Status => Reply::Status(manager.status()),
            Request::Doctor => Reply::Doctor(manager.doctor()),
            Request::StopAll => match manager.stop_all() {
                Ok(leases) => Reply::Stopped { leases },
                Err(message) => Reply::Error {
                    code: "stop_failed".into(),
                    message,
                },
            },
            Request::Recover => match manager.recover() {
                Ok(()) => Reply::Recovered,
                Err(RecoverError::Refused(message)) => Reply::Error {
                    code: "recover_refused".into(),
                    message,
                },
                Err(RecoverError::Cleanup(message)) => Reply::Error {
                    code: "recover_failed".into(),
                    message,
                },
            },
        };
        if let Err(error) = send_server_message(&sink, ServerMessage::Reply(reply)) {
            break Err(error);
        }
    };
    if let Some(lease_id) = owned_lease {
        let _ = manager.release(&lease_id);
    }
    result
}

fn peer_uid(stream: &UnixStream) -> io::Result<u32> {
    let mut effective_uid: libc::uid_t = 0;
    let mut effective_gid: libc::gid_t = 0;
    // SAFETY: getpeereid writes exactly one uid_t and one gid_t to valid
    // pointers and does not retain them after the call.
    let result = unsafe {
        libc::getpeereid(
            std::os::fd::AsRawFd::as_raw_fd(stream),
            &mut effective_uid,
            &mut effective_gid,
        )
    };
    if result == 0 {
        Ok(effective_uid)
    } else {
        Err(io::Error::last_os_error())
    }
}

fn resolve_user_uid(username: &str) -> io::Result<u32> {
    let username = CString::new(username)
        .map_err(|_| io::Error::new(io::ErrorKind::InvalidInput, "username contains NUL"))?;
    // SAFETY: getpwnam reads a NUL-terminated string and returns a pointer to
    // libc-owned storage. We copy pw_uid before making another libc call.
    let entry = unsafe { libc::getpwnam(username.as_ptr()) };
    if entry.is_null() {
        return Err(io::Error::new(
            io::ErrorKind::NotFound,
            "allowed user does not exist",
        ));
    }
    Ok(unsafe { (*entry).pw_uid })
}

fn resolve_staff_gid() -> io::Result<u32> {
    let group = c"staff";
    // SAFETY: getgrnam reads a static NUL-terminated string. We copy gr_gid
    // before making another libc call.
    let entry = unsafe { libc::getgrnam(group.as_ptr()) };
    if entry.is_null() {
        return Err(io::Error::new(
            io::ErrorKind::NotFound,
            "staff group missing",
        ));
    }
    Ok(unsafe { (*entry).gr_gid })
}

fn prepare_socket(path: &Path) -> io::Result<UnixListener> {
    match fs::symlink_metadata(path) {
        Ok(metadata) if metadata.file_type().is_socket() && metadata.uid() == effective_uid() => {
            fs::remove_file(path)?;
        }
        Ok(_) => {
            return Err(io::Error::other(
                "refusing to replace non-owned or non-socket path",
            ));
        }
        Err(error) if error.kind() == io::ErrorKind::NotFound => {}
        Err(error) => return Err(error),
    }
    let listener = UnixListener::bind(path)?;
    let group = resolve_staff_gid()?;
    // SAFETY: path is a valid NUL-free Rust path created by this process; the
    // CString remains alive through chown.
    let c_path = CString::new(path.as_os_str().as_encoded_bytes())
        .map_err(|_| io::Error::new(io::ErrorKind::InvalidInput, "socket path contains NUL"))?;
    if unsafe { libc::chown(c_path.as_ptr(), 0, group) } != 0 {
        return Err(io::Error::last_os_error());
    }
    fs::set_permissions(path, fs::Permissions::from_mode(0o660))?;
    listener.set_nonblocking(true)?;
    Ok(listener)
}

fn acquire_instance_lock(path: &Path, owner_uid: u32) -> io::Result<File> {
    let file = OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .mode(0o600)
        .custom_flags(libc::O_NOFOLLOW)
        .open(path)?;
    let metadata = file.metadata()?;
    if !metadata.is_file()
        || metadata.uid() != owner_uid
        || metadata.permissions().mode() & 0o077 != 0
    {
        return Err(io::Error::new(
            io::ErrorKind::PermissionDenied,
            "sleepctld lock is not a private daemon-owned file",
        ));
    }
    // SAFETY: flock operates on this live file descriptor and retains no
    // pointer. The File remains alive for the daemon lifetime.
    if unsafe { libc::flock(file.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) } != 0 {
        let error = io::Error::last_os_error();
        return Err(if error.raw_os_error() == Some(libc::EWOULDBLOCK) {
            io::Error::new(
                io::ErrorKind::AlreadyExists,
                "another sleepctld instance is already running",
            )
        } else {
            error
        });
    }
    Ok(file)
}

fn lock_error<T>(_: std::sync::PoisonError<T>) -> String {
    "daemon state lock is poisoned".into()
}

fn effective_uid() -> u32 {
    // SAFETY: geteuid has no arguments and reads process credentials only.
    unsafe { libc::geteuid() }
}

fn io_string(error: io::Error) -> String {
    error.to_string()
}

pub fn run() -> ExitCode {
    let args = Args::parse();
    match run_inner(&args.allowed_user) {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("sleepctld: {error}");
            ExitCode::from(1)
        }
    }
}

fn run_inner(allowed_user: &str) -> io::Result<()> {
    let allowed_uid = resolve_user_uid(allowed_user)?;
    let power = Arc::new(SystemPowerController::default());
    power.ensure_state_directory()?;
    let _instance_lock = acquire_instance_lock(Path::new(LOCK_PATH), 0)?;
    let manager = Arc::new(
        Manager::new(power, Arc::new(FoundationThermalSource))
            .map_err(|error| io::Error::other(format!("startup recovery failed: {error}")))?,
    );
    let socket_path = Path::new(SOCKET_PATH);
    let listener = prepare_socket(socket_path)?;
    let terminating = Arc::new(AtomicBool::new(false));
    let active_connections = Arc::new(AtomicUsize::new(0));
    signal_hook::flag::register(signal_hook::consts::SIGTERM, Arc::clone(&terminating))?;
    signal_hook::flag::register(signal_hook::consts::SIGINT, Arc::clone(&terminating))?;

    let thermal_manager = Arc::clone(&manager);
    let thermal_terminating = Arc::clone(&terminating);
    let thermal_watchdog = thread::spawn(move || {
        while !thermal_terminating.load(Ordering::Relaxed)
            && thermal_manager.fatal_message().is_none()
        {
            if let Err(error) = thermal_manager.thermal_watchdog_tick() {
                eprintln!("sleepctld: thermal watchdog: {error}");
                if thermal_manager.fatal_message().is_some() {
                    break;
                }
            }
            thread::sleep(Duration::from_millis(THERMAL_POLL_INTERVAL_MS));
        }
    });
    let battery_manager = Arc::clone(&manager);
    let battery_terminating = Arc::clone(&terminating);
    let battery_watchdog = thread::spawn(move || {
        while !battery_terminating.load(Ordering::Relaxed)
            && battery_manager.fatal_message().is_none()
        {
            if let Err(error) = battery_manager.battery_watchdog_tick() {
                eprintln!("sleepctld: battery watchdog: {error}");
                if battery_manager.fatal_message().is_some() {
                    break;
                }
            }
            thread::sleep(Duration::from_millis(THERMAL_POLL_INTERVAL_MS));
        }
    });

    while !terminating.load(Ordering::Relaxed) && manager.fatal_message().is_none() {
        match listener.accept() {
            Ok((stream, _)) => {
                let previous = active_connections.fetch_add(1, Ordering::AcqRel);
                if previous >= MAX_CLIENT_CONNECTIONS {
                    active_connections.fetch_sub(1, Ordering::AcqRel);
                    let _ = stream.shutdown(Shutdown::Both);
                    continue;
                }
                let manager = Arc::clone(&manager);
                let active_connections = Arc::clone(&active_connections);
                thread::spawn(move || {
                    if let Err(error) = handle_client(stream, allowed_uid, manager) {
                        eprintln!("sleepctld: client: {error}");
                    }
                    active_connections.fetch_sub(1, Ordering::AcqRel);
                });
            }
            Err(error) if error.kind() == io::ErrorKind::WouldBlock => {
                thread::sleep(Duration::from_millis(100));
            }
            Err(error) => {
                terminating.store(true, Ordering::Relaxed);
                let _ = manager.shutdown();
                let _ = fs::remove_file(socket_path);
                return Err(error);
            }
        }
    }

    terminating.store(true, Ordering::Relaxed);
    // Existing authenticated connections may still be processing requests
    // while watchdog threads wind down. Close the acquisition gate before
    // joining them so shutdown cannot re-enable global power state.
    manager.stop_accepting();
    let _ = thermal_watchdog.join();
    let _ = battery_watchdog.join();
    let shutdown_result = manager.shutdown();
    let fatal_message = manager.fatal_message();
    fs::remove_file(socket_path)?;
    if let Some(message) = fatal_message {
        return Err(io::Error::other(message));
    }
    shutdown_result.map_err(io::Error::other)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::BatterySource;
    use std::collections::VecDeque;
    use std::io::Write as _;
    use std::sync::atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering};

    struct FakeThermal {
        state: Mutex<Result<ThermalState, ()>>,
    }

    impl ThermalSource for FakeThermal {
        fn thermal_state(&self) -> io::Result<ThermalState> {
            self.state
                .lock()
                .unwrap()
                .map_err(|()| io::Error::other("thermal unavailable"))
        }
    }

    struct SequenceThermal {
        states: Mutex<VecDeque<Result<ThermalState, ()>>>,
    }

    impl ThermalSource for SequenceThermal {
        fn thermal_state(&self) -> io::Result<ThermalState> {
            self.states
                .lock()
                .unwrap()
                .pop_front()
                .unwrap_or(Err(()))
                .map_err(|()| io::Error::other("thermal unavailable"))
        }
    }

    #[derive(Default)]
    struct ManualClock {
        now_ms: AtomicU64,
    }

    impl ManualClock {
        fn set(&self, now_ms: u64) {
            self.now_ms.store(now_ms, Ordering::SeqCst);
        }
    }

    impl Clock for ManualClock {
        fn now_ms(&self) -> u64 {
            self.now_ms.load(Ordering::SeqCst)
        }
    }

    struct FakePower {
        disabled: AtomicBool,
        sentinel: AtomicBool,
        fail_enable: AtomicBool,
        fail_restore: AtomicBool,
        fail_remove: AtomicBool,
        fail_write: AtomicBool,
        leave_failed_write: AtomicBool,
        fail_lid: AtomicBool,
        fail_sleep: AtomicBool,
        block_enable: AtomicBool,
        enable_started: AtomicBool,
        block_sleep_read: AtomicBool,
        sleep_read_started: AtomicBool,
        battery: Mutex<Result<BatteryState, ()>>,
        battery_sequence: Mutex<VecDeque<Result<BatteryState, ()>>>,
        battery_calls: AtomicUsize,
        enable_calls: AtomicUsize,
        restore_calls: AtomicUsize,
    }

    impl FakePower {
        fn new(disabled: bool, sentinel: bool) -> Self {
            Self {
                disabled: AtomicBool::new(disabled),
                sentinel: AtomicBool::new(sentinel),
                fail_enable: AtomicBool::new(false),
                fail_restore: AtomicBool::new(false),
                fail_remove: AtomicBool::new(false),
                fail_write: AtomicBool::new(false),
                leave_failed_write: AtomicBool::new(false),
                fail_lid: AtomicBool::new(false),
                fail_sleep: AtomicBool::new(false),
                block_enable: AtomicBool::new(false),
                enable_started: AtomicBool::new(false),
                block_sleep_read: AtomicBool::new(false),
                sleep_read_started: AtomicBool::new(false),
                battery: Mutex::new(Ok(BatteryState {
                    source: BatterySource::Ac,
                    percent: Some(100),
                })),
                battery_sequence: Mutex::new(VecDeque::new()),
                battery_calls: AtomicUsize::new(0),
                enable_calls: AtomicUsize::new(0),
                restore_calls: AtomicUsize::new(0),
            }
        }
    }

    impl PowerController for FakePower {
        fn ensure_state_directory(&self) -> io::Result<()> {
            Ok(())
        }

        fn fixed_commands_available(&self) -> io::Result<bool> {
            Ok(true)
        }

        fn sleep_disabled(&self) -> io::Result<bool> {
            self.sleep_read_started.store(true, Ordering::SeqCst);
            while self.block_sleep_read.load(Ordering::SeqCst) {
                thread::yield_now();
            }
            Ok(self.disabled.load(Ordering::SeqCst))
        }

        fn set_sleep_disabled(&self, disabled: bool) -> io::Result<()> {
            if disabled {
                self.enable_calls.fetch_add(1, Ordering::SeqCst);
                self.enable_started.store(true, Ordering::SeqCst);
                while self.block_enable.load(Ordering::SeqCst) {
                    thread::yield_now();
                }
                if self.fail_enable.load(Ordering::SeqCst) {
                    return Err(io::Error::other("injected enable failure"));
                }
            } else {
                self.restore_calls.fetch_add(1, Ordering::SeqCst);
                if self.fail_restore.load(Ordering::SeqCst) {
                    return Err(io::Error::other("injected restore failure"));
                }
            }
            self.disabled.store(disabled, Ordering::SeqCst);
            Ok(())
        }

        fn battery_state(&self) -> io::Result<BatteryState> {
            self.battery_calls.fetch_add(1, Ordering::SeqCst);
            if let Some(result) = self.battery_sequence.lock().unwrap().pop_front() {
                return result.map_err(|()| io::Error::other("injected battery failure"));
            }
            self.battery
                .lock()
                .unwrap()
                .map_err(|()| io::Error::other("injected battery failure"))
        }

        fn lid_closed(&self) -> io::Result<bool> {
            if self.fail_lid.load(Ordering::SeqCst) {
                Err(io::Error::other("injected lid failure"))
            } else {
                Ok(self.fail_sleep.load(Ordering::SeqCst))
            }
        }

        fn sleep_now(&self) -> io::Result<()> {
            if self.fail_sleep.load(Ordering::SeqCst) {
                Err(io::Error::other("injected sleep failure"))
            } else {
                Ok(())
            }
        }

        fn sentinel_exists(&self) -> io::Result<bool> {
            Ok(self.sentinel.load(Ordering::SeqCst))
        }

        fn write_sentinel(&self, _instance_id: &str) -> io::Result<()> {
            if self.fail_write.load(Ordering::SeqCst) {
                if self.leave_failed_write.load(Ordering::SeqCst) {
                    self.sentinel.store(true, Ordering::SeqCst);
                }
                return Err(io::Error::other("injected sentinel write failure"));
            }
            if self.sentinel.swap(true, Ordering::SeqCst) {
                Err(io::Error::new(
                    io::ErrorKind::AlreadyExists,
                    "sentinel exists",
                ))
            } else {
                Ok(())
            }
        }

        fn remove_sentinel(&self) -> io::Result<()> {
            if self.fail_remove.load(Ordering::SeqCst) {
                return Err(io::Error::other("injected sentinel removal failure"));
            }
            self.sentinel.store(false, Ordering::SeqCst);
            Ok(())
        }

        fn state_directory_secure(&self) -> io::Result<bool> {
            Ok(true)
        }
    }

    fn nominal_thermal() -> Arc<FakeThermal> {
        Arc::new(FakeThermal {
            state: Mutex::new(Ok(ThermalState::Nominal)),
        })
    }

    fn manager_with_clock(
        power: Arc<FakePower>,
        thermal: Arc<FakeThermal>,
        clock: Arc<ManualClock>,
    ) -> Manager {
        Manager::new_with_clock(power, thermal, clock).unwrap()
    }

    fn sink_pair() -> (ClientSink, UnixStream) {
        let (server, client) = UnixStream::pair().unwrap();
        (ClientSink::new(&server).unwrap(), client)
    }

    fn read_server_message(stream: &mut UnixStream) -> ServerMessage {
        require_version(read_frame::<Envelope<ServerMessage>>(stream).unwrap()).unwrap()
    }

    fn assert_lease_accepted(stream: &mut UnixStream, lease_id: &str) {
        assert_eq!(
            read_server_message(stream),
            ServerMessage::Reply(Reply::LeaseAccepted {
                lease_id: lease_id.into(),
            })
        );
    }

    #[test]
    fn startup_recovers_own_sentinel() {
        let power = Arc::new(FakePower::new(true, true));
        let manager = Manager::new(power.clone(), nominal_thermal()).unwrap();
        assert!(!power.disabled.load(Ordering::SeqCst));
        assert!(!power.sentinel.load(Ordering::SeqCst));
        assert!(!manager.status().foreign_state);
    }

    #[test]
    fn startup_restore_failure_refuses_to_start() {
        let power = Arc::new(FakePower::new(true, true));
        power.fail_restore.store(true, Ordering::SeqCst);
        assert!(Manager::new(power, nominal_thermal()).is_err());
    }

    #[test]
    fn startup_refuses_foreign_state_without_mutating_it() {
        let power = Arc::new(FakePower::new(true, false));
        let manager = Manager::new(power.clone(), nominal_thermal()).unwrap();
        assert!(power.disabled.load(Ordering::SeqCst));
        assert!(manager.status().foreign_state);
    }

    #[test]
    fn foreign_state_clears_after_external_restore() {
        let power = Arc::new(FakePower::new(true, false));
        let manager = Manager::new(power.clone(), nominal_thermal()).unwrap();
        power.disabled.store(false, Ordering::SeqCst);
        let (sink, _client) = sink_pair();
        assert!(manager.acquire(60_000, sink).is_ok());
        assert!(!manager.status().foreign_state);
    }

    #[test]
    fn overlapping_leases_mutate_power_only_at_boundaries() {
        let power = Arc::new(FakePower::new(false, false));
        let manager = Manager::new(power.clone(), nominal_thermal()).unwrap();
        let (first_sink, _first_client) = sink_pair();
        let (second_sink, _second_client) = sink_pair();
        let first = manager.acquire(60_000, first_sink).unwrap();
        let second = manager.acquire(60_000, second_sink).unwrap();
        assert_eq!(power.enable_calls.load(Ordering::SeqCst), 1);
        manager.release(&first).unwrap();
        assert!(power.disabled.load(Ordering::SeqCst));
        assert_eq!(power.restore_calls.load(Ordering::SeqCst), 0);
        manager.release(&second).unwrap();
        assert!(!power.disabled.load(Ordering::SeqCst));
        assert_eq!(power.restore_calls.load(Ordering::SeqCst), 1);
    }

    #[test]
    fn enable_failure_rolls_back_and_marks_daemon_fatal() {
        let power = Arc::new(FakePower::new(false, false));
        power.fail_enable.store(true, Ordering::SeqCst);
        let manager = Manager::new(power.clone(), nominal_thermal()).unwrap();
        let (sink, _client) = sink_pair();
        assert!(manager.acquire(60_000, sink).is_err());
        assert!(!power.disabled.load(Ordering::SeqCst));
        assert!(!power.sentinel.load(Ordering::SeqCst));
        assert!(manager.fatal_message().is_some());
    }

    #[test]
    fn acquisition_rolls_back_if_thermal_state_becomes_unsafe_during_enable() {
        let power = Arc::new(FakePower::new(false, false));
        let thermal = Arc::new(SequenceThermal {
            states: Mutex::new(VecDeque::from([
                Ok(ThermalState::Nominal),
                Ok(ThermalState::Nominal),
                Ok(ThermalState::Critical),
            ])),
        });
        let manager = Manager::new(power.clone(), thermal).unwrap();
        let (sink, _client) = sink_pair();
        assert!(manager.acquire(60_000, sink).is_err());
        assert!(!power.disabled.load(Ordering::SeqCst));
        assert!(!power.sentinel.load(Ordering::SeqCst));
        assert!(manager.status().active_leases.is_empty());
    }

    #[test]
    fn acquisition_rolls_back_if_battery_becomes_unsafe_during_enable() {
        let power = Arc::new(FakePower::new(false, false));
        *power.battery_sequence.lock().unwrap() = VecDeque::from([
            Ok(BatteryState {
                source: BatterySource::Ac,
                percent: Some(100),
            }),
            Ok(BatteryState {
                source: BatterySource::Battery,
                percent: Some(20),
            }),
        ]);
        let manager = Manager::new(power.clone(), nominal_thermal()).unwrap();
        let (sink, _client) = sink_pair();

        assert!(manager.acquire(60_000, sink).is_err());
        assert!(!power.disabled.load(Ordering::SeqCst));
        assert!(!power.sentinel.load(Ordering::SeqCst));
        assert!(manager.status().active_leases.is_empty());
    }

    #[test]
    fn fair_acquisition_warns_only_after_acceptance() {
        let power = Arc::new(FakePower::new(false, false));
        let thermal = Arc::new(FakeThermal {
            state: Mutex::new(Ok(ThermalState::Fair)),
        });
        let manager = Manager::new(power, thermal).unwrap();
        let (sink, mut client) = sink_pair();
        let lease_id = manager.acquire(60_000, sink).unwrap();

        assert_lease_accepted(&mut client, &lease_id);
        assert_eq!(
            read_server_message(&mut client),
            ServerMessage::Event(Event::Warning {
                thermal: ThermalState::Fair,
            })
        );
    }

    #[test]
    fn sentinel_write_failure_is_recoverable_only_after_verified_cleanup() {
        let cleaned = Arc::new(FakePower::new(false, false));
        cleaned.fail_write.store(true, Ordering::SeqCst);
        let manager = Manager::new(cleaned, nominal_thermal()).unwrap();
        let (sink, _client) = sink_pair();
        assert!(manager.acquire(60_000, sink).is_err());
        assert!(manager.fatal_message().is_none());

        let leftover = Arc::new(FakePower::new(false, false));
        leftover.fail_write.store(true, Ordering::SeqCst);
        leftover.leave_failed_write.store(true, Ordering::SeqCst);
        let manager = Manager::new(leftover, nominal_thermal()).unwrap();
        let (sink, _client) = sink_pair();
        assert!(manager.acquire(60_000, sink).is_err());
        assert!(manager.fatal_message().is_some());
    }

    #[test]
    fn restore_failure_marks_daemon_fatal_and_keeps_sentinel() {
        let power = Arc::new(FakePower::new(false, false));
        let manager = Manager::new(power.clone(), nominal_thermal()).unwrap();
        let (sink, _client) = sink_pair();
        let lease = manager.acquire(60_000, sink).unwrap();
        power.fail_restore.store(true, Ordering::SeqCst);
        assert!(manager.release(&lease).is_err());
        assert!(power.sentinel.load(Ordering::SeqCst));
        assert!(manager.fatal_message().is_some());
    }

    #[test]
    fn trip_reports_restore_failure_after_the_initial_reason() {
        let power = Arc::new(FakePower::new(false, false));
        let thermal = nominal_thermal();
        let manager = Manager::new(power.clone(), thermal.clone()).unwrap();
        let (sink, mut client) = sink_pair();
        let lease_id = manager.acquire(60_000, sink).unwrap();
        assert_lease_accepted(&mut client, &lease_id);
        power.fail_restore.store(true, Ordering::SeqCst);
        *thermal.state.lock().unwrap() = Ok(ThermalState::Critical);

        assert!(manager.watchdog_tick().is_err());
        assert_eq!(
            read_server_message(&mut client),
            ServerMessage::Event(Event::Trip {
                lease_id: lease_id.clone(),
                reason: TripReason::ThermalCritical,
            })
        );
        assert_eq!(
            read_server_message(&mut client),
            ServerMessage::Event(Event::Trip {
                lease_id,
                reason: TripReason::PowerRestoreFailed,
            })
        );
        assert!(power.sentinel.load(Ordering::SeqCst));
        assert!(manager.fatal_message().is_some());
    }

    #[test]
    fn critical_trip_revokes_lease_and_restores_sleep() {
        let power = Arc::new(FakePower::new(false, false));
        let thermal = nominal_thermal();
        let manager = Manager::new(power.clone(), thermal.clone()).unwrap();
        let (sink, mut client) = sink_pair();
        let lease_id = manager.acquire(60_000, sink).unwrap();
        assert_lease_accepted(&mut client, &lease_id);
        let battery_calls_before_trip = power.battery_calls.load(Ordering::SeqCst);
        assert!(power.disabled.load(Ordering::SeqCst));

        *thermal.state.lock().unwrap() = Ok(ThermalState::Critical);
        manager.watchdog_tick().unwrap();

        assert_eq!(
            power.battery_calls.load(Ordering::SeqCst),
            battery_calls_before_trip
        );
        assert!(!power.disabled.load(Ordering::SeqCst));
        assert!(!power.sentinel.load(Ordering::SeqCst));
        let message = read_server_message(&mut client);
        assert_eq!(
            message,
            ServerMessage::Event(Event::Trip {
                lease_id: lease_id.clone(),
                reason: TripReason::ThermalCritical,
            })
        );
        assert_eq!(
            read_server_message(&mut client),
            ServerMessage::Event(Event::PowerRestored {
                lease_id: lease_id.clone(),
            })
        );
        assert!(manager.status().active_leases.is_empty());
    }

    #[test]
    fn post_trip_lid_or_sleep_failure_marks_daemon_fatal() {
        for fail_lid in [true, false] {
            let power = Arc::new(FakePower::new(false, false));
            if fail_lid {
                power.fail_lid.store(true, Ordering::SeqCst);
            } else {
                power.fail_sleep.store(true, Ordering::SeqCst);
            }
            let thermal = nominal_thermal();
            let manager = Manager::new(power, thermal.clone()).unwrap();
            let (sink, mut client) = sink_pair();
            let lease_id = manager.acquire(60_000, sink).unwrap();
            assert_lease_accepted(&mut client, &lease_id);
            *thermal.state.lock().unwrap() = Ok(ThermalState::Critical);

            assert!(manager.watchdog_tick().is_err());
            assert!(manager.fatal_message().is_some());
            assert!(matches!(
                read_server_message(&mut client),
                ServerMessage::Event(Event::Trip { .. })
            ));
            assert!(matches!(
                read_server_message(&mut client),
                ServerMessage::Event(Event::PowerRestored { .. })
            ));
        }
    }

    #[test]
    fn sustained_serious_trip_uses_the_monotonic_threshold() {
        let power = Arc::new(FakePower::new(false, false));
        let thermal = nominal_thermal();
        let clock = Arc::new(ManualClock::default());
        let manager = manager_with_clock(power, thermal.clone(), clock.clone());
        let (sink, mut client) = sink_pair();
        let lease_id = manager.acquire(60_000, sink).unwrap();
        assert_lease_accepted(&mut client, &lease_id);
        *thermal.state.lock().unwrap() = Ok(ThermalState::Serious);

        manager.watchdog_tick().unwrap();
        clock.set(14_999);
        manager.watchdog_tick().unwrap();
        assert_eq!(manager.status().active_leases.len(), 1);
        clock.set(15_000);
        manager.watchdog_tick().unwrap();

        assert_eq!(
            read_server_message(&mut client),
            ServerMessage::Event(Event::Warning {
                thermal: ThermalState::Serious,
            })
        );
        assert_eq!(
            read_server_message(&mut client),
            ServerMessage::Event(Event::Trip {
                lease_id: lease_id.clone(),
                reason: TripReason::ThermalSerious,
            })
        );
        assert_eq!(
            read_server_message(&mut client),
            ServerMessage::Event(Event::PowerRestored { lease_id })
        );
    }

    #[test]
    fn low_battery_and_probe_failure_each_trip_an_active_lease() {
        for (battery, reason) in [
            (
                Ok(BatteryState {
                    source: BatterySource::Battery,
                    percent: Some(20),
                }),
                TripReason::LowBattery { percent: 20 },
            ),
            (Err(()), TripReason::BatteryUnavailable),
        ] {
            let power = Arc::new(FakePower::new(false, false));
            let manager = Manager::new(power.clone(), nominal_thermal()).unwrap();
            let (sink, mut client) = sink_pair();
            let lease_id = manager.acquire(60_000, sink).unwrap();
            assert_lease_accepted(&mut client, &lease_id);
            *power.battery.lock().unwrap() = battery;
            manager.watchdog_tick().unwrap();
            assert_eq!(
                read_server_message(&mut client),
                ServerMessage::Event(Event::Trip { lease_id, reason })
            );
            assert!(matches!(
                read_server_message(&mut client),
                ServerMessage::Event(Event::PowerRestored { .. })
            ));
            assert!(!power.disabled.load(Ordering::SeqCst));
        }
    }

    #[test]
    fn deadline_and_heartbeat_timeout_revoke_leases() {
        let power = Arc::new(FakePower::new(false, false));
        let clock = Arc::new(ManualClock::default());
        let manager = manager_with_clock(power.clone(), nominal_thermal(), clock.clone());
        let (sink, mut client) = sink_pair();
        let lease_id = manager.acquire(1_000, sink).unwrap();
        assert_lease_accepted(&mut client, &lease_id);
        manager.heartbeat(&lease_id).unwrap();
        clock.set(1_000);
        manager.watchdog_tick().unwrap();
        assert_eq!(
            read_server_message(&mut client),
            ServerMessage::Event(Event::LeaseExpired { lease_id })
        );
        assert!(!power.disabled.load(Ordering::SeqCst));
        assert!(!power.sentinel.load(Ordering::SeqCst));

        let power = Arc::new(FakePower::new(false, false));
        let clock = Arc::new(ManualClock::default());
        let manager = manager_with_clock(power, nominal_thermal(), clock.clone());
        let (sink, mut client) = sink_pair();
        let lease_id = manager.acquire(60_000, sink).unwrap();
        assert_lease_accepted(&mut client, &lease_id);
        clock.set(HEARTBEAT_TIMEOUT_MS);
        manager.watchdog_tick().unwrap();
        assert_eq!(
            read_server_message(&mut client),
            ServerMessage::Event(Event::LeaseRevoked { lease_id })
        );
    }

    #[test]
    fn malformed_frame_releases_the_connections_owned_lease() {
        let power = Arc::new(FakePower::new(false, false));
        let manager = Arc::new(Manager::new(power.clone(), nominal_thermal()).unwrap());
        let (mut client, server) = UnixStream::pair().unwrap();
        let worker_manager = Arc::clone(&manager);
        let worker = thread::spawn(move || handle_client(server, effective_uid(), worker_manager));

        write_frame(
            &mut client,
            &Envelope::new(Request::Acquire {
                duration_ms: 60_000,
            }),
        )
        .unwrap();
        assert!(matches!(
            read_server_message(&mut client),
            ServerMessage::Reply(Reply::LeaseAccepted { .. })
        ));
        client.write_all(&1_u32.to_be_bytes()).unwrap();
        client.write_all(b"{").unwrap();
        client.shutdown(Shutdown::Write).unwrap();
        assert!(worker.join().unwrap().is_err());
        assert!(!power.disabled.load(Ordering::SeqCst));
        assert!(!power.sentinel.load(Ordering::SeqCst));
        assert!(manager.status().active_leases.is_empty());
    }

    #[test]
    fn unknown_request_type_is_rejected_by_the_production_handler() {
        let power = Arc::new(FakePower::new(false, false));
        let manager = Arc::new(Manager::new(power.clone(), nominal_thermal()).unwrap());
        let (mut client, server) = UnixStream::pair().unwrap();
        let worker = thread::spawn(move || handle_client(server, effective_uid(), manager));
        let payload = br#"{"version":1,"body":{"type":"run_command","pid":1}}"#;

        client
            .write_all(&(u32::try_from(payload.len()).unwrap()).to_be_bytes())
            .unwrap();
        client.write_all(payload).unwrap();
        client.shutdown(Shutdown::Write).unwrap();

        assert_eq!(
            worker.join().unwrap().unwrap_err().kind(),
            io::ErrorKind::InvalidData
        );
        assert_eq!(power.enable_calls.load(Ordering::SeqCst), 0);
    }

    #[test]
    fn truncated_request_is_rejected_by_the_production_handler() {
        let manager = Arc::new(
            Manager::new(Arc::new(FakePower::new(false, false)), nominal_thermal()).unwrap(),
        );
        let (mut client, server) = UnixStream::pair().unwrap();
        let worker = thread::spawn(move || handle_client(server, effective_uid(), manager));

        client.write_all(&10_u32.to_be_bytes()).unwrap();
        client.write_all(b"{").unwrap();
        client.shutdown(Shutdown::Write).unwrap();

        assert_eq!(
            worker.join().unwrap().unwrap_err().kind(),
            io::ErrorKind::InvalidData
        );
    }

    #[test]
    fn release_is_acknowledged_only_after_verified_restore() {
        let power = Arc::new(FakePower::new(false, false));
        let manager = Arc::new(Manager::new(power.clone(), nominal_thermal()).unwrap());
        let (mut client, server) = UnixStream::pair().unwrap();
        let worker_manager = Arc::clone(&manager);
        let worker = thread::spawn(move || handle_client(server, effective_uid(), worker_manager));

        write_frame(
            &mut client,
            &Envelope::new(Request::Acquire {
                duration_ms: 60_000,
            }),
        )
        .unwrap();
        let ServerMessage::Reply(Reply::LeaseAccepted { lease_id }) =
            read_server_message(&mut client)
        else {
            panic!("expected lease acceptance");
        };
        write_frame(&mut client, &Envelope::new(Request::Release { lease_id })).unwrap();
        assert_eq!(
            read_server_message(&mut client),
            ServerMessage::Reply(Reply::Released)
        );
        assert!(!power.disabled.load(Ordering::SeqCst));
        drop(client);
        worker.join().unwrap().unwrap();
    }

    #[test]
    fn handler_normalizes_a_nonblocking_accepted_socket() {
        let power = Arc::new(FakePower::new(false, false));
        let manager = Arc::new(Manager::new(power.clone(), nominal_thermal()).unwrap());
        let (mut client, server) = UnixStream::pair().unwrap();
        server.set_nonblocking(true).unwrap();
        let worker_manager = Arc::clone(&manager);
        let (started_sender, started_receiver) = std::sync::mpsc::channel();
        let worker = thread::spawn(move || {
            started_sender.send(()).unwrap();
            handle_client(server, effective_uid(), worker_manager)
        });
        started_receiver.recv().unwrap();
        let deadline = Instant::now() + Duration::from_secs(1);
        while !worker.is_finished() && Instant::now() < deadline {
            thread::yield_now();
        }
        assert!(
            !worker.is_finished(),
            "handler exited on EAGAIN before a request arrived"
        );

        write_frame(
            &mut client,
            &Envelope::new(Request::Acquire {
                duration_ms: 60_000,
            }),
        )
        .unwrap();
        let ServerMessage::Reply(Reply::LeaseAccepted { lease_id }) =
            read_server_message(&mut client)
        else {
            panic!("expected lease acceptance");
        };
        write_frame(&mut client, &Envelope::new(Request::Release { lease_id })).unwrap();
        assert_eq!(
            read_server_message(&mut client),
            ServerMessage::Reply(Reply::Released)
        );
        drop(client);
        worker.join().unwrap().unwrap();
        assert!(!power.disabled.load(Ordering::SeqCst));
    }

    #[test]
    fn unauthorized_peer_is_rejected_before_power_mutation() {
        let power = Arc::new(FakePower::new(false, false));
        let manager = Arc::new(Manager::new(power.clone(), nominal_thermal()).unwrap());
        let (_client, server) = UnixStream::pair().unwrap();
        let error = handle_client(server, effective_uid().wrapping_add(1), manager).unwrap_err();
        assert_eq!(error.kind(), io::ErrorKind::PermissionDenied);
        assert_eq!(power.enable_calls.load(Ordering::SeqCst), 0);
    }

    #[test]
    fn instance_lock_rejects_a_second_daemon_before_startup_recovery() {
        let temp = tempfile::tempdir().unwrap();
        let path = temp.path().join("daemon.lock");
        let first = acquire_instance_lock(&path, effective_uid()).unwrap();
        let error = acquire_instance_lock(&path, effective_uid()).unwrap_err();
        assert_eq!(error.kind(), io::ErrorKind::AlreadyExists);
        drop(first);
        acquire_instance_lock(&path, effective_uid()).unwrap();
    }

    #[test]
    fn doctor_is_read_only_and_reports_daemon_health() {
        let power = Arc::new(FakePower::new(false, false));
        let manager = Manager::new(power.clone(), nominal_thermal()).unwrap();
        let doctor = manager.doctor();
        assert!(doctor.daemon_healthy);
        assert!(doctor.power_commands_available);
        assert!(doctor.problems.is_empty());
        assert_eq!(power.enable_calls.load(Ordering::SeqCst), 0);
        assert_eq!(power.restore_calls.load(Ordering::SeqCst), 0);
        assert!(!power.sentinel.load(Ordering::SeqCst));
    }

    #[test]
    fn shutdown_gate_rejects_new_acquisitions_before_cleanup() {
        let power = Arc::new(FakePower::new(false, false));
        let manager = Manager::new(power.clone(), nominal_thermal()).unwrap();
        manager.stop_accepting();
        let (sink, _client) = sink_pair();

        assert_eq!(
            manager.acquire(60_000, sink).unwrap_err(),
            "daemon is shutting down"
        );
        assert_eq!(power.enable_calls.load(Ordering::SeqCst), 0);
    }

    #[test]
    fn shutdown_gate_rolls_back_an_acquisition_already_enabling_power() {
        let power = Arc::new(FakePower::new(false, false));
        power.block_enable.store(true, Ordering::SeqCst);
        let manager = Arc::new(Manager::new(power.clone(), nominal_thermal()).unwrap());
        let (sink, _client) = sink_pair();
        let acquire_manager = Arc::clone(&manager);
        let acquire = thread::spawn(move || acquire_manager.acquire(60_000, sink));
        while !power.enable_started.load(Ordering::SeqCst) {
            thread::yield_now();
        }

        let stop_manager = Arc::clone(&manager);
        let stopper = thread::spawn(move || stop_manager.stop_accepting());
        while manager.accepting.load(Ordering::SeqCst) {
            thread::yield_now();
        }
        power.block_enable.store(false, Ordering::SeqCst);

        assert_eq!(
            acquire.join().unwrap().unwrap_err(),
            "daemon is shutting down"
        );
        stopper.join().unwrap();
        assert!(!power.disabled.load(Ordering::SeqCst));
        assert!(!power.sentinel.load(Ordering::SeqCst));
        assert!(manager.status().active_leases.is_empty());
    }

    #[test]
    fn slow_diagnostic_snapshot_does_not_block_a_critical_trip() {
        let power = Arc::new(FakePower::new(false, false));
        let thermal = nominal_thermal();
        let manager = Arc::new(Manager::new(power.clone(), thermal.clone()).unwrap());
        let (sink, _client) = sink_pair();
        manager.acquire(60_000, sink).unwrap();
        power.sleep_read_started.store(false, Ordering::SeqCst);
        power.block_sleep_read.store(true, Ordering::SeqCst);
        let doctor_manager = Arc::clone(&manager);
        let doctor = thread::spawn(move || doctor_manager.doctor());
        while !power.sleep_read_started.load(Ordering::SeqCst) {
            thread::yield_now();
        }
        *thermal.state.lock().unwrap() = Ok(ThermalState::Critical);

        manager.thermal_watchdog_tick().unwrap();
        power.block_sleep_read.store(false, Ordering::SeqCst);
        let _ = doctor.join().unwrap();

        assert!(!power.disabled.load(Ordering::SeqCst));
        assert!(!power.sentinel.load(Ordering::SeqCst));
    }

    #[test]
    fn recover_distinguishes_refusal_from_cleanup_failure() {
        let manager = Arc::new(
            Manager::new(Arc::new(FakePower::new(true, false)), nominal_thermal()).unwrap(),
        );
        let (mut client, server) = UnixStream::pair().unwrap();
        let worker = thread::spawn(move || handle_client(server, effective_uid(), manager));

        write_frame(&mut client, &Envelope::new(Request::Recover)).unwrap();
        assert!(matches!(
            read_server_message(&mut client),
            ServerMessage::Reply(Reply::Error { code, .. }) if code == "recover_refused"
        ));
        drop(client);
        worker.join().unwrap().unwrap();
    }

    #[test]
    fn status_json_exposes_the_stable_v1_health_fields() {
        let manager =
            Manager::new(Arc::new(FakePower::new(false, false)), nominal_thermal()).unwrap();
        let json = serde_json::to_value(manager.status()).unwrap();
        for field in [
            "schema_version",
            "daemon_reachable",
            "healthy",
            "health_problem",
            "thermal",
            "thermal_latched",
            "battery",
            "sleep_disabled",
            "foreign_state",
            "active_leases",
            "last_trip",
        ] {
            assert!(json.get(field).is_some(), "missing status field {field}");
        }
    }

    #[test]
    fn unix_peer_uid_comes_from_kernel_credentials() {
        let (stream, _peer) = UnixStream::pair().unwrap();
        assert_eq!(peer_uid(&stream).unwrap(), effective_uid());
    }
}
