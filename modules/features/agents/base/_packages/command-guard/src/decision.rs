use std::{collections::BTreeSet, path::Path};

use crate::{
    error::{GuardError, Result},
    option_scan,
    policy::SemanticDenyRule,
    protocol::{HookInput, bounded_reason},
    redirection,
    shell::{self, FunctionDefinition, ParsedShell, Pipeline, SimpleCommand, Word},
    shellfirm_provider::{ShellfirmMatch, ValidatedPolicy},
};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Decision {
    Safe,
    Context { additional_context: String },
    Deny { reason: String },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
enum FindingKind {
    Context,
    Deny,
}

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord)]
struct Finding {
    kind: FindingKind,
    key: String,
    reason: String,
}

enum SudoInvocation {
    None,
    Command(SimpleCommand),
    ShellSource(String),
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum ExecutionContext {
    External,
    Shell,
    ShellNoFunctions,
}

impl ExecutionContext {
    fn has_shell_builtins(self) -> bool {
        self != Self::External
    }
}

#[derive(Clone, Copy)]
struct FunctionScopes<'a> {
    immediate: &'a [FunctionDefinition],
    deferred: &'a [FunctionDefinition],
}

pub fn assess(input: &HookInput, policy: &ValidatedPolicy) -> Decision {
    match assess_source(input.command(), input.cwd(), policy, 0) {
        Ok(findings) if findings.is_empty() => Decision::Safe,
        Ok(findings) if has_deny_findings(&findings) => Decision::Deny {
            reason: render_findings(&findings, FindingKind::Deny),
        },
        Ok(findings) => Decision::Context {
            additional_context: render_findings(&findings, FindingKind::Context),
        },
        Err(error) => Decision::Deny {
            reason: bounded_reason(&format!(
                "The shared command policy could not safely analyze this command: {error}. Rewrite it as a simpler static command and try again."
            )),
        },
    }
}

fn assess_source(
    source: &str,
    cwd: &Path,
    validated: &ValidatedPolicy,
    depth: usize,
) -> Result<Vec<Finding>> {
    assess_source_with_functions(source, cwd, validated, depth, &[], &[])
}

fn assess_source_with_functions(
    source: &str,
    cwd: &Path,
    validated: &ValidatedPolicy,
    depth: usize,
    inherited_functions: &[FunctionDefinition],
    deferred_functions: &[FunctionDefinition],
) -> Result<Vec<Finding>> {
    if depth > validated.policy.unknown.max_decode_depth {
        return Err(GuardError::Policy(
            "nested command decoding exceeded maxDecodeDepth".to_owned(),
        ));
    }
    let parsed = shell::parse(source)?;
    let mut functions = inherited_functions
        .iter()
        .cloned()
        .map(|mut definition| {
            definition.source_start = 0;
            definition.inherited = true;
            definition
        })
        .collect::<Vec<_>>();
    functions.extend(parsed.functions.iter().cloned());
    let mut deferred_functions = deferred_functions
        .iter()
        .cloned()
        .map(|mut definition| {
            definition.source_start = 0;
            definition.inherited = true;
            definition
        })
        .collect::<Vec<_>>();
    deferred_functions.extend(parsed.functions.iter().cloned());
    assess_parsed(
        &parsed,
        cwd,
        validated,
        depth,
        FunctionScopes {
            immediate: &functions,
            deferred: &deferred_functions,
        },
    )
}

fn assess_parsed(
    parsed: &ParsedShell,
    cwd: &Path,
    validated: &ValidatedPolicy,
    depth: usize,
    scopes: FunctionScopes<'_>,
) -> Result<Vec<Finding>> {
    let mut findings = Vec::new();
    if let Some(variable) = parsed
        .assignment_names
        .iter()
        .find(|name| is_shell_init_variable(name))
    {
        return Err(GuardError::Policy(format!(
            "assignment to {variable} can inject shell startup code and is not allowed in guarded commands"
        )));
    }
    for pipeline in &parsed.pipelines {
        add_shellfirm_findings(
            validated.shellfirm_matches(&pipeline.projection(), cwd),
            &mut findings,
        );
        if let Some(pipeline) =
            normalize_pipeline(pipeline, validated.policy.unknown.max_decode_depth)?
        {
            add_shellfirm_findings(
                validated.shellfirm_matches(&pipeline.projection(), cwd),
                &mut findings,
            );
        }
    }
    for command in &parsed.commands {
        if let Err(error) = assess_simple(
            command,
            cwd,
            validated,
            depth,
            ExecutionContext::Shell,
            scopes,
            &mut findings,
        ) && !has_deny_findings(&findings)
        {
            return Err(error);
        }
        for projection in command.redirect_projections() {
            add_shellfirm_findings(validated.shellfirm_matches(&projection, cwd), &mut findings);
        }
    }
    for redirect in &parsed.standalone_redirects {
        add_shellfirm_findings(
            validated.shellfirm_matches(&redirect.projection(), cwd),
            &mut findings,
        );
    }
    for projection in &parsed.redirect_projections {
        add_shellfirm_findings(validated.shellfirm_matches(projection, cwd), &mut findings);
    }
    if !validated.policy.shell.redirection.empty_file {
        match redirection::empty_file_findings(
            parsed,
            cwd,
            validated.policy.unknown.max_decode_depth,
        ) {
            Ok(matches) => findings.extend(matches.into_iter().map(|matched| Finding {
                kind: FindingKind::Deny,
                key: matched.key,
                reason: matched.reason,
            })),
            Err(error) if !has_deny_findings(&findings) => return Err(error),
            Err(_) => {}
        }
    }
    findings.sort();
    findings.dedup_by(|left, right| left.key == right.key);
    Ok(findings)
}

