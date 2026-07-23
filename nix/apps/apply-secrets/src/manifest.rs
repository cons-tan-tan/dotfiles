use std::collections::HashSet;
use std::fs;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Deserializer, de};

use crate::error::AppError;

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub enum Format {
    #[default]
    Raw,
    SshConfigYaml,
}

impl<'de> Deserialize<'de> for Format {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        let value = String::deserialize(deserializer)?;
        match value.as_str() {
            "raw" => Ok(Self::Raw),
            "ssh-config-yaml" => Ok(Self::SshConfigYaml),
            _ => Err(de::Error::custom(format!("unsupported format '{value}'"))),
        }
    }
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct ManifestEntry {
    src: String,
    dst: String,
    #[serde(default)]
    format: Format,
    #[serde(deserialize_with = "deserialize_mode")]
    mode: String,
    #[serde(rename = "dirMode", deserialize_with = "deserialize_directory_mode")]
    dir_mode: String,
}

fn deserialize_mode<'de, D>(deserializer: D) -> Result<String, D::Error>
where
    D: Deserializer<'de>,
{
    String::deserialize(deserializer)
        .map_err(|_| de::Error::custom("mode must be a non-empty string"))
}

fn deserialize_directory_mode<'de, D>(deserializer: D) -> Result<String, D::Error>
where
    D: Deserializer<'de>,
{
    String::deserialize(deserializer)
        .map_err(|_| de::Error::custom("dirMode must be a non-empty string"))
}

#[derive(Debug)]
pub struct Entry {
    pub relative_source: String,
    pub relative_destination: String,
    pub source: PathBuf,
    pub destination: PathBuf,
    pub format: Format,
    pub mode: u32,
    pub directory_mode: u32,
}

pub fn load_and_preflight(
    manifest_path: &Path,
    root: &Path,
    home: &Path,
) -> Result<Vec<Entry>, AppError> {
    ensure_base_directory(root, "source root")?;
    ensure_base_directory(home, "HOME")?;

    let bytes = fs::read(manifest_path)
        .map_err(|error| AppError::io("failed to read manifest", manifest_path, error))?;
    let raw_entries: Vec<ManifestEntry> = serde_json::from_slice(&bytes)
        .map_err(|error| AppError::Manifest(format!("invalid JSON: {error}")))?;

    let mut destinations = HashSet::new();
    let mut entries = Vec::with_capacity(raw_entries.len());
    for (index, raw) in raw_entries.into_iter().enumerate() {
        let number = index + 1;
        let source_relative = validate_relative("src", &raw.src, number)?;
        let destination_relative = validate_relative("dst", &raw.dst, number)?;
        let mode = parse_mode("mode", &raw.mode, number)?;
        let directory_mode = parse_mode("dirMode", &raw.dir_mode, number)?;

        let source = root.join(&source_relative);
        validate_source(root, &source_relative, number)?;

        let destination = home.join(&destination_relative);
        validate_destination(home, &destination_relative, number)?;
        if !destinations.insert(destination_relative.clone()) {
            return Err(AppError::Manifest(format!(
                "entry {number}: duplicate dst '{}'",
                raw.dst
            )));
        }

        entries.push(Entry {
            relative_source: raw.src,
            relative_destination: raw.dst,
            source,
            destination,
            format: raw.format,
            mode,
            directory_mode,
        });
    }

    Ok(entries)
}

fn ensure_base_directory(path: &Path, label: &str) -> Result<(), AppError> {
    let metadata = fs::metadata(path)
        .map_err(|error| AppError::Manifest(format!("{label} {}: {error}", path.display())))?;
    if !metadata.is_dir() {
        return Err(AppError::Manifest(format!(
            "{label} {} is not a directory",
            path.display()
        )));
    }
    Ok(())
}

fn validate_relative(field: &str, value: &str, number: usize) -> Result<PathBuf, AppError> {
    if value.is_empty() {
        return Err(AppError::Manifest(format!(
            "entry {number}: {field} must be a non-empty string"
        )));
    }
    if value.starts_with('/') {
        return Err(AppError::Manifest(format!(
            "entry {number}: {field} must be relative"
        )));
    }
    if value
        .split('/')
        .any(|component| component.is_empty() || component == "." || component == "..")
    {
        let boundary = if field == "dst" {
            "HOME"
        } else {
            "source root"
        };
        return Err(AppError::Manifest(format!(
            "entry {number}: {field} '{value}' escapes {boundary}"
        )));
    }
    Ok(PathBuf::from(value))
}

