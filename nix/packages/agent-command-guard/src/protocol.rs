use std::{
    io::Read,
    path::{Path, PathBuf},
};

use serde::{Deserialize, Serialize};

use crate::error::{GuardError, Result};

pub const MAX_INPUT_BYTES: u64 = 1024 * 1024;
pub const MAX_COMMAND_BYTES: usize = 256 * 1024;
const MAX_REASON_CHARS: usize = 1200;

#[derive(Debug, Deserialize)]
pub struct HookInput {
    pub cwd: PathBuf,
    pub hook_event_name: String,
    pub tool_name: String,
    pub tool_input: ToolInput,
}

#[derive(Debug, Deserialize)]
pub struct ToolInput {
    pub command: String,
}

impl HookInput {
    pub fn read(reader: impl Read) -> Result<Self> {
        let mut bytes = Vec::new();
        reader
            .take(MAX_INPUT_BYTES + 1)
            .read_to_end(&mut bytes)
            .map_err(GuardError::ReadInput)?;
        if bytes.len() as u64 > MAX_INPUT_BYTES {
            return Err(GuardError::HookInput(format!(
                "hook input exceeds {MAX_INPUT_BYTES} bytes"
            )));
        }
        let input: Self = serde_json::from_slice(&bytes)?;
        input.validate()?;
        Ok(input)
    }

    pub fn command(&self) -> &str {
        &self.tool_input.command
    }

    pub fn cwd(&self) -> &Path {
        &self.cwd
    }

    fn validate(&self) -> Result<()> {
        if self.hook_event_name != "PreToolUse" {
            return Err(GuardError::HookInput(
                "hook_event_name must be PreToolUse".to_owned(),
            ));
        }
        if self.tool_name != "Bash" {
            return Err(GuardError::HookInput("tool_name must be Bash".to_owned()));
        }
        if self.tool_input.command.is_empty() {
            return Err(GuardError::HookInput(
                "tool_input.command must not be empty".to_owned(),
            ));
        }
        if self.tool_input.command.len() > MAX_COMMAND_BYTES {
            return Err(GuardError::HookInput(format!(
                "tool_input.command exceeds {MAX_COMMAND_BYTES} bytes"
            )));
        }
        Ok(())
    }
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct DenyOutput<'a> {
    hook_specific_output: HookSpecificOutput<'a>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct HookSpecificOutput<'a> {
    hook_event_name: &'static str,
    permission_decision: &'static str,
    permission_decision_reason: &'a str,
}

pub fn safe_output() -> &'static str {
    "{}"
}

pub fn deny_output(reason: &str) -> String {
    let reason = bounded_reason(reason);
    serde_json::to_string(&DenyOutput {
        hook_specific_output: HookSpecificOutput {
            hook_event_name: "PreToolUse",
            permission_decision: "deny",
            permission_decision_reason: &reason,
        },
    })
    .expect("serializing a fixed hook response cannot fail")
}

pub fn bounded_reason(reason: &str) -> String {
    let trimmed = reason.trim();
    let source = if trimmed.is_empty() {
        "The shared command policy denied this command without a detailed reason."
    } else {
        trimmed
    };
    let mut chars = source.chars();
    let mut output = chars.by_ref().take(MAX_REASON_CHARS).collect::<String>();
    if chars.next().is_some() {
        output.push_str("...");
    }
    output
}

#[cfg(test)]
mod tests {
    use serde_json::Value;

    use super::*;

    #[test]
    fn safe_output_is_an_empty_object() {
        assert_eq!(safe_output(), "{}");
    }

    #[test]
    fn deny_output_uses_the_supported_pre_tool_use_shape() {
        let output: Value = serde_json::from_str(&deny_output("blocked")).unwrap();
        assert_eq!(output["hookSpecificOutput"]["permissionDecision"], "deny");
        assert_eq!(
            output["hookSpecificOutput"]["permissionDecisionReason"],
            "blocked"
        );
        assert_eq!(output["hookSpecificOutput"]["hookEventName"], "PreToolUse");
    }
}