fn assess_simple(
    command: &SimpleCommand,
    cwd: &Path,
    validated: &ValidatedPolicy,
    depth: usize,
    context: ExecutionContext,
    scopes: FunctionScopes<'_>,
    findings: &mut Vec<Finding>,
) -> Result<()> {
    if depth > validated.policy.unknown.max_decode_depth {
        return Err(GuardError::Policy(
            "nested command decoding exceeded maxDecodeDepth".to_owned(),
        ));
    }
    let Some(first) = command.words.first() else {
        return Ok(());
    };
    let Some(executable) = first.static_value() else {
        return Err(GuardError::Policy(
            "the executable name is dynamic".to_owned(),
        ));
    };
    let basename = executable_basename(executable);

    let scoped_functions = scopes
        .immediate
        .iter()
        .filter(|definition| definition.inherited || definition.source_start < command.source.start)
        .cloned()
        .collect::<Vec<_>>();
    if context == ExecutionContext::Shell
        && let Some(function) = scoped_functions
            .iter()
            .enumerate()
            .filter(|(_, definition)| definition.name == basename)
            .max_by_key(|(index, definition)| {
                (!definition.inherited, definition.source_start, *index)
            })
            .map(|(_, definition)| definition)
    {
        findings.extend(assess_source_with_functions(
            &function.body,
            cwd,
            validated,
            depth + 1,
            &scoped_functions,
            scopes.deferred,
        )?);
        return Ok(());
    }
    let nested_functions = scoped_functions
        .iter()
        .cloned()
        .map(|mut definition| {
            definition.source_start = 0;
            definition.inherited = true;
            definition
        })
        .collect::<Vec<_>>();
    let nested_scopes = FunctionScopes {
        immediate: &nested_functions,
        deferred: scopes.deferred,
    };

    match basename {
        "command" if context.has_shell_builtins() => {
            if let Some(inner) = unwrap_command_builtin(&command.words[1..])? {
                assess_simple(
                    &inner,
                    cwd,
                    validated,
                    depth + 1,
                    ExecutionContext::ShellNoFunctions,
                    nested_scopes,
                    findings,
                )?;
            }
            return Ok(());
        }
        "exec" if context.has_shell_builtins() => {
            if let Some(inner) = unwrap_exec(&command.words[1..])? {
                assess_simple(
                    &inner,
                    cwd,
                    validated,
                    depth + 1,
                    ExecutionContext::External,
                    nested_scopes,
                    findings,
                )?;
            }
            return Ok(());
        }
        "builtin" if context.has_shell_builtins() => {
            if let Some(inner) = unwrap_builtin(&command.words[1..])? {
                assess_simple(
                    &inner,
                    cwd,
                    validated,
                    depth + 1,
                    ExecutionContext::ShellNoFunctions,
                    nested_scopes,
                    findings,
                )?;
            }
            return Ok(());
        }
        "env" => {
            if let Some(inner) = unwrap_env(&command.words[1..])? {
                assess_simple(
                    &inner,
                    cwd,
                    validated,
                    depth + 1,
                    ExecutionContext::External,
                    nested_scopes,
                    findings,
                )?;
            }
            return Ok(());
        }
        "sudo" => {
            match unwrap_sudo(&command.words[1..])? {
                SudoInvocation::None => {}
                SudoInvocation::Command(inner) => {
                    assess_simple(
                        &inner,
                        cwd,
                        validated,
                        depth + 1,
                        ExecutionContext::External,
                        nested_scopes,
                        findings,
                    )?;
                }
                SudoInvocation::ShellSource(source) => {
                    findings.extend(assess_source(&source, cwd, validated, depth + 1)?);
                }
            }
            return Ok(());
        }
        "bash" | "sh" | "dash" | "zsh" => {
            if let Some(source) = shell_source(&command.words[1..])? {
                findings.extend(assess_source(&source, cwd, validated, depth + 1)?);
            }
            return Ok(());
        }
        "nix-shell" => {
            if let Some(source) = nix_shell_source(&command.words[1..])? {
                findings.extend(assess_source(&source, cwd, validated, depth + 1)?);
            }
            return Ok(());
        }
        "eval" if context.has_shell_builtins() => {
            let source = eval_source(&command.words[1..])?;
            if !source.is_empty() {
                if !shell::parse(&source)?.functions.is_empty() {
                    return Err(GuardError::Policy(
                        "function definitions inside eval change later shell state and are not decoded; use a literal function definition"
                            .to_owned(),
                    ));
                }
                findings.extend(assess_source_with_functions(
                    &source,
                    cwd,
                    validated,
                    depth + 1,
                    &scoped_functions,
                    scopes.deferred,
                )?);
            }
            return Ok(());
        }
        "trap" if context.has_shell_builtins() => {
            if let Some(action) = trap_action(&command.words[1..])? {
                findings.extend(assess_source_with_functions(
                    &action,
                    cwd,
                    validated,
                    depth + 1,
                    scopes.deferred,
                    scopes.deferred,
                )?);
            }
            return Ok(());
        }
        "export" | "readonly" | "declare" | "typeset" | "local" if context.has_shell_builtins() => {
            validate_shell_state_builtin(basename, &command.words[1..])?;
            return Ok(());
        }
        "set" if context.has_shell_builtins() => {
            validate_set_builtin(&command.words[1..])?;
            return Ok(());
        }
        "shopt" if context.has_shell_builtins() => {
            validate_shopt_builtin(&command.words[1..])?;
            return Ok(());
        }
        "." | "source" if context.has_shell_builtins() && command.words.len() > 1 => {
            return Err(GuardError::Policy(
                "sourced shell files and process substitutions are not decoded; use an inspected literal -c command"
                    .to_owned(),
            ));
        }
        "alias" if context.has_shell_builtins() && command.words.len() > 1 => {
            return Err(GuardError::Policy(
                "shell aliases cannot be safely resolved; use a literal command".to_owned(),
            ));
        }
        "nix" => {
            if let Some(resolved) = unwrap_nix(&command.words[1..])? {
                assess_simple(
                    &resolved,
                    cwd,
                    validated,
                    depth + 1,
                    ExecutionContext::External,
                    nested_scopes,
                    findings,
                )?;
            }
        }
        "timeout" => {
            if let Some(inner) = unwrap_timeout(&command.words[1..])? {
                assess_simple(
                    &inner,
                    cwd,
                    validated,
                    depth + 1,
                    ExecutionContext::External,
                    nested_scopes,
                    findings,
                )?;
            }
            return Ok(());
        }
        "nice" => {
            if let Some(inner) = unwrap_nice(&command.words[1..])? {
                assess_simple(
                    &inner,
                    cwd,
                    validated,
                    depth + 1,
                    ExecutionContext::External,
                    nested_scopes,
                    findings,
                )?;
            }
            return Ok(());
        }
        "nohup" => {
            if let Some(inner) = unwrap_nohup(&command.words[1..])? {
                assess_simple(
                    &inner,
                    cwd,
                    validated,
                    depth + 1,
                    ExecutionContext::External,
                    nested_scopes,
                    findings,
                )?;
            }
            return Ok(());
        }
        "xargs" => {
            if let Some(inner) = unwrap_xargs(&command.words[1..])? {
                assess_simple(
                    &inner,
                    cwd,
                    validated,
                    depth + 1,
                    ExecutionContext::External,
                    nested_scopes,
                    findings,
                )?;
            }
            return Ok(());
        }
        "find" => {
            for inner in find_exec_commands(&command.words[1..])? {
                assess_simple(
                    &inner,
                    cwd,
                    validated,
                    depth + 1,
                    ExecutionContext::External,
                    nested_scopes,
                    findings,
                )?;
            }
        }
        _ => {}
    }

    let normalized = normalized_words(command)?;
    add_exact_findings(&normalized, validated, findings);
    add_semantic_findings(command, &normalized, validated, findings)?;
    add_shellfirm_findings(
        validated.shellfirm_matches(&command.projection(), cwd),
        findings,
    );
    Ok(())
}