fn parse_mode(field: &str, value: &str, number: usize) -> Result<u32, AppError> {
    if !(value.len() == 3 || value.len() == 4)
        || !value.bytes().all(|byte| matches!(byte, b'0'..=b'7'))
    {
        return Err(AppError::Manifest(format!(
            "entry {number}: {field} must be a 3- or 4-digit octal string"
        )));
    }
    u32::from_str_radix(value, 8).map_err(|_| {
        AppError::Manifest(format!("entry {number}: {field} must be a valid Unix mode"))
    })
}

fn validate_source(root: &Path, relative: &Path, number: usize) -> Result<(), AppError> {
    let mut current = root.to_path_buf();
    let component_count = relative.components().count();
    for (index, component) in relative.components().enumerate() {
        current.push(component.as_os_str());
        let metadata = fs::symlink_metadata(&current).map_err(|error| {
            AppError::Manifest(format!(
                "entry {number}: {} is not in the repo: {error}",
                relative.display()
            ))
        })?;
        if metadata.file_type().is_symlink() {
            return Err(AppError::Manifest(format!(
                "entry {number}: src '{}' contains a symlink",
                relative.display()
            )));
        }
        let is_last = index + 1 == component_count;
        if (!is_last && !metadata.is_dir()) || (is_last && !metadata.is_file()) {
            return Err(AppError::Manifest(format!(
                "entry {number}: {} is not a regular file in the repo",
                relative.display()
            )));
        }
    }
    Ok(())
}

