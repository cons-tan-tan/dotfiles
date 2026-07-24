use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

pub const THERMAL_POLL_INTERVAL_MS: u64 = 2_000;
pub const SERIOUS_TRIP_AFTER_MS: u64 = 15_000;
pub const NOMINAL_RESET_AFTER_MS: u64 = 60_000;
pub const HEARTBEAT_EVERY_MS: u64 = 5_000;
pub const HEARTBEAT_TIMEOUT_MS: u64 = 15_000;
pub const MAX_LID_LEASE_MS: u64 = 4 * 60 * 60 * 1_000;
pub const MAX_ACTIVE_LID_LEASES: usize = 32;
pub const LOW_BATTERY_PERCENT: u8 = 20;

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ThermalState {
    Nominal,
    Fair,
    Serious,
    Critical,
    Unknown,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum BatterySource {
    Ac,
    Battery,
    Unknown,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct BatteryState {
    pub source: BatterySource,
    pub percent: Option<u8>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum TripReason {
    ThermalCritical,
    ThermalSerious,
    ThermalUnavailable,
    LowBattery { percent: u8 },
    BatteryUnavailable,
    PowerRestoreFailed,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Lease {
    pub id: String,
    pub deadline_ms: u64,
    pub heartbeat_deadline_ms: u64,
}

#[derive(Clone, Debug, Default)]
pub struct SafetyPolicy {
    serious_since_ms: Option<u64>,
    nominal_since_ms: Option<u64>,
    latched: bool,
    pub last_trip: Option<TripReason>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum ThermalDecision {
    Permit,
    Warn(ThermalState),
    Refuse(TripReason),
    Trip(TripReason),
}

impl SafetyPolicy {
    #[must_use]
    pub fn is_latched(&self) -> bool {
        self.latched
    }

    #[must_use]
    pub fn observe_thermal(
        &mut self,
        now_ms: u64,
        state: Result<ThermalState, ()>,
        has_active_lease: bool,
    ) -> ThermalDecision {
        let state = match state {
            Ok(state) => state,
            Err(()) => {
                self.reset_cooldown();
                return if has_active_lease {
                    self.trip(TripReason::ThermalUnavailable)
                } else {
                    ThermalDecision::Refuse(TripReason::ThermalUnavailable)
                };
            }
        };

        match state {
            ThermalState::Nominal => {
                self.serious_since_ms = None;
                if self.latched {
                    let since = self.nominal_since_ms.get_or_insert(now_ms);
                    if now_ms.saturating_sub(*since) >= NOMINAL_RESET_AFTER_MS {
                        self.latched = false;
                        self.nominal_since_ms = None;
                    }
                }
                if self.latched {
                    ThermalDecision::Refuse(
                        self.last_trip
                            .clone()
                            .unwrap_or(TripReason::ThermalUnavailable),
                    )
                } else {
                    ThermalDecision::Permit
                }
            }
            ThermalState::Fair => {
                self.reset_cooldown();
                self.serious_since_ms = None;
                if self.latched {
                    ThermalDecision::Refuse(
                        self.last_trip
                            .clone()
                            .unwrap_or(TripReason::ThermalUnavailable),
                    )
                } else {
                    ThermalDecision::Warn(ThermalState::Fair)
                }
            }
            ThermalState::Serious => {
                self.reset_cooldown();
                if !has_active_lease {
                    self.serious_since_ms = None;
                    return ThermalDecision::Refuse(TripReason::ThermalSerious);
                }
                let since = self.serious_since_ms.get_or_insert(now_ms);
                if now_ms.saturating_sub(*since) >= SERIOUS_TRIP_AFTER_MS {
                    self.trip(TripReason::ThermalSerious)
                } else {
                    ThermalDecision::Warn(ThermalState::Serious)
                }
            }
            ThermalState::Critical => {
                self.reset_cooldown();
                self.serious_since_ms = None;
                if has_active_lease {
                    self.trip(TripReason::ThermalCritical)
                } else {
                    ThermalDecision::Refuse(TripReason::ThermalCritical)
                }
            }
            ThermalState::Unknown => {
                self.reset_cooldown();
                if has_active_lease {
                    self.trip(TripReason::ThermalUnavailable)
                } else {
                    ThermalDecision::Refuse(TripReason::ThermalUnavailable)
                }
            }
        }
    }

    #[must_use]
    pub fn observe_battery(
        &mut self,
        battery: Result<BatteryState, ()>,
        has_active_lease: bool,
    ) -> Option<TripReason> {
        match battery {
            Ok(BatteryState {
                source: BatterySource::Ac,
                ..
            }) => None,
            Ok(BatteryState {
                source: BatterySource::Battery,
                percent: Some(percent),
            }) if percent <= LOW_BATTERY_PERCENT => {
                let reason = TripReason::LowBattery { percent };
                if has_active_lease {
                    self.last_trip = Some(reason.clone());
                }
                Some(reason)
            }
            Ok(BatteryState {
                source: BatterySource::Battery,
                percent: None,
            })
            | Ok(BatteryState {
                source: BatterySource::Unknown,
                ..
            })
            | Err(()) => {
                let reason = TripReason::BatteryUnavailable;
                if has_active_lease {
                    self.last_trip = Some(reason.clone());
                }
                Some(reason)
            }
            Ok(_) => None,
        }
    }

    fn reset_cooldown(&mut self) {
        self.nominal_since_ms = None;
    }

    fn trip(&mut self, reason: TripReason) -> ThermalDecision {
        self.latch(reason.clone());
        ThermalDecision::Trip(reason)
    }

    fn latch(&mut self, reason: TripReason) {
        self.latched = true;
        self.last_trip = Some(reason);
        self.nominal_since_ms = None;
    }
}

#[derive(Default)]
pub struct LeaseBook {
    leases: BTreeMap<String, Lease>,
}

impl LeaseBook {
    pub fn acquire(&mut self, lease: Lease) -> Result<bool, &'static str> {
        if lease.deadline_ms == 0 || lease.heartbeat_deadline_ms == 0 {
            return Err("invalid lease duration");
        }
        if self.leases.contains_key(&lease.id) {
            return Err("duplicate lease id");
        }
        let was_empty = self.leases.is_empty();
        self.leases.insert(lease.id.clone(), lease);
        Ok(was_empty)
    }

    pub fn heartbeat(&mut self, id: &str, heartbeat_deadline_ms: u64) -> bool {
        let Some(lease) = self.leases.get_mut(id) else {
            return false;
        };
        lease.heartbeat_deadline_ms = heartbeat_deadline_ms;
        true
    }

    pub fn release(&mut self, id: &str) -> bool {
        self.leases.remove(id).is_some() && self.leases.is_empty()
    }

    pub fn expire(&mut self, now_ms: u64) -> Vec<String> {
        let expired = self
            .leases
            .iter()
            .filter(|(_, lease)| {
                now_ms >= lease.deadline_ms || now_ms >= lease.heartbeat_deadline_ms
            })
            .map(|(id, _)| id.clone())
            .collect::<Vec<_>>();
        for id in &expired {
            self.leases.remove(id);
        }
        expired
    }

    pub fn revoke_all(&mut self) -> Vec<String> {
        let ids = self.leases.keys().cloned().collect();
        self.leases.clear();
        ids
    }

    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.leases.is_empty()
    }

    #[must_use]
    pub fn len(&self) -> usize {
        self.leases.len()
    }

    pub fn values(&self) -> impl Iterator<Item = &Lease> {
        self.leases.values()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn serious_trips_only_at_threshold() {
        let mut policy = SafetyPolicy::default();
        assert_eq!(
            policy.observe_thermal(1_000, Ok(ThermalState::Serious), true),
            ThermalDecision::Warn(ThermalState::Serious)
        );
        assert_eq!(
            policy.observe_thermal(15_999, Ok(ThermalState::Serious), true),
            ThermalDecision::Warn(ThermalState::Serious)
        );
        assert_eq!(
            policy.observe_thermal(16_000, Ok(ThermalState::Serious), true),
            ThermalDecision::Trip(TripReason::ThermalSerious)
        );
    }

    #[test]
    fn critical_and_read_failure_trip_immediately() {
        let mut critical = SafetyPolicy::default();
        assert_eq!(
            critical.observe_thermal(0, Ok(ThermalState::Critical), true),
            ThermalDecision::Trip(TripReason::ThermalCritical)
        );
        let mut unavailable = SafetyPolicy::default();
        assert_eq!(
            unavailable.observe_thermal(0, Err(()), true),
            ThermalDecision::Trip(TripReason::ThermalUnavailable)
        );
    }

    #[test]
    fn latch_requires_sixty_nominal_seconds() {
        let mut policy = SafetyPolicy::default();
        let _ = policy.observe_thermal(0, Ok(ThermalState::Critical), true);
        assert!(policy.is_latched());
        assert!(matches!(
            policy.observe_thermal(10, Ok(ThermalState::Nominal), false),
            ThermalDecision::Refuse(_)
        ));
        assert!(matches!(
            policy.observe_thermal(60_009, Ok(ThermalState::Nominal), false),
            ThermalDecision::Refuse(_)
        ));
        assert_eq!(
            policy.observe_thermal(60_010, Ok(ThermalState::Nominal), false),
            ThermalDecision::Permit
        );
        assert!(!policy.is_latched());
    }

    #[test]
    fn fair_resets_nominal_cooldown() {
        let mut policy = SafetyPolicy::default();
        let _ = policy.observe_thermal(0, Ok(ThermalState::Critical), true);
        let _ = policy.observe_thermal(1_000, Ok(ThermalState::Nominal), false);
        let _ = policy.observe_thermal(30_000, Ok(ThermalState::Fair), false);
        assert!(matches!(
            policy.observe_thermal(31_000, Ok(ThermalState::Nominal), false),
            ThermalDecision::Refuse(_)
        ));
        assert!(matches!(
            policy.observe_thermal(90_999, Ok(ThermalState::Nominal), false),
            ThermalDecision::Refuse(_)
        ));
        assert_eq!(
            policy.observe_thermal(91_000, Ok(ThermalState::Nominal), false),
            ThermalDecision::Permit
        );
    }

    #[test]
    fn low_discharging_battery_is_a_trip() {
        let mut policy = SafetyPolicy::default();
        assert_eq!(
            policy.observe_battery(
                Ok(BatteryState {
                    source: BatterySource::Battery,
                    percent: Some(20),
                }),
                true,
            ),
            Some(TripReason::LowBattery { percent: 20 })
        );
        assert!(!policy.is_latched());
    }

    #[test]
    fn ac_power_ignores_missing_percentage() {
        let mut policy = SafetyPolicy::default();
        assert_eq!(
            policy.observe_battery(
                Ok(BatteryState {
                    source: BatterySource::Ac,
                    percent: None,
                }),
                true,
            ),
            None
        );
    }

    #[test]
    fn overlapping_leases_restore_only_after_last_release() {
        let mut book = LeaseBook::default();
        assert_eq!(
            book.acquire(Lease {
                id: "a".into(),
                deadline_ms: 10,
                heartbeat_deadline_ms: 5,
            }),
            Ok(true)
        );
        assert_eq!(
            book.acquire(Lease {
                id: "b".into(),
                deadline_ms: 10,
                heartbeat_deadline_ms: 5,
            }),
            Ok(false)
        );
        assert!(!book.release("a"));
        assert!(book.release("b"));
    }

    #[test]
    fn deadline_and_heartbeat_expire_independently() {
        let mut book = LeaseBook::default();
        book.acquire(Lease {
            id: "deadline".into(),
            deadline_ms: 5,
            heartbeat_deadline_ms: 10,
        })
        .unwrap();
        book.acquire(Lease {
            id: "heartbeat".into(),
            deadline_ms: 10,
            heartbeat_deadline_ms: 4,
        })
        .unwrap();
        assert_eq!(book.expire(4), vec![String::from("heartbeat")]);
        assert_eq!(book.expire(5), vec![String::from("deadline")]);
        assert!(book.is_empty());
    }
}