fn normalize_pipeline(pipeline: &Pipeline, max_depth: usize) -> Result<Option<Pipeline>> {
    let commands = pipeline
        .commands
        .iter()
        .map(|command| normalize_pipeline_command(command, 0, max_depth, ExecutionContext::Shell))
        .collect::<Result<Option<Vec<_>>>>()?;
    Ok(commands.map(|commands| Pipeline {
        commands,
        operators: pipeline.operators.clone(),
    }))
}

fn normalize_pipeline_command(
    command: &SimpleCommand,
    depth: usize,
    max_depth: usize,
    context: ExecutionContext,
) -> Result<Option<SimpleCommand>> {
    if depth > max_depth {
        return Err(GuardError::Policy(
            "pipeline launcher decoding exceeded maxDecodeDepth".to_owned(),
        ));
    }
    let Some(first) = command.words.first() else {
        return Ok(None);
    };
    let executable = static_word(first, "pipeline executable")?;
    match executable_basename(executable) {
        "command" if context.has_shell_builtins() => unwrap_command_builtin(&command.words[1..])?
            .map(|inner| {
                normalize_pipeline_command(
                    &inner,
                    depth + 1,
                    max_depth,
                    ExecutionContext::ShellNoFunctions,
                )
            })
            .transpose()
            .map(Option::flatten),
        "exec" if context.has_shell_builtins() => unwrap_exec(&command.words[1..])?
            .map(|inner| {
                normalize_pipeline_command(&inner, depth + 1, max_depth, ExecutionContext::External)
            })
            .transpose()
            .map(Option::flatten),
        "builtin" if context.has_shell_builtins() => unwrap_builtin(&command.words[1..])?
            .map(|inner| {
                normalize_pipeline_command(
                    &inner,
                    depth + 1,
                    max_depth,
                    ExecutionContext::ShellNoFunctions,
                )
            })
            .transpose()
            .map(Option::flatten),
        "env" => unwrap_env(&command.words[1..])?
            .map(|inner| {
                normalize_pipeline_command(&inner, depth + 1, max_depth, ExecutionContext::External)
            })
            .transpose()
            .map(Option::flatten),
        "sudo" => match unwrap_sudo(&command.words[1..])? {
            SudoInvocation::None => Ok(None),
            SudoInvocation::Command(inner) => {
                normalize_pipeline_command(&inner, depth + 1, max_depth, ExecutionContext::External)
            }
            SudoInvocation::ShellSource(_) => Ok(Some(command.clone())),
        },
        "nix" => unwrap_nix(&command.words[1..])?
            .map(|inner| {
                normalize_pipeline_command(&inner, depth + 1, max_depth, ExecutionContext::External)
            })
            .transpose()
            .map(Option::flatten),
        _ => Ok(Some(command.clone())),
    }
}

fn eval_source(words: &[Word]) -> Result<String> {
    let words = match words.first().and_then(Word::static_value) {
        Some("--") => &words[1..],
        Some(value) if value.starts_with('-') => {
            return Err(GuardError::Policy(format!(
                "unsupported eval option {value}"
            )));
        }
        _ => words,
    };
    words
        .iter()
        .map(|word| static_word(word, "eval source"))
        .collect::<Result<Vec<_>>>()
        .map(|parts| parts.join(" "))
}

fn normalized_words(command: &SimpleCommand) -> Result<Vec<Option<String>>> {
    command
        .words
        .iter()
        .enumerate()
        .map(|(index, word)| match word.static_value() {
            Some(value) if index == 0 => Ok(Some(executable_basename(value).to_owned())),
            Some(value) => Ok(Some(value.to_owned())),
            None if index == 0 => Err(GuardError::Policy(
                "the executable name is dynamic".to_owned(),
            )),
            None => Ok(None),
        })
        .collect()
}

fn add_exact_findings(
    words: &[Option<String>],
    validated: &ValidatedPolicy,
    findings: &mut Vec<Finding>,
) {
    let matched = validated
        .policy
        .exact
        .iter()
        .filter(|rule| prefix_matches(words, &rule.argv_prefix))
        .max_by_key(|rule| rule.argv_prefix.len());
    if let Some(rule) = matched {
        findings.push(Finding {
            kind: FindingKind::Deny,
            key: format!("exact:{}", rule.argv_prefix.join("\u{0}")),
            reason: rule.reason.clone(),
        });
    }
}

