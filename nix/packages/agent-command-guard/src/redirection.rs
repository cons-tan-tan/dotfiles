use std::{fs, io::ErrorKind, path::Path};

use crate::{
    error::{GuardError, Result},
    shell::{ParsedShell, Redirect, SimpleCommand},
};

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct RedirectionFinding {
    pub key: String,
    pub reason: String,
}

pub(crate) fn empty_file_findings(
    parsed: &ParsedShell,
    cwd: &Path,
    max_decode_depth: usize,
) -> Result<Vec<RedirectionFinding>> {
    let mut findings = Vec::new();
    for command in &parsed.commands {
        if explicitly_empties_file(command, 0, max_decode_depth)? {
            inspect_redirects(command.redirects(), cwd, &mut findings)?;
        }
    }
    inspect_redirects(&parsed.standalone_redirects, cwd, &mut findings)?;
    Ok(findings)
}

fn explicitly_empties_file(
    command: &SimpleCommand,
    depth: usize,
    max_decode_depth: usize,
) -> Result<bool> {
    if depth > max_decode_depth {
        return Err(GuardError::Policy(
            "empty-file launcher decoding exceeded maxDecodeDepth".to_owned(),
        ));
    }
    let Some(executable) = command.words.first().and_then(|word| word.static_value()) else {
        return Ok(false);
    };
    let basename = executable.rsplit('/').next().unwrap_or(executable);
    match basename {
        // The shell builtins intentionally produce no output regardless of arguments.
        ":" => Ok(true),
        "true" | "false" => Ok(true),
        "command" => command_builtin_empties_file(&command.words[1..], depth + 1, max_decode_depth),
        "builtin" => builtin_empties_file(&command.words[1..], depth + 1, max_decode_depth),
        "env" => env_empties_file(&command.words[1..], depth + 1, max_decode_depth),
        "exec" => exec_empties_file(&command.words[1..], depth + 1, max_decode_depth),
        "echo" => echo_empties_file(&command.words[1..]),
        "printf" => printf_empties_file(&command.words[1..]),
        "cat" => {
            Ok(command.words.len() == 2 && command.words[1].static_value() == Some("/dev/null"))
        }
        _ => Ok(false),
    }
}

fn command_builtin_empties_file(
    words: &[crate::shell::Word],
    depth: usize,
    max_decode_depth: usize,
) -> Result<bool> {
    let mut index = 0;
    while let Some(value) = words.get(index).and_then(|word| word.static_value()) {
        match value {
            "--" | "-p" => index += 1,
            "-v" | "-V" => return Ok(false),
            value if value.starts_with('-') => return Ok(false),
            _ => break,
        }
    }
    explicitly_empties_words(&words[index..], depth, max_decode_depth)
}

fn builtin_empties_file(
    words: &[crate::shell::Word],
    depth: usize,
    max_decode_depth: usize,
) -> Result<bool> {
    let words = match words.first().and_then(|word| word.static_value()) {
        Some("--") => &words[1..],
        Some(value) if value.starts_with('-') => return Ok(false),
        _ => words,
    };
    explicitly_empties_words(words, depth, max_decode_depth)
}

fn exec_empties_file(
    words: &[crate::shell::Word],
    depth: usize,
    max_decode_depth: usize,
) -> Result<bool> {
    let mut index = 0;
    while let Some(value) = words.get(index).and_then(|word| word.static_value()) {
        if value == "--" {
            index += 1;
            break;
        }
        if matches!(value, "-c" | "-l") {
            index += 1;
            continue;
        }
        if value == "-a" {
            index += 2;
            continue;
        }
        if value.starts_with('-') {
            return Ok(false);
        }
        break;
    }
    if index >= words.len() {
        Ok(true)
    } else {
        explicitly_empties_words(&words[index..], depth, max_decode_depth)
    }
}

fn env_empties_file(
    words: &[crate::shell::Word],
    depth: usize,
    max_decode_depth: usize,
) -> Result<bool> {
    let mut index = 0;
    while let Some(value) = words.get(index).and_then(|word| word.static_value()) {
        if value == "--" {
            index += 1;
            break;
        }
        if matches!(value, "-u" | "--unset" | "-C" | "--chdir") {
            index += 2;
            continue;
        }
        if matches!(
            value,
            "-i" | "--ignore-environment" | "-0" | "--null" | "--debug"
        ) || value.starts_with("--unset=")
            || value.starts_with("--chdir=")
            || value.split_once('=').is_some_and(|(name, _)| {
                !name.is_empty()
                    && name.chars().enumerate().all(|(position, character)| {
                        character == '_'
                            || character.is_ascii_alphanumeric()
                                && (position > 0 || !character.is_ascii_digit())
                    })
            })
        {
            index += 1;
            continue;
        }
        if value.starts_with('-') {
            return Ok(false);
        }
        break;
    }
    explicitly_empties_words(&words[index..], depth, max_decode_depth)
}