pub(crate) fn validate_destination(
    home: &Path,
    relative: &Path,
    number: usize,
) -> Result<(), AppError> {
    let mut current = home.to_path_buf();
    let component_count = relative.components().count();
    for (index, component) in relative.components().enumerate() {
        current.push(component.as_os_str());
        let metadata = match fs::symlink_metadata(&current) {
            Ok(metadata) => metadata,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => break,
            Err(error) => {
                return Err(AppError::Manifest(format!(
                    "entry {number}: cannot inspect dst '{}': {error}",
                    relative.display()
                )));
            }
        };
        if metadata.file_type().is_symlink() {
            return Err(AppError::Manifest(format!(
                "entry {number}: dst '{}' contains a symlink",
                relative.display()
            )));
        }
        let is_last = index + 1 == component_count;
        if (!is_last && !metadata.is_dir()) || (is_last && !metadata.is_file()) {
            return Err(AppError::Manifest(format!(
                "entry {number}: dst '{}' is not a regular file path",
                relative.display()
            )));
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use std::os::unix::fs::symlink;

    use tempfile::TempDir;

    use super::*;

    fn fixture() -> (TempDir, PathBuf, PathBuf, PathBuf) {
        let temp = TempDir::new().unwrap();
        let root = temp.path().join("root");
        let home = temp.path().join("home");
        fs::create_dir_all(root.join("secrets")).unwrap();
        fs::create_dir(&home).unwrap();
        fs::write(root.join("secrets/demo"), b"encrypted").unwrap();
        let manifest = temp.path().join("manifest.json");
        (temp, root, home, manifest)
    }

    #[test]
    fn rejects_malformed_json_and_non_array() {
        let (_temp, root, home, manifest) = fixture();
        fs::write(&manifest, b"{").unwrap();
        assert!(load_and_preflight(&manifest, &root, &home).is_err());
        fs::write(&manifest, br#"{"src":"secrets/demo"}"#).unwrap();
        assert!(load_and_preflight(&manifest, &root, &home).is_err());
    }

    #[test]
    fn rejects_unknown_fields_invalid_modes_and_duplicates() {
        let (_temp, root, home, manifest) = fixture();
        fs::write(
            &manifest,
            br#"[{"src":"secrets/demo","dst":"out","mode":"600","dirMode":"700","typo":true}]"#,
        )
        .unwrap();
        assert!(load_and_preflight(&manifest, &root, &home).is_err());

        fs::write(
            &manifest,
            br#"[{"src":"secrets/demo","dst":"out","mode":"68x","dirMode":"700"}]"#,
        )
        .unwrap();
        assert!(load_and_preflight(&manifest, &root, &home).is_err());

        fs::write(
            &manifest,
            br#"[
              {"src":"secrets/demo","dst":"out","mode":"600","dirMode":"700"},
              {"src":"secrets/demo","dst":"out","mode":"600","dirMode":"700"}
            ]"#,
        )
        .unwrap();
        assert!(load_and_preflight(&manifest, &root, &home).is_err());
    }

    #[test]
    fn rejects_missing_empty_and_wrong_typed_required_fields() {
        let (_temp, root, home, manifest) = fixture();
        for document in [
            br#"[{"dst":"out","mode":"600","dirMode":"700"}]"#.as_slice(),
            br#"[{"src":"secrets/demo","mode":"600","dirMode":"700"}]"#.as_slice(),
            br#"[{"src":"secrets/demo","dst":"out","dirMode":"700"}]"#.as_slice(),
            br#"[{"src":"secrets/demo","dst":"out","mode":"600"}]"#.as_slice(),
            br#"[{"src":"","dst":"out","mode":"600","dirMode":"700"}]"#.as_slice(),
            br#"[{"src":"secrets/demo","dst":"","mode":"600","dirMode":"700"}]"#.as_slice(),
            br#"[{"src":"secrets/demo","dst":"out","mode":"","dirMode":"700"}]"#.as_slice(),
            br#"[{"src":"secrets/demo","dst":"out","mode":"600","dirMode":""}]"#.as_slice(),
            br#"[{"src":"secrets/demo","dst":"out","mode":null,"dirMode":"700"}]"#.as_slice(),
        ] {
            fs::write(&manifest, document).unwrap();
            assert!(
                load_and_preflight(&manifest, &root, &home).is_err(),
                "document should be rejected"
            );
        }
    }

    #[test]
    fn rejects_unsupported_format_and_missing_source() {
        let (_temp, root, home, manifest) = fixture();
        fs::write(
            &manifest,
            br#"[{"src":"secrets/demo","dst":"out","format":"unsupported","mode":"600","dirMode":"700"}]"#,
        )
        .unwrap();
        assert!(load_and_preflight(&manifest, &root, &home).is_err());

        fs::write(
            &manifest,
            br#"[{"src":"secrets/missing","dst":"out","mode":"600","dirMode":"700"}]"#,
        )
        .unwrap();
        assert!(load_and_preflight(&manifest, &root, &home).is_err());
    }

    #[test]
    fn rejects_unsafe_paths_and_symlinks() {
        let (_temp, root, home, manifest) = fixture();
        for path in ["/absolute", "../escape", "a/./b", "a//b"] {
            fs::write(
                &manifest,
                format!(
                    r#"[{{"src":"secrets/demo","dst":"{path}","mode":"600","dirMode":"700"}}]"#
                ),
            )
            .unwrap();
            assert!(load_and_preflight(&manifest, &root, &home).is_err());
        }

        symlink(root.join("secrets/demo"), root.join("secrets/link")).unwrap();
        fs::write(
            &manifest,
            br#"[{"src":"secrets/link","dst":"out","mode":"600","dirMode":"700"}]"#,
        )
        .unwrap();
        assert!(load_and_preflight(&manifest, &root, &home).is_err());

        let outside = home.parent().unwrap().join("outside");
        fs::create_dir(&outside).unwrap();
        symlink(&outside, home.join("link")).unwrap();
        fs::write(
            &manifest,
            br#"[{"src":"secrets/demo","dst":"link/out","mode":"600","dirMode":"700"}]"#,
        )
        .unwrap();
        assert!(load_and_preflight(&manifest, &root, &home).is_err());
    }

    #[test]
    fn accepts_valid_manifest_and_defaults_format() {
        let (_temp, root, home, manifest) = fixture();
        fs::write(
            &manifest,
            br#"[{"src":"secrets/demo","dst":"nested/out","mode":"0600","dirMode":"700"}]"#,
        )
        .unwrap();
        let entries = load_and_preflight(&manifest, &root, &home).unwrap();
        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0].format, Format::Raw);
        assert_eq!(entries[0].mode, 0o600);
    }
}