fn add_semantic_findings(
    command: &SimpleCommand,
    words: &[Option<String>],
    validated: &ValidatedPolicy,
    findings: &mut Vec<Finding>,
) -> Result<()> {
    let matched = validated
        .policy
        .semantic
        .iter()
        .filter(|rule| prefix_matches(words, &rule.command_prefix))
        .max_by_key(|rule| rule.command_prefix.len());
    let Some(rule) = matched else {
        return Ok(());
    };
    let deny_options = rule
        .deny
        .iter()
        .flat_map(|deny| deny.option_groups.iter().flatten())
        .cloned()
        .collect::<BTreeSet<_>>();
    let scan = option_scan::scan(
        &command.words[rule.command_prefix.len()..],
        &rule.option_syntax,
        &deny_options,
    )?;
    let mut denied = false;
    for (index, deny) in rule.deny.iter().enumerate() {
        if deny
            .option_groups
            .iter()
            .all(|group| group.iter().any(|option| scan.present.contains(option)))
        {
            denied = true;
            findings.push(Finding {
                kind: FindingKind::Deny,
                key: format!("semantic:{}:{index}", rule.command_prefix.join("\u{0}")),
                reason: semantic_reason(deny),
            });
        }
    }
    if !denied && scan.dynamic_relevant {
        return Err(GuardError::Policy(format!(
            "an option for {} is dynamic; insert -- before dynamic positional arguments",
            rule.command_prefix.join(" ")
        )));
    }
    if !denied && let Some(guidance) = &rule.guidance {
        findings.push(Finding {
            kind: FindingKind::Context,
            key: format!("context:{}", rule.command_prefix.join("\u{0}")),
            reason: guidance.clone(),
        });
    }
    Ok(())
}

fn semantic_reason(deny: &SemanticDenyRule) -> String {
    format!(
        "{} Alternative: {}",
        deny.reason,
        deny.alternatives.join(" ")
    )
}

fn prefix_matches(words: &[Option<String>], prefix: &[String]) -> bool {
    words.len() >= prefix.len()
        && words
            .iter()
            .zip(prefix)
            .all(|(actual, expected)| actual.as_deref() == Some(expected.as_str()))
}

fn add_shellfirm_findings(matches: Vec<ShellfirmMatch>, findings: &mut Vec<Finding>) {
    for matched in matches {
        let alternative = matched
            .alternative
            .filter(|value| !value.trim().is_empty())
            .map(|value| format!(" Alternative: {value}"))
            .unwrap_or_default();
        findings.push(Finding {
            kind: FindingKind::Deny,
            key: format!("shellfirm:{}", matched.id),
            reason: format!(
                "Shellfirm {} ({:?}): {}{}",
                matched.id, matched.severity, matched.description, alternative
            ),
        });
    }
}

fn has_deny_findings(findings: &[Finding]) -> bool {
    findings
        .iter()
        .any(|finding| finding.kind == FindingKind::Deny)
}

fn render_findings(findings: &[Finding], kind: FindingKind) -> String {
    bounded_reason(
        &findings
            .iter()
            .filter(|finding| finding.kind == kind)
            .map(|finding| finding.reason.as_str())
            .collect::<Vec<_>>()
            .join(" "),
    )
}

fn executable_basename(executable: &str) -> &str {
    executable.rsplit('/').next().unwrap_or(executable)
}

fn synthetic_from(words: &[Word]) -> Option<SimpleCommand> {
    (!words.is_empty()).then(|| SimpleCommand {
        words: words.to_vec(),
        redirects: Vec::new(),
        source: 0..0,
    })
}

fn unwrap_command_builtin(words: &[Word]) -> Result<Option<SimpleCommand>> {
    let mut index = 0;
    while let Some(word) = words.get(index) {
        let value = static_word(word, "command option")?;
        match value {
            "--" | "-p" => index += 1,
            "-v" | "-V" => return Ok(None),
            value if value.starts_with('-') => {
                return Err(GuardError::Policy(format!(
                    "unsupported command builtin option {value}"
                )));
            }
            _ => break,
        }
    }
    Ok(synthetic_from(&words[index..]))
}

fn unwrap_exec(words: &[Word]) -> Result<Option<SimpleCommand>> {
    let mut index = 0;
    while let Some(word) = words.get(index) {
        let value = static_word(word, "exec option or executable")?;
        if value == "--" {
            index += 1;
            break;
        }
        if matches!(value, "-c" | "-l") {
            index += 1;
            continue;
        }
        if value == "-a" {
            require_static_value(words, index + 1, "exec argv zero value")?;
            index += 2;
            continue;
        }
        if value.starts_with('-') {
            return Err(GuardError::Policy(format!(
                "unsupported exec option {value}"
            )));
        }
        break;
    }
    Ok(synthetic_from(&words[index..]))
}

fn unwrap_builtin(words: &[Word]) -> Result<Option<SimpleCommand>> {
    let words = match words.first().and_then(Word::static_value) {
        Some("--") => &words[1..],
        Some(value) if value.starts_with('-') => {
            return Err(GuardError::Policy(format!(
                "unsupported builtin option {value}"
            )));
        }
        _ => words,
    };
    let Some(name) = words
        .first()
        .map(|word| static_word(word, "builtin name"))
        .transpose()?
    else {
        return Ok(None);
    };
    if !matches!(
        name,
        "." | "alias"
            | "builtin"
            | "command"
            | "declare"
            | "eval"
            | "exec"
            | "export"
            | "local"
            | "readonly"
            | "set"
            | "shopt"
            | "source"
            | "trap"
            | "typeset"
    ) {
        return Ok(None);
    }
    Ok(synthetic_from(words))
}

fn trap_action(words: &[Word]) -> Result<Option<String>> {
    let mut index = 0;
    if let Some(word) = words.first() {
        let value = static_word(word, "trap option or action")?;
        if value == "--" {
            index += 1;
        } else if matches!(value, "-l" | "-p" | "--help") {
            return Ok(None);
        } else if value.starts_with('-') && value != "-" {
            return Err(GuardError::Policy(format!(
                "unsupported trap option {value}"
            )));
        }
    }
    if words.len().saturating_sub(index) < 2 {
        return Ok(None);
    }
    let action = static_word(&words[index], "trap action")?;
    if matches!(action, "" | "-") {
        return Ok(None);
    }
    Ok(Some(action.to_owned()))
}

fn validate_shell_state_builtin(executable: &str, words: &[Word]) -> Result<()> {
    let mut function_mode = false;
    let mut export_mode = executable == "export";
    for word in words {
        let value = static_word(word, "shell state builtin argument")?;
        if value == "--" {
            continue;
        }
        if let Some(options) = value.strip_prefix('-').filter(|value| !value.is_empty()) {
            function_mode |= options.chars().any(|option| matches!(option, 'f' | 'F'));
            export_mode |= options.contains('x');
            continue;
        }
        if is_shell_init_variable(assignment_name(value).unwrap_or(value)) {
            return Err(GuardError::Policy(format!(
                "{executable} of a shell startup variable is not allowed in guarded commands"
            )));
        }
    }
    if function_mode && export_mode {
        return Err(GuardError::Policy(
            "exported shell functions can inject code into child shells and are not decoded"
                .to_owned(),
        ));
    }
    Ok(())
}

