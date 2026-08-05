use crate::model::ThermalState;
use objc2_foundation::{NSProcessInfo, NSProcessInfoThermalState};
use std::io;

pub trait ThermalSource: Send + Sync {
    fn thermal_state(&self) -> io::Result<ThermalState>;
}

#[derive(Default)]
pub struct FoundationThermalSource;

impl ThermalSource for FoundationThermalSource {
    fn thermal_state(&self) -> io::Result<ThermalState> {
        let state = NSProcessInfo::processInfo().thermalState();
        let mapped = if state == NSProcessInfoThermalState::Nominal {
            ThermalState::Nominal
        } else if state == NSProcessInfoThermalState::Fair {
            ThermalState::Fair
        } else if state == NSProcessInfoThermalState::Serious {
            ThermalState::Serious
        } else if state == NSProcessInfoThermalState::Critical {
            ThermalState::Critical
        } else {
            ThermalState::Unknown
        };
        Ok(mapped)
    }
}