fn explicitly_empties_words(
    words: &[crate::shell::Word],
    depth: usize,
    max_decode_depth: usize,
) -> Result<bool> {
    let Some(command) = (!words.is_empty()).then(|| SimpleCommand {
        words: words.to_vec(),
        redirects: Vec::new(),
        source: 0..0,
    }) else {
        return Ok(false);
    };
    explicitly_empties_file(&command, depth, max_decode_depth)
}

fn echo_empties_file(words: &[crate::shell::Word]) -> Result<bool> {
    Ok(!words.is_empty()
        && words.iter().all(|word| {
            word.static_value().is_some_and(|value| {
                value.starts_with('-')
                    && value.len() > 1
                    && value[1..]
                        .chars()
                        .all(|option| matches!(option, 'n' | 'e' | 'E'))
            })
        })
        && words.iter().any(|word| {
            word.static_value()
                .is_some_and(|value| value[1..].contains('n'))
        }))
}

fn printf_empties_file(words: &[crate::shell::Word]) -> Result<bool> {
    let words = match words.first().and_then(|word| word.static_value()) {
        Some("--") => &words[1..],
        _ => words,
    };
    Ok(words.len() == 1 && words[0].static_value() == Some(""))
}

fn inspect_redirects(
    redirects: &[Redirect],
    cwd: &Path,
    findings: &mut Vec<RedirectionFinding>,
) -> Result<()> {
    for redirect in redirects {
        let static_destination = redirect
            .destination()
            .and_then(|destination| destination.static_value());
        if !is_truncating_output(redirect.operator(), static_destination) {
            continue;
        }
        let destination = redirect.destination().ok_or_else(|| {
            GuardError::Policy(
                "an explicit empty-file redirection has no static destination".to_owned(),
            )
        })?;
        let destination = destination.static_value().ok_or_else(|| {
            GuardError::Policy(
                "an explicit empty-file redirection has a dynamic destination".to_owned(),
            )
        })?;
        if destination.starts_with('~')
            || destination
                .chars()
                .any(|character| matches!(character, '*' | '?' | '['))
        {
            return Err(GuardError::Policy(
                "an explicit empty-file redirection has a dynamic destination".to_owned(),
            ));
        }
        let path = Path::new(destination);
        let resolved = if path.is_absolute() {
            path.to_path_buf()
        } else {
            cwd.join(path)
        };
        match fs::metadata(&resolved) {
            Ok(metadata) if metadata.is_file() => findings.push(RedirectionFinding {
                key: format!("shell:redirection:empty-file:{}", resolved.display()),
                reason: "Emptying an existing file through output redirection is disabled for coding agents. Use a reviewed editor when intentional."
                    .to_owned(),
            }),
            Ok(_) => {}
            Err(error) if error.kind() == ErrorKind::NotFound => {}
            Err(error) => {
                return Err(GuardError::Policy(format!(
                    "could not inspect redirection destination {}: {error}",
                    resolved.display()
                )));
            }
        }
    }
    Ok(())
}

fn is_truncating_output(operator: &str, destination: Option<&str>) -> bool {
    let operator = operator.trim();
    if operator.contains(">>") || operator.contains('<') {
        return false;
    }
    if operator == ">&" {
        return destination.is_none_or(|value| {
            value != "-" && !value.chars().all(|character| character.is_ascii_digit())
        });
    }
    if operator.ends_with(">&") {
        return false;
    }
    let prefix = operator
        .strip_suffix(">|")
        .or_else(|| operator.strip_suffix('>'));
    prefix.is_some_and(|prefix| {
        prefix.is_empty()
            || prefix == "&"
            || prefix.chars().all(|character| character.is_ascii_digit())
            || (prefix.starts_with('{')
                && prefix.ends_with('}')
                && prefix.len() > 2
                && prefix[1..prefix.len() - 1]
                    .chars()
                    .all(|character| character.is_ascii_alphanumeric() || character == '_'))
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn recognizes_truncating_but_not_append_duplication_or_input_operators() {
        for operator in [">", "2>", ">|", "2>|", "&>", "{fd}>"] {
            assert!(is_truncating_output(operator, Some("file")), "{operator}");
        }
        for operator in [">>", "2>>", "2>&1", "<", "<<", "<<<"] {
            assert!(!is_truncating_output(operator, Some("file")), "{operator}");
        }
        assert!(is_truncating_output(">&", Some("file")));
        assert!(!is_truncating_output(">&", Some("1")));
        assert!(!is_truncating_output(">&", Some("-")));
    }
}