fn validate_set_builtin(words: &[Word]) -> Result<()> {
    let mut expects_option_name = false;
    for word in words {
        let value = static_word(word, "set argument")?;
        if expects_option_name {
            if value == "allexport" {
                return Err(allexport_error());
            }
            expects_option_name = false;
            continue;
        }
        if value == "--" {
            break;
        }
        let Some(options) = value
            .strip_prefix('-')
            .filter(|options| !options.is_empty())
        else {
            continue;
        };
        if options.contains('a') {
            return Err(allexport_error());
        }
        expects_option_name = options.ends_with('o');
    }
    Ok(())
}

fn validate_shopt_builtin(words: &[Word]) -> Result<()> {
    let mut enables = false;
    let mut set_option_mode = false;
    let mut names = Vec::new();
    let mut parsing_options = true;
    for word in words {
        let value = static_word(word, "shopt argument")?;
        if parsing_options && value == "--" {
            parsing_options = false;
            continue;
        }
        if parsing_options {
            if let Some(options) = value
                .strip_prefix('-')
                .filter(|options| !options.is_empty())
            {
                enables |= options.contains('s');
                set_option_mode |= options.contains('o');
                continue;
            }
            parsing_options = false;
        }
        names.push(value);
    }
    if enables && set_option_mode && names.contains(&"allexport") {
        return Err(allexport_error());
    }
    Ok(())
}

fn allexport_error() -> GuardError {
    GuardError::Policy(
        "allexport can export a shell startup variable mutated by another builtin and is not allowed in guarded commands"
            .to_owned(),
    )
}

fn unwrap_env(words: &[Word]) -> Result<Option<SimpleCommand>> {
    let value_options = BTreeSet::from(["-u", "--unset", "-C", "--chdir"]);
    let flag_options = BTreeSet::from(["-i", "--ignore-environment", "-0", "--null", "--debug"]);
    let mut index = 0;
    while let Some(word) = words.get(index) {
        let value = static_word(word, "env option or executable")?;
        if value == "--" {
            index += 1;
            break;
        }
        if value == "-S" || value == "--split-string" || value.starts_with("--split-string=") {
            return Err(GuardError::Policy(
                "env --split-string is not decoded by the command guard".to_owned(),
            ));
        }
        if flag_options.contains(value)
            || value.starts_with("--unset=")
            || value.starts_with("--chdir=")
        {
            index += 1;
            continue;
        }
        if value_options.contains(value) {
            require_static_value(words, index + 1, "env option value")?;
            index += 2;
            continue;
        }
        if is_env_assignment(value) {
            reject_shell_init_assignment(value, "env")?;
            index += 1;
            continue;
        }
        if value.starts_with('-') {
            return Err(GuardError::Policy(format!(
                "unsupported env option {value}"
            )));
        }
        break;
    }
    Ok(synthetic_from(&words[index..]))
}

fn unwrap_sudo(words: &[Word]) -> Result<SudoInvocation> {
    let long_value_options = BTreeSet::from([
        "--user",
        "--group",
        "--host",
        "--prompt",
        "--close-from",
        "--command-timeout",
        "--chroot",
        "--chdir",
        "--role",
        "--type",
    ]);
    let terminal_action_options = BTreeSet::from([
        "-V",
        "--version",
        "--help",
        "-l",
        "--list",
        "-v",
        "--validate",
        "-K",
        "--remove-timestamp",
    ]);
    let command_modifier_options = BTreeSet::from(["-k", "--reset-timestamp"]);
    let long_flags = BTreeSet::from([
        "--non-interactive",
        "--preserve-env",
        "--set-home",
        "--stdin",
        "--background",
        "--preserve-groups",
        "--login",
        "--shell",
    ]);
    let mut index = 0;
    let mut shell_mode = false;
    while let Some(word) = words.get(index) {
        let value = static_word(word, "sudo option or executable")?;
        if value == "--" {
            index += 1;
            break;
        }
        if terminal_action_options.contains(value) {
            return Ok(SudoInvocation::None);
        }
        if command_modifier_options.contains(value) {
            index += 1;
            continue;
        }
        if long_value_options.contains(value) {
            require_static_value(words, index + 1, "sudo option value")?;
            index += 2;
            continue;
        }
        if value == "--preserve-env" || value.starts_with("--preserve-env=") {
            index += 1;
            continue;
        }
        if let Some((name, _)) = value.split_once('=')
            && long_value_options.contains(name)
        {
            index += 1;
            continue;
        }
        if long_flags.contains(value) {
            shell_mode |= matches!(value, "--login" | "--shell");
            index += 1;
            continue;
        }
        if is_assignment(value) {
            reject_shell_init_assignment(value, "sudo")?;
            index += 1;
            continue;
        }
        if value.starts_with("--") {
            return Err(GuardError::Policy(format!(
                "unsupported sudo option {value}"
            )));
        }
        if value.starts_with('-') {
            let effects = sudo_short_option_effects(value)?;
            if effects.no_execution {
                return Ok(SudoInvocation::None);
            }
            shell_mode |= effects.shell_mode;
            if effects.consumes_next {
                require_static_value(words, index + 1, "sudo option value")?;
                index += 2;
            } else {
                index += 1;
            }
            continue;
        }
        break;
    }
    let remaining = &words[index..];
    if shell_mode {
        if remaining.is_empty() {
            return Err(GuardError::Policy(
                "interactive sudo shells are not decoded; provide a literal command".to_owned(),
            ));
        }
        return sudo_shell_source(remaining).map(SudoInvocation::ShellSource);
    }
    Ok(synthetic_from(remaining)
        .map(SudoInvocation::Command)
        .unwrap_or(SudoInvocation::None))
}

fn sudo_shell_source(words: &[Word]) -> Result<String> {
    words
        .iter()
        .map(|word| static_word(word, "sudo shell command").map(quote_sudo_shell_word))
        .collect::<Result<Vec<_>>>()
        .map(|parts| parts.join(" "))
}

