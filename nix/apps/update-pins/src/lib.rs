#![cfg_attr(all(feature = "smoke", not(feature = "mutating")), allow(dead_code))]

#[cfg(feature = "mutating")]
pub mod build;
#[cfg(feature = "mutating")]
pub mod cli;
#[cfg(feature = "mutating")]
pub mod codex_app;
#[cfg(not(feature = "mutating"))]
mod codex_app;
#[cfg(feature = "mutating")]
pub mod command;
#[cfg(not(feature = "mutating"))]
mod command;
#[cfg(feature = "mutating")]
pub mod engine;
#[cfg(feature = "mutating")]
pub mod error;
#[cfg(not(feature = "mutating"))]
mod error;
#[cfg(feature = "mutating")]
pub mod fetch;
#[cfg(not(feature = "mutating"))]
mod fetch;
#[cfg(feature = "mutating")]
pub mod ledger;
#[cfg(feature = "mutating")]
pub mod pins;
#[cfg(feature = "mutating")]
pub mod policy;
#[cfg(not(feature = "mutating"))]
mod policy;
#[cfg(feature = "mutating")]
pub mod prefetch;
#[cfg(not(feature = "mutating"))]
mod prefetch;
#[cfg(feature = "mutating")]
pub mod registry;
#[cfg(feature = "mutating")]
pub mod shellfirm;
#[cfg(not(feature = "mutating"))]
mod shellfirm;
#[cfg(feature = "smoke")]
pub mod smoke;
#[cfg(feature = "mutating")]
pub mod targets;
#[cfg(feature = "mutating")]
pub mod transaction;
#[cfg(feature = "mutating")]
pub mod upstream;
#[cfg(not(feature = "mutating"))]
mod upstream;
#[cfg(feature = "mutating")]
pub mod validation;
#[cfg(feature = "mutating")]
pub mod value_validation;
#[cfg(not(feature = "mutating"))]
mod value_validation;
