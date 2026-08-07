use std::collections::BTreeSet;
use std::ffi::OsString;
use std::fs;
use std::io::{self, Write};
use std::path::{Path, PathBuf};

use crate::cli::{self, Options, ParseResult};
use crate::model::{Candidate, Summary};
use crate::mutation;
use crate::workspace::{self, Workspace};

pub fn run(
    arguments: impl IntoIterator<Item = OsString>,
    stdout: &mut impl Write,
    stderr: &mut impl Write,
) -> u8 {
    match execute(arguments, stdout, stderr) {
        Ok(code) => code,
        Err(error) => {
            let _ = writeln!(stderr, "nix-mutation-test: {error}");
            2
        }
    }
}

fn execute(
    arguments: impl IntoIterator<Item = OsString>,
    stdout: &mut impl Write,
    stderr: &mut impl Write,
) -> Result<u8, String> {
    let options = match cli::parse(arguments)? {
        ParseResult::Help => {
            write!(stdout, "{}", cli::USAGE).map_err(io_error)?;
            return Ok(0);
        }
        ParseResult::Options(options) => options,
    };
    let root = canonical_root(&options.root)?;
    let targets = resolve_targets(&root, &options.targets)?;
    let mut candidates = collect_candidates(&targets, &options)?;
    if let Some(maximum) = options.max_mutants {
        candidates.truncate(maximum);
    }

    if options.list_only {
        for candidate in candidates {
            serde_json::to_writer(&mut *stdout, &candidate)
                .map_err(|error| format!("could not serialize candidate: {error}"))?;
            writeln!(stdout).map_err(io_error)?;
        }
        return Ok(0);
    }

    run_mutants(&root, &options, &candidates, stdout, stderr)
}

fn canonical_root(root: &Path) -> Result<PathBuf, String> {
    let canonical = root
        .canonicalize()
        .map_err(|_| format!("root does not exist: {}", root.display()))?;
    if !canonical.is_dir() {
        return Err(format!("root is not a directory: {}", root.display()));
    }
    Ok(canonical)
}

fn resolve_targets(root: &Path, requested: &[PathBuf]) -> Result<Vec<(String, PathBuf)>, String> {
    let mut targets = Vec::new();
    let mut seen = BTreeSet::new();
    for target in requested {
        let unresolved = if target.is_absolute() {
            target.clone()
        } else {
            root.join(target)
        };
        let absolute = unresolved
            .canonicalize()
            .map_err(|_| format!("target does not exist: {}", target.display()))?;
        if !absolute.is_file() {
            return Err(format!(
                "target is not a regular file: {}",
                target.display()
            ));
        }
        let relative = absolute
            .strip_prefix(root)
            .map_err(|_| format!("target is outside root: {}", target.display()))?;
        if relative
            .extension()
            .and_then(|extension| extension.to_str())
            != Some("nix")
        {
            return Err(format!("target is not a Nix file: {}", target.display()));
        }
        let relative = relative
            .to_str()
            .ok_or_else(|| format!("target path is not valid UTF-8: {}", target.display()))?
            .to_owned();
        if !seen.insert(relative.clone()) {
            continue;
        }
        // rnix owns lossless traversal, while the Nix parser remains the
        // acceptance oracle for the language evaluated by the test command.
        if !workspace::parses_with_nix(&absolute)? {
            return Err(format!(
                "target does not parse as Nix: {}",
                target.display()
            ));
        }
        targets.push((relative, absolute));
    }
    Ok(targets)
}

fn collect_candidates(
    targets: &[(String, PathBuf)],
    options: &Options,
) -> Result<Vec<Candidate>, String> {
    let mut candidates = Vec::new();
    for (relative, absolute) in targets {
        let source = fs::read_to_string(absolute)
            .map_err(|error| format!("could not read {}: {error}", absolute.display()))?;
        candidates.extend(mutation::discover(
            relative,
            &source,
            &options.selected_operators,
        )?);
    }
    candidates.sort_by(|left, right| {
        (
            &left.file,
            left.replacement_offsets.start,
            left.replacement_offsets.end,
            &left.mutation,
        )
            .cmp(&(
                &right.file,
                right.replacement_offsets.start,
                right.replacement_offsets.end,
                &right.mutation,
            ))
    });
    let mut ids = BTreeSet::new();
    for candidate in &candidates {
        if !ids.insert(&candidate.id) {
            return Err(format!("duplicate mutant ID: {}", candidate.id));
        }
    }
    Ok(candidates)
}

fn run_mutants(
    root: &Path,
    options: &Options,
    candidates: &[Candidate],
    stdout: &mut impl Write,
    stderr: &mut impl Write,
) -> Result<u8, String> {
    let test_command = options
        .test_command
        .as_deref()
        .expect("validated by CLI parser");
    let workspace = Workspace::create(root)?;
    workspace.reset()?;
    let baseline = workspace.run_test(
        test_command,
        options.timeout_seconds,
        "baseline",
        "baseline",
        "",
    )?;
    if baseline.timed_out {
        stderr.write_all(&baseline.stdout).map_err(io_error)?;
        stderr.write_all(&baseline.stderr).map_err(io_error)?;
        return Err(format!(
            "baseline test timed out after {} seconds",
            options.timeout_seconds
        ));
    }
    if !baseline.status.success() {
        stderr.write_all(&baseline.stdout).map_err(io_error)?;
        stderr.write_all(&baseline.stderr).map_err(io_error)?;
        return Err(format!(
            "baseline test failed with status {}",
            baseline.status.code().unwrap_or(1)
        ));
    }
    writeln!(stdout, "BASELINE pass").map_err(io_error)?;

    let mut summary = Summary::default();
    for (index, candidate) in candidates.iter().enumerate() {
        workspace.reset()?;
        let mutated_path = workspace.apply(candidate)?;
        let result = if !workspace::parses_with_nix(&mutated_path)? {
            summary.invalid += 1;
            "invalid"
        } else {
            let output = workspace.run_test(
                test_command,
                options.timeout_seconds,
                &candidate.id,
                &candidate.mutation,
                &candidate.file,
            )?;
            match (output.timed_out, output.status.code()) {
                (false, Some(0)) => {
                    summary.survived += 1;
                    "survived"
                }
                (true, _) => {
                    summary.timed_out += 1;
                    "timeout"
                }
                _ => {
                    summary.killed += 1;
                    "killed"
                }
            }
        };
        writeln!(
            stdout,
            "MUTANT {}/{} {} {} {} {} -> {}",
            index + 1,
            candidates.len(),
            result,
            candidate.mutation,
            candidate.location(),
            serde_json::to_string(&candidate.text).map_err(json_error)?,
            serde_json::to_string(&candidate.replacement).map_err(json_error)?,
        )
        .map_err(io_error)?;
    }

    writeln!(
        stdout,
        "SUMMARY total={} killed={} survived={} invalid={} timeout={}",
        candidates.len(),
        summary.killed,
        summary.survived,
        summary.invalid,
        summary.timed_out
    )
    .map_err(io_error)?;

    Ok(u8::from(summary.survived > 0 || summary.timed_out > 0))
}

fn io_error(error: io::Error) -> String {
    format!("I/O error: {error}")
}

fn json_error(error: serde_json::Error) -> String {
    format!("JSON error: {error}")
}