fn quote_sudo_shell_word(word: &str) -> String {
    word.chars()
        .flat_map(|character| {
            if character.is_ascii_alphanumeric() || matches!(character, '_' | '-' | '$') {
                [None, Some(character)]
            } else {
                [Some('\\'), Some(character)]
            }
        })
        .flatten()
        .collect()
}

struct SudoShortEffects {
    consumes_next: bool,
    no_execution: bool,
    shell_mode: bool,
}

fn sudo_short_option_effects(value: &str) -> Result<SudoShortEffects> {
    let options = value
        .strip_prefix('-')
        .filter(|value| !value.is_empty())
        .ok_or_else(|| GuardError::Policy("invalid sudo short option".to_owned()))?;
    let mut characters = options.char_indices().peekable();
    let mut no_execution = false;
    let mut shell_mode = false;
    while let Some((_, option)) = characters.next() {
        if matches!(option, 'K' | 'V' | 'l' | 'v') {
            no_execution = true;
            continue;
        }
        if matches!(option, 'n' | 'E' | 'H' | 'S' | 'b' | 'P' | 'k') {
            continue;
        }
        if matches!(option, 'i' | 's') {
            shell_mode = true;
            continue;
        }
        if matches!(
            option,
            'u' | 'g' | 'h' | 'p' | 'C' | 'T' | 'R' | 'D' | 'r' | 't'
        ) {
            return Ok(SudoShortEffects {
                consumes_next: characters.peek().is_none(),
                no_execution,
                shell_mode,
            });
        }
        return Err(GuardError::Policy(format!(
            "unsupported sudo short option -{option}"
        )));
    }
    Ok(SudoShortEffects {
        consumes_next: false,
        no_execution,
        shell_mode,
    })
}

fn shell_source(words: &[Word]) -> Result<Option<String>> {
    let mut index = 0;
    while let Some(word) = words.get(index) {
        let value = static_word(word, "shell option")?;
        if value == "--" {
            if words.get(index + 1).is_some() {
                return Err(GuardError::Policy(
                    "shell script files are not decoded; use a literal -c command".to_owned(),
                ));
            }
            break;
        }
        if matches!(value, "--help" | "--version") {
            return Ok(None);
        }
        if matches!(value, "--rcfile" | "--init-file")
            || value.starts_with("--rcfile=")
            || value.starts_with("--init-file=")
        {
            return Err(GuardError::Policy(
                "shell startup files are not decoded; use a literal -c command without --rcfile or --init-file"
                    .to_owned(),
            ));
        }
        if matches!(value, "-O" | "+O") {
            require_static_value(words, index + 1, "shell option value")?;
            index += 2;
            continue;
        }
        if (value.starts_with("-O") || value.starts_with("+O")) && value.len() > 2 {
            index += 1;
            continue;
        }
        if matches!(value, "-o" | "+o") {
            let option = require_static_value(words, index + 1, "shell option value")?;
            if value == "-o" && option == "allexport" {
                return Err(allexport_error());
            }
            index += 2;
            continue;
        }
        if (value.starts_with("-o") || value.starts_with("+o")) && value.len() > 2 {
            index += 1;
            continue;
        }
        if let Some(options) = value
            .strip_prefix('-')
            .filter(|value| !value.starts_with('-'))
        {
            if options.contains('a') {
                return Err(allexport_error());
            }
            if options.contains('c') {
                return require_static_value(words, index + 1, "shell -c source")
                    .map(str::to_owned)
                    .map(Some);
            }
            index += 1;
            continue;
        }
        if value.starts_with('+') {
            index += 1;
            continue;
        }
        if !value.starts_with('-') {
            return Err(GuardError::Policy(
                "shell script files are not decoded; use a literal -c command".to_owned(),
            ));
        }
        index += 1;
    }
    Err(GuardError::Policy(
        "shell source from standard input or a here-document is not decoded; use a literal -c command"
            .to_owned(),
    ))
}

fn nix_shell_source(words: &[Word]) -> Result<Option<String>> {
    let two_value_options = BTreeSet::from(["--arg", "--arg-from-file", "--argstr", "--option"]);
    let one_value_options = BTreeSet::from([
        "-A",
        "-I",
        "-j",
        "--arg-from-stdin",
        "--attr",
        "--builders",
        "--cores",
        "--eval-store",
        "--exclude",
        "--include",
        "--keep",
        "--log-format",
        "--max-jobs",
        "--store",
        "--system",
        "--timeout",
    ]);
    let mut index = 0;
    while let Some(word) = words.get(index) {
        let value = static_word(word, "nix-shell argument")?;
        if matches!(value, "--run" | "--command") {
            return require_static_value(words, index + 1, "nix-shell command")
                .map(str::to_owned)
                .map(Some);
        }
        if let Some(source) = value
            .strip_prefix("--run=")
            .or_else(|| value.strip_prefix("--command="))
        {
            return Ok(Some(source.to_owned()));
        }
        if two_value_options.contains(value) {
            require_static_value(words, index + 1, "nix-shell option name")?;
            require_static_value(words, index + 2, "nix-shell option value")?;
            index += 3;
            continue;
        }
        if one_value_options.contains(value) {
            require_static_value(words, index + 1, "nix-shell option value")?;
            index += 2;
            continue;
        }
        index += 1;
    }
    Ok(None)
}

fn unwrap_nohup(words: &[Word]) -> Result<Option<SimpleCommand>> {
    let mut index = 0;
    if let Some(word) = words.first() {
        let value = static_word(word, "nohup option or executable")?;
        match value {
            "--" => {
                index += 1;
            }
            "--help" | "--version" => return Ok(None),
            value if value.starts_with('-') => {
                return Err(GuardError::Policy(format!(
                    "unsupported nohup option {value}"
                )));
            }
            _ => {}
        }
    }
    Ok(synthetic_from(&words[index..]))
}

