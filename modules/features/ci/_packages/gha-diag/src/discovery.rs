use serde::Serialize;
use std::collections::BTreeSet;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};

pub const MAX_DOCUMENT_BYTES: u64 = 4 * 1024 * 1024;
const MAX_DEFAULT_ACTION_DIRECTORY_DEPTH: usize = 3;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum DocumentKind {
    Workflow,
    Action,
}

impl DocumentKind {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Workflow => "workflow",
            Self::Action => "action",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ResolvedInput {
    pub path: PathBuf,
    pub kind: DocumentKind,
}

pub fn discover(root: &Path) -> io::Result<Vec<PathBuf>> {
    let mut files = BTreeSet::new();
    discover_workflows(root, &mut files)?;
    discover_action_metadata(root, 0, &mut files)?;
    Ok(files.into_iter().collect())
}

fn discover_workflows(root: &Path, files: &mut BTreeSet<PathBuf>) -> io::Result<()> {
    let github = root.join(".github");
    let Some(github_metadata) = metadata_if_present(&github)? else {
        return Ok(());
    };
    if github_metadata.file_type().is_symlink() {
        return Ok(());
    }

    let directory = github.join("workflows");
    let Some(directory_metadata) = metadata_if_present(&directory)? else {
        return Ok(());
    };
    if directory_metadata.file_type().is_symlink() {
        return Ok(());
    }
    let entries = match fs::read_dir(&directory) {
        Ok(entries) => entries,
        Err(error) => {
            return Err(io::Error::new(
                error.kind(),
                format!("cannot read directory {}: {error}", directory.display()),
            ));
        }
    };

    for entry in entries {
        let entry = entry?;
        let file_type = entry.file_type()?;
        if !file_type.is_file() || file_type.is_symlink() {
            continue;
        }
        let path = entry.path();
        if has_default_yaml_extension(&path) {
            files.insert(path);
        }
    }
    Ok(())
}

fn metadata_if_present(path: &Path) -> io::Result<Option<fs::Metadata>> {
    match fs::symlink_metadata(path) {
        Ok(metadata) => Ok(Some(metadata)),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(None),
        Err(error) => Err(io::Error::new(
            error.kind(),
            format!("cannot inspect {}: {error}", path.display()),
        )),
    }
}

fn discover_action_metadata(
    directory: &Path,
    depth: usize,
    files: &mut BTreeSet<PathBuf>,
) -> io::Result<()> {
    let entries = fs::read_dir(directory).map_err(|error| {
        io::Error::new(
            error.kind(),
            format!("cannot read directory {}: {error}", directory.display()),
        )
    })?;

    let mut child_directories = Vec::new();
    for entry in entries {
        let entry = entry.map_err(|error| {
            io::Error::new(
                error.kind(),
                format!("cannot read entry under {}: {error}", directory.display()),
            )
        })?;
        let file_type = entry.file_type().map_err(|error| {
            io::Error::new(
                error.kind(),
                format!("cannot inspect {}: {error}", entry.path().display()),
            )
        })?;
        if file_type.is_symlink() {
            continue;
        }
        if file_type.is_file() && is_default_action_name(&entry.file_name()) {
            files.insert(entry.path());
        } else if depth < MAX_DEFAULT_ACTION_DIRECTORY_DEPTH && file_type.is_dir() {
            child_directories.push(entry.path());
        }
    }

    child_directories.sort();
    for child in child_directories {
        discover_action_metadata(&child, depth + 1, files)?;
    }
    Ok(())
}

fn has_default_yaml_extension(path: &Path) -> bool {
    path.extension()
        .is_some_and(|extension| extension == "yml" || extension == "yaml")
}

fn is_default_action_name(name: &std::ffi::OsStr) -> bool {
    name == "action.yml" || name == "action.yaml"
}

fn is_supported_yaml(path: &Path) -> bool {
    path.extension()
        .and_then(|extension| extension.to_str())
        .is_some_and(|extension| {
            extension.eq_ignore_ascii_case("yml") || extension.eq_ignore_ascii_case("yaml")
        })
}

pub fn document_kind(path: &Path) -> DocumentKind {
    if is_official_workflow_path(path) {
        return DocumentKind::Workflow;
    }
    if path
        .file_name()
        .and_then(|name| name.to_str())
        .is_some_and(|name| {
            name.eq_ignore_ascii_case("action.yml") || name.eq_ignore_ascii_case("action.yaml")
        })
    {
        return DocumentKind::Action;
    }

    // @actions/languageservice currently routes every non-action document to
    // workflow validation. Recording that effective route is more useful than
    // exposing its intermediate "unknown" classification.
    DocumentKind::Workflow
}

fn is_official_workflow_path(path: &Path) -> bool {
    if !is_supported_yaml(path) {
        return false;
    }
    let Some(workflows) = path.parent() else {
        return false;
    };
    let Some(github) = workflows.parent() else {
        return false;
    };
    workflows
        .file_name()
        .and_then(|name| name.to_str())
        .is_some_and(|name| {
            name.eq_ignore_ascii_case("workflows") || name.eq_ignore_ascii_case("workflows-lab")
        })
        && github
            .file_name()
            .and_then(|name| name.to_str())
            .is_some_and(|name| name.eq_ignore_ascii_case(".github"))
}

pub fn resolve_inputs(root: &Path, inputs: &[PathBuf]) -> Result<Vec<ResolvedInput>, String> {
    let canonical_root = root
        .canonicalize()
        .map_err(|error| format!("cannot resolve repository root {}: {error}", root.display()))?;
    let candidates = if inputs.is_empty() {
        discover(&canonical_root)
            .map_err(|error| format!("cannot discover GitHub Actions files: {error}"))?
    } else {
        inputs
            .iter()
            .map(|input| {
                if input.is_absolute() {
                    input.clone()
                } else {
                    canonical_root.join(input)
                }
            })
            .collect()
    };

    let mut resolved = BTreeSet::new();
    for candidate in candidates {
        let candidate_metadata = fs::symlink_metadata(&candidate).map_err(|error| {
            format!(
                "input file does not exist or cannot be inspected: {}: {error}",
                candidate.display()
            )
        })?;
        if candidate_metadata.file_type().is_symlink() {
            return Err(format!(
                "input path is a symbolic link: {}",
                candidate.display()
            ));
        }
        let canonical = candidate.canonicalize().map_err(|error| {
            format!(
                "input file does not exist or cannot be resolved: {}: {error}",
                candidate.display()
            )
        })?;
        if !canonical.starts_with(&canonical_root) {
            return Err(format!(
                "input file escapes repository root: {}",
                candidate.display()
            ));
        }
        let metadata = fs::metadata(&canonical).map_err(|error| {
            format!("cannot inspect input file {}: {error}", candidate.display())
        })?;
        if !metadata.is_file() {
            return Err(format!(
                "input path is not a regular file: {}",
                candidate.display()
            ));
        }
        if metadata.len() > MAX_DOCUMENT_BYTES {
            return Err(format!(
                "input file exceeds the {} byte limit: {}",
                MAX_DOCUMENT_BYTES,
                candidate.display()
            ));
        }
        if !is_supported_yaml(&canonical) {
            return Err(format!("input file is not YAML: {}", candidate.display()));
        }
        resolved.insert(canonical);
    }
    Ok(resolved
        .into_iter()
        .map(|path| ResolvedInput {
            kind: document_kind(&path),
            path,
        })
        .collect())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    #[test]
    fn discovers_the_same_default_regular_files_as_pinact() {
        let temporary = tempfile::tempdir().expect("temporary directory");
        let paths = [
            ".github/workflows/ci.yaml",
            ".github/workflows/lint.yml",
            ".github/workflows/action.yml",
            ".github/workflows/UPPER.YAML",
            ".github/workflows/nested/ignored.yaml",
            ".github/actions/example/action.yml",
            "action.yml",
            "action.yaml",
            "one/action.yml",
            "one/action.yaml",
            "one/two/action.yml",
            "one/two/action.yaml",
            "one/two/three/action.yml",
            "one/two/three/action.yaml",
            "one/two/three/four/action.yml",
            "one/two/not-action.yaml",
            "ACTION.YML",
        ];
        for path in paths {
            let absolute = temporary.path().join(path);
            fs::create_dir_all(absolute.parent().expect("parent directory"))
                .expect("fixture directory");
            fs::write(absolute, "name: fixture\n").expect("fixture file");
        }

        let result = discover(temporary.path()).expect("discovery succeeds");
        let relative: Vec<_> = result
            .iter()
            .map(|path| {
                path.strip_prefix(temporary.path())
                    .expect("relative path")
                    .to_string_lossy()
                    .replace('\\', "/")
            })
            .collect();
        assert_eq!(
            relative,
            [
                ".github/actions/example/action.yml",
                ".github/workflows/action.yml",
                ".github/workflows/ci.yaml",
                ".github/workflows/lint.yml",
                "action.yaml",
                "action.yml",
                "one/action.yaml",
                "one/action.yml",
                "one/two/action.yaml",
                "one/two/action.yml",
                "one/two/three/action.yaml",
                "one/two/three/action.yml",
            ]
        );
    }

    #[test]
    fn mirrors_the_language_service_validation_route() {
        assert_eq!(
            document_kind(Path::new(".github/workflows/action.yml")),
            DocumentKind::Workflow
        );
        assert_eq!(
            document_kind(Path::new(".github/workflows-lab/action.yaml")),
            DocumentKind::Workflow
        );
        assert_eq!(
            document_kind(Path::new(".github/actions/example/ACTION.YML")),
            DocumentKind::Action
        );
        assert_eq!(
            document_kind(Path::new("custom/workflow.yaml")),
            DocumentKind::Workflow
        );
    }

    #[test]
    fn explicit_deep_action_is_accepted_and_classified_as_action() {
        let root = tempfile::tempdir().expect("repository");
        let action = root.path().join("one/two/three/four/action.yml");
        fs::create_dir_all(action.parent().expect("action directory")).expect("action directory");
        fs::write(&action, "name: fixture\n").expect("action");

        let resolved = resolve_inputs(
            root.path(),
            &[PathBuf::from("one/two/three/four/action.yml")],
        )
        .expect("explicit action");
        assert_eq!(resolved.len(), 1);
        assert_eq!(resolved[0].kind, DocumentKind::Action);
    }

    #[test]
    fn rejects_an_input_outside_the_repository() {
        let root = tempfile::tempdir().expect("repository");
        let outside = tempfile::NamedTempFile::new().expect("outside file");
        let error = resolve_inputs(root.path(), &[outside.path().to_path_buf()])
            .expect_err("must reject escape");
        assert!(error.contains("escapes repository root"));
    }

    #[cfg(unix)]
    #[test]
    fn default_discovery_does_not_follow_symbolic_links() {
        use std::os::unix::fs::symlink;

        let root = tempfile::tempdir().expect("repository");
        let outside = tempfile::tempdir().expect("outside directory");
        fs::write(outside.path().join("action.yml"), "name: outside\n").expect("outside action");
        symlink(
            outside.path().join("action.yml"),
            root.path().join("action.yml"),
        )
        .expect("file symlink");
        symlink(outside.path(), root.path().join("linked")).expect("directory symlink");

        assert!(
            discover(root.path())
                .expect("discovery succeeds")
                .is_empty()
        );
    }

    #[cfg(unix)]
    #[test]
    fn workflow_discovery_does_not_follow_symbolic_directory_components() {
        use std::os::unix::fs::symlink;

        let outside = tempfile::tempdir().expect("outside directory");
        let outside_workflows = outside.path().join("workflows");
        fs::create_dir_all(&outside_workflows).expect("outside workflows");
        fs::write(outside_workflows.join("ci.yaml"), "on: push\n").expect("outside workflow");

        let github_link_root = tempfile::tempdir().expect("repository");
        symlink(outside.path(), github_link_root.path().join(".github")).expect(".github symlink");
        assert!(
            discover(github_link_root.path())
                .expect("discovery succeeds")
                .is_empty()
        );

        let workflows_link_root = tempfile::tempdir().expect("repository");
        fs::create_dir(workflows_link_root.path().join(".github")).expect(".github directory");
        symlink(
            &outside_workflows,
            workflows_link_root.path().join(".github/workflows"),
        )
        .expect("workflows symlink");
        assert!(
            discover(workflows_link_root.path())
                .expect("discovery succeeds")
                .is_empty()
        );
    }

    #[cfg(unix)]
    #[test]
    fn explicit_symbolic_link_is_rejected() {
        use std::os::unix::fs::symlink;

        let root = tempfile::tempdir().expect("repository");
        let outside = tempfile::NamedTempFile::new().expect("outside file");
        symlink(outside.path(), root.path().join("action.yml")).expect("file symlink");

        let error = resolve_inputs(root.path(), &[PathBuf::from("action.yml")])
            .expect_err("must reject symbolic link");
        assert!(error.contains("symbolic link"));
    }

    #[test]
    fn rejects_an_oversized_document() {
        let root = tempfile::tempdir().expect("repository");
        let workflow = root.path().join("workflow.yaml");
        let file = fs::File::create(&workflow).expect("workflow");
        file.set_len(MAX_DOCUMENT_BYTES + 1)
            .expect("oversized workflow");

        let error = resolve_inputs(root.path(), &[workflow]).expect_err("must reject large file");
        assert!(error.contains("exceeds"));
    }
}