fn unwrap_nice(words: &[Word]) -> Result<Option<SimpleCommand>> {
    let mut index = 0;
    while let Some(word) = words.get(index) {
        let value = static_word(word, "nice option or executable")?;
        if value == "--" {
            index += 1;
            break;
        }
        if matches!(value, "--help" | "--version") {
            return Ok(None);
        }
        if value == "-n" || value == "--adjustment" {
            require_static_value(words, index + 1, "nice adjustment")?;
            index += 2;
            continue;
        }
        if value.starts_with("--adjustment=") || is_obsolete_nice_adjustment(value) {
            index += 1;
            continue;
        }
        if value.starts_with('-') {
            return Err(GuardError::Policy(format!(
                "unsupported nice option {value}"
            )));
        }
        break;
    }
    Ok(synthetic_from(&words[index..]))
}

fn is_obsolete_nice_adjustment(value: &str) -> bool {
    value.strip_prefix('-').is_some_and(|digits| {
        !digits.is_empty() && digits.chars().all(|value| value.is_ascii_digit())
    })
}

fn unwrap_timeout(words: &[Word]) -> Result<Option<SimpleCommand>> {
    let mut index = 0;
    while let Some(word) = words.get(index) {
        let value = static_word(word, "timeout option or duration")?;
        if value == "--" {
            index += 1;
            break;
        }
        if matches!(value, "--help" | "--version") {
            return Ok(None);
        }
        if matches!(
            value,
            "--foreground" | "--preserve-status" | "--verbose" | "-v"
        ) {
            index += 1;
            continue;
        }
        if matches!(value, "-k" | "--kill-after" | "-s" | "--signal") {
            require_static_value(words, index + 1, "timeout option value")?;
            index += 2;
            continue;
        }
        if value.starts_with("--kill-after=")
            || value.starts_with("--signal=")
            || value.starts_with("-k") && value.len() > 2
            || value.starts_with("-s") && value.len() > 2
        {
            index += 1;
            continue;
        }
        if value.starts_with('-') {
            return Err(GuardError::Policy(format!(
                "unsupported timeout option {value}"
            )));
        }
        break;
    }
    if words.get(index).is_none() {
        return Ok(None);
    }
    require_static_value(words, index, "timeout duration")?;
    Ok(synthetic_from(&words[index + 1..]))
}

fn unwrap_xargs(words: &[Word]) -> Result<Option<SimpleCommand>> {
    let long_value_options = BTreeSet::from([
        "--arg-file",
        "--delimiter",
        "--max-args",
        "--max-chars",
        "--max-procs",
        "--process-slot-var",
    ]);
    let long_optional_value_options = BTreeSet::from(["--eof", "--max-lines", "--replace"]);
    let long_flags = BTreeSet::from([
        "--exit",
        "--interactive",
        "--no-run-if-empty",
        "--null",
        "--open-tty",
        "--show-limits",
        "--verbose",
    ]);
    let mut index = 0;
    let mut replacement = None;
    while let Some(word) = words.get(index) {
        let value = static_word(word, "xargs option or executable")?;
        if value == "--" {
            index += 1;
            break;
        }
        if matches!(value, "--help" | "--version") {
            return Ok(None);
        }
        if value == "--replace" || value == "-i" {
            replacement = Some("{}".to_owned());
            index += 1;
            continue;
        }
        if value == "-I" {
            replacement = Some(
                require_static_value(words, index + 1, "xargs replacement string")?.to_owned(),
            );
            index += 2;
            continue;
        }
        if let Some(value) = value.strip_prefix("--replace=") {
            replacement = Some(value.to_owned());
            index += 1;
            continue;
        }
        if let Some(value) = value.strip_prefix("-I").filter(|value| !value.is_empty()) {
            replacement = Some(value.to_owned());
            index += 1;
            continue;
        }
        if let Some(value) = value.strip_prefix("-i").filter(|value| !value.is_empty()) {
            replacement = Some(value.to_owned());
            index += 1;
            continue;
        }
        if value.starts_with('-')
            && !value.starts_with("--")
            && value[1..].chars().any(|option| matches!(option, 'I' | 'i'))
        {
            return Err(GuardError::Policy(
                "combined xargs replacement options are not decoded; spell -I separately"
                    .to_owned(),
            ));
        }
        if long_flags.contains(value) || long_optional_value_options.contains(value) {
            index += 1;
            continue;
        }
        if long_value_options.contains(value) {
            require_static_value(words, index + 1, "xargs option value")?;
            index += 2;
            continue;
        }
        if let Some((name, _)) = value.split_once('=')
            && (long_value_options.contains(name) || long_optional_value_options.contains(name))
        {
            index += 1;
            continue;
        }
        if value.starts_with("--") {
            return Err(GuardError::Policy(format!(
                "unsupported xargs option {value}"
            )));
        }
        if value.starts_with('-') {
            if xargs_short_option_consumes_next(value)? {
                require_static_value(words, index + 1, "xargs option value")?;
                index += 2;
            } else {
                index += 1;
            }
            continue;
        }
        break;
    }
    let Some(mut command) = synthetic_from(&words[index..]) else {
        return Ok(None);
    };
    if let Some(replacement) = replacement {
        command.words = command
            .words
            .into_iter()
            .map(|word| match word.static_value() {
                Some(value) if value.contains(&replacement) => Word::dynamic(),
                _ => word,
            })
            .collect();
    } else {
        command.words.push(Word::dynamic());
    }
    Ok(Some(command))
}

fn xargs_short_option_consumes_next(value: &str) -> Result<bool> {
    let options = value
        .strip_prefix('-')
        .filter(|value| !value.is_empty())
        .ok_or_else(|| GuardError::Policy("invalid xargs short option".to_owned()))?;
    let mut characters = options.char_indices().peekable();
    while let Some((_, option)) = characters.next() {
        if matches!(option, '0' | 'p' | 'r' | 't' | 'x') {
            continue;
        }
        if matches!(option, 'e' | 'i' | 'l') {
            return Ok(false);
        }
        if matches!(option, 'a' | 'd' | 'E' | 'I' | 'L' | 'n' | 'P' | 's') {
            return Ok(characters.peek().is_none());
        }
        return Err(GuardError::Policy(format!(
            "unsupported xargs short option -{option}"
        )));
    }
    Ok(false)
}

fn find_exec_commands(words: &[Word]) -> Result<Vec<SimpleCommand>> {
    let mut commands = Vec::new();
    let mut index = 0;
    while index < words.len() {
        let value = static_word(&words[index], "find expression")?;
        if !matches!(value, "-exec" | "-execdir" | "-ok" | "-okdir") {
            index += 1;
            continue;
        }
        let marker = value.to_owned();
        index += 1;
        let start = index;
        while index < words.len() {
            let value = static_word(&words[index], "find execution argument")?;
            if matches!(value, ";" | "+") {
                break;
            }
            index += 1;
        }
        if index == words.len() {
            return Err(GuardError::Policy(format!(
                "find {marker} action has no terminating ; or +"
            )));
        }
        if start == index {
            return Err(GuardError::Policy(format!(
                "find {marker} action has no command"
            )));
        }
        let command_words = words[start..index]
            .iter()
            .map(|word| match word.static_value() {
                Some(value) if value.contains("{}") => Word::dynamic(),
                _ => word.clone(),
            })
            .collect::<Vec<_>>();
        commands.push(synthetic_from(&command_words).expect("find command is non-empty"));
        index += 1;
    }
    Ok(commands)
}

fn unwrap_nix(words: &[Word]) -> Result<Option<SimpleCommand>> {
    let Some(subcommand_index) = nix_subcommand_index(words)? else {
        return Ok(None);
    };
    let subcommand = static_word(&words[subcommand_index], "nix subcommand")?;
    let arguments = &words[subcommand_index + 1..];
    match subcommand {
        "shell" | "develop" => {
            let mut command_index = None;
            for (index, word) in arguments.iter().enumerate() {
                let value = static_word(word, "nix shell argument before --command")?;
                if matches!(value, "-c" | "--command") {
                    command_index = Some(index);
                    break;
                }
            }
            Ok(command_index.and_then(|index| synthetic_from(&arguments[index + 1..])))
        }
        "run" => unwrap_nix_run(arguments),
        _ => Ok(None),
    }
}

fn nix_subcommand_index(words: &[Word]) -> Result<Option<usize>> {
    let value_options = BTreeSet::from([
        "--extra-experimental-features",
        "--experimental-features",
        "--log-format",
    ]);
    let flag_options = BTreeSet::from([
        "--accept-flake-config",
        "--debug",
        "--offline",
        "--print-build-logs",
        "--quiet",
        "--refresh",
        "--verbose",
        "-L",
        "-v",
    ]);
    let terminal_options = BTreeSet::from(["--help", "--version"]);
    let mut index = 0;
    while let Some(word) = words.get(index) {
        let value = static_word(word, "nix global option or subcommand")?;
        if terminal_options.contains(value) {
            return Ok(None);
        }
        if flag_options.contains(value) {
            index += 1;
            continue;
        }
        if value_options.contains(value) {
            require_static_value(words, index + 1, "nix global option value")?;
            index += 2;
            continue;
        }
        if value == "--option" {
            require_static_value(words, index + 1, "nix configuration option name")?;
            require_static_value(words, index + 2, "nix configuration option value")?;
            index += 3;
            continue;
        }
        if let Some((name, _)) = value.split_once('=')
            && value_options.contains(name)
        {
            index += 1;
            continue;
        }
        if value.starts_with('-') {
            return Err(GuardError::Policy(format!(
                "unsupported nix global option {value} before the subcommand"
            )));
        }
        return Ok(Some(index));
    }
    Ok(None)
}

fn unwrap_nix_run(words: &[Word]) -> Result<Option<SimpleCommand>> {
    let mut installable = None;
    let mut argument_index = None;
    for (index, word) in words.iter().enumerate() {
        let value = static_word(word, "nix run argument")?;
        if value == "--" {
            argument_index = Some(index + 1);
            break;
        }
        if installable.is_none() && !value.starts_with('-') {
            installable = Some(value);
        }
    }
    let Some(installable) = installable else {
        return Ok(None);
    };
    let executable = installable
        .rsplit_once('#')
        .map(|(_, fragment)| fragment.rsplit('.').next().unwrap_or(fragment))
        .filter(|value| !value.is_empty());
    let Some(executable) = executable else {
        return Err(GuardError::Policy(
            "nix run installable has no static package fragment".to_owned(),
        ));
    };
    let mut resolved = vec![Word::synthetic(executable)];
    if let Some(index) = argument_index {
        resolved.extend_from_slice(&words[index..]);
    }
    Ok(synthetic_from(&resolved))
}

fn static_word<'a>(word: &'a Word, context: &str) -> Result<&'a str> {
    word.static_value().ok_or_else(|| {
        GuardError::Policy(format!("{context} is dynamic and cannot be safely decoded"))
    })
}

fn require_static_value<'a>(words: &'a [Word], index: usize, context: &str) -> Result<&'a str> {
    let word = words
        .get(index)
        .ok_or_else(|| GuardError::Policy(format!("{context} is missing")))?;
    static_word(word, context)
}

fn is_assignment(value: &str) -> bool {
    let Some(name) = assignment_name(value) else {
        return false;
    };
    !name.is_empty()
        && name.chars().enumerate().all(|(index, character)| {
            character == '_'
                || character.is_ascii_alphanumeric() && (index > 0 || !character.is_ascii_digit())
        })
}

fn is_env_assignment(value: &str) -> bool {
    assignment_name(value).is_some_and(|name| !name.is_empty())
}

fn assignment_name(value: &str) -> Option<&str> {
    value.split_once('=').map(|(name, _)| name)
}

fn is_shell_init_variable(name: &str) -> bool {
    matches!(name, "BASH_ENV" | "ENV" | "SHELLOPTS" | "ZDOTDIR")
}

fn is_exported_bash_function(name: &str) -> bool {
    name.starts_with("BASH_FUNC_") && name.ends_with("%%")
}

fn reject_shell_init_assignment(value: &str, launcher: &str) -> Result<()> {
    if assignment_name(value)
        .is_some_and(|name| is_shell_init_variable(name) || is_exported_bash_function(name))
    {
        return Err(GuardError::Policy(format!(
            "{launcher} assignment to a shell startup variable can inject code and is not decoded"
        )));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn recognizes_assignments_but_not_option_values() {
        assert!(is_assignment("A_B=1"));
        assert!(!is_assignment("1A=1"));
        assert!(!is_assignment("--foo=bar"));
        assert_eq!(
            eval_source(&[Word::synthetic("--"), Word::synthetic("echo safe")]).unwrap(),
            "echo safe"
        );
    }
}
