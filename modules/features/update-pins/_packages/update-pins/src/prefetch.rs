use std::fs::File;
use std::io;
use std::path::{Component, Path, PathBuf};
use std::time::Duration;

use flate2::read::MultiGzDecoder;
use serde_json::Value;
use tar::EntryType;

use crate::command::{CommandRunner, CommandSpec, run_checked_limited_with_timeout};
use crate::error::{FetchFailureKind, UpdateError};
use crate::fetch::{FetchLimits, download_bounded_with_limits};
use crate::policy::RunPolicy;
use crate::value_validation::validate_sri_hash;

const DEFAULT_MAX_DOWNLOAD_BYTES: u64 = 2 * 1024 * 1024 * 1024;
const PREFETCH_STDOUT_LIMIT: usize = 64 * 1024;
const PREFETCH_STDERR_LIMIT: usize = 64 * 1024;
const PREFETCH_TIMEOUT: Duration = Duration::from_secs(60 * 60);
const TAR_MAX_ENTRIES: u64 = 50_000;
const TAR_MAX_EXPANSION_RATIO: u64 = 32;
const TAR_MIN_EXPANDED_BYTES: u64 = 64 * 1024;
const TAR_MAX_EXPANDED_BYTES: u64 = 512 * 1024 * 1024;
const TAR_MAX_PATH_BYTES: usize = 4_096;

#[derive(Clone, Copy)]
pub(crate) struct TarPreflightLimits {
    pub(crate) max_entries: u64,
    pub(crate) max_expanded_bytes: u64,
    pub(crate) max_path_bytes: usize,
}

pub(crate) struct ExpandedLimitReader<R> {
    inner: R,
    remaining: u64,
    max_expanded_bytes: u64,
    exceeded: bool,
}

impl<R> ExpandedLimitReader<R> {
    pub(crate) fn new(inner: R, max_expanded_bytes: u64) -> Self {
        Self {
            inner,
            remaining: max_expanded_bytes,
            max_expanded_bytes,
            exceeded: false,
        }
    }

    fn limit_error(&self) -> io::Error {
        io::Error::other(format!(
            "tar archive exceeded the {}-byte expanded limit",
            self.max_expanded_bytes
        ))
    }
}

impl<R: io::Read> io::Read for ExpandedLimitReader<R> {
    fn read(&mut self, buffer: &mut [u8]) -> io::Result<usize> {
        if buffer.is_empty() {
            return Ok(0);
        }
        if self.exceeded {
            return Err(self.limit_error());
        }
        if self.remaining == 0 {
            let mut probe = [0_u8; 1];
            return match self.inner.read(&mut probe) {
                Ok(0) => Ok(0),
                Ok(_) => {
                    self.exceeded = true;
                    Err(self.limit_error())
                }
                Err(source) => Err(source),
            };
        }

        let allowed = usize::try_from(self.remaining)
            .unwrap_or(usize::MAX)
            .min(buffer.len());
        let read = self.inner.read(&mut buffer[..allowed])?;
        self.remaining -= read as u64;
        Ok(read)
    }
}

pub struct PrefetchResult {
    pub hash: String,
    pub store_path: Option<PathBuf>,
    #[cfg_attr(not(feature = "smoke"), allow(dead_code))]
    pub download_bytes: u64,
}

pub fn prefetch_hash<R: CommandRunner>(
    label: &str,
    policy: RunPolicy,
    runner: &R,
    root: &Path,
    url: &str,
    unpack: bool,
) -> Result<String, UpdateError> {
    Ok(prefetch_result(label, policy, runner, root, url, unpack)?.hash)
}

pub fn prefetch_result<R: CommandRunner>(
    label: &str,
    policy: RunPolicy,
    runner: &R,
    root: &Path,
    url: &str,
    unpack: bool,
) -> Result<PrefetchResult, UpdateError> {
    prefetch_result_bounded(
        label,
        policy,
        runner,
        root,
        url,
        unpack,
        DEFAULT_MAX_DOWNLOAD_BYTES,
        FetchLimits::default(),
        PREFETCH_TIMEOUT,
    )
}

#[allow(clippy::too_many_arguments)]
pub(crate) fn prefetch_result_bounded<R: CommandRunner>(
    label: &str,
    policy: RunPolicy,
    runner: &R,
    root: &Path,
    url: &str,
    unpack: bool,
    max_download_bytes: u64,
    fetch_limits: FetchLimits,
    timeout: Duration,
) -> Result<PrefetchResult, UpdateError> {
    let downloaded = download_bounded_with_limits(
        policy.retry,
        runner,
        root,
        label.split(':').next().unwrap_or("update-pins"),
        "artifact download",
        url,
        max_download_bytes,
        fetch_limits,
    )?;
    let download_bytes = std::fs::metadata(downloaded.path())
        .map_err(|source| UpdateError::io(downloaded.path(), source))?
        .len();
    if download_bytes > max_download_bytes {
        return Err(archive_drift(
            label,
            format!("download exceeded the {max_download_bytes}-byte limit"),
        ));
    }
    if unpack && is_tar_gz_url(url) {
        preflight_tar_gz(
            label,
            downloaded.path(),
            tar_preflight_limits(max_download_bytes),
        )?;
    }
    let local_url = local_file_url(downloaded.path())?;
    let store_name = deterministic_store_name(url);
    let mut command = CommandSpec::new("nix")
        .args(["store", "prefetch-file", "--json", "--name", &store_name])
        .current_dir(root);
    if unpack {
        command = command.arg("--unpack");
    }
    command = command.arg(&local_url);
    let output = run_checked_limited_with_timeout(
        runner,
        &command,
        PREFETCH_STDOUT_LIMIT,
        PREFETCH_STDERR_LIMIT,
        timeout,
    )
    .map_err(|error| UpdateError::message(format!("{label}: {error}")))?;
    let response: Value = serde_json::from_slice(&output.stdout).map_err(|source| {
        UpdateError::message(format!("{label}: prefetch returned invalid JSON: {source}"))
    })?;
    let hash = response
        .get("hash")
        .and_then(Value::as_str)
        .filter(|hash| !hash.is_empty())
        .map(ToOwned::to_owned)
        .ok_or_else(|| UpdateError::message(format!("{label}: prefetch did not return a hash")))?;
    validate_sri_hash(label, &hash)?;
    let store_path = response
        .get("storePath")
        .and_then(Value::as_str)
        .filter(|path| !path.is_empty())
        .map(PathBuf::from);
    Ok(PrefetchResult {
        hash,
        store_path,
        download_bytes,
    })
}

pub(crate) fn tar_preflight_limits(max_download_bytes: u64) -> TarPreflightLimits {
    TarPreflightLimits {
        max_entries: TAR_MAX_ENTRIES,
        max_expanded_bytes: max_download_bytes
            .saturating_mul(TAR_MAX_EXPANSION_RATIO)
            .clamp(TAR_MIN_EXPANDED_BYTES, TAR_MAX_EXPANDED_BYTES),
        max_path_bytes: TAR_MAX_PATH_BYTES,
    }
}

fn preflight_tar_gz(
    label: &str,
    path: &Path,
    limits: TarPreflightLimits,
) -> Result<(), UpdateError> {
    let file = File::open(path).map_err(|source| UpdateError::io(path, source))?;
    let decoder = MultiGzDecoder::new(file);
    let decoder = ExpandedLimitReader::new(decoder, limits.max_expanded_bytes);
    let mut archive = tar::Archive::new(decoder);
    let mut entry_count = 0_u64;
    let mut expanded_bytes = 0_u64;

    {
        let entries = archive
            .entries()
            .map_err(|source| archive_drift(label, format!("invalid tar.gz archive: {source}")))?;
        for entry in entries {
            entry_count = entry_count
                .checked_add(1)
                .ok_or_else(|| archive_drift(label, "tar entry count overflowed"))?;
            if entry_count > limits.max_entries {
                return Err(archive_drift(
                    label,
                    format!(
                        "tar archive exceeded the {}-entry limit",
                        limits.max_entries
                    ),
                ));
            }

            let mut entry = entry.map_err(|source| {
                archive_drift(label, format!("invalid tar.gz archive: {source}"))
            })?;
            validate_tar_entry(label, &entry, limits.max_path_bytes)?;
            let declared_size = entry.size();
            expanded_bytes = expanded_bytes
                .checked_add(declared_size)
                .ok_or_else(|| archive_drift(label, "tar expanded byte count overflowed"))?;
            enforce_expanded_limit(label, expanded_bytes, limits.max_expanded_bytes)?;

            let copied = io::copy(&mut entry, &mut io::sink()).map_err(|source| {
                archive_drift(label, format!("invalid tar.gz archive data: {source}"))
            })?;
            if copied != declared_size {
                return Err(archive_drift(label, "tar entry data was truncated"));
            }
        }
    }

    let mut decoder = archive.into_inner();
    io::copy(&mut decoder, &mut io::sink()).map_err(|source| {
        archive_drift(label, format!("invalid tar.gz archive trailer: {source}"))
    })?;
    Ok(())
}

fn validate_tar_entry<R: io::Read>(
    label: &str,
    entry: &tar::Entry<'_, R>,
    max_path_bytes: usize,
) -> Result<(), UpdateError> {
    let path = entry
        .path()
        .map_err(|source| archive_drift(label, format!("invalid tar entry path: {source}")))?;
    if !is_safe_archive_path(&path, max_path_bytes) {
        return Err(archive_drift(
            label,
            "tar archive contained an unsafe entry path",
        ));
    }

    let entry_type = entry.header().entry_type();
    if entry_type.is_file()
        || entry_type.is_dir()
        || entry_type.is_pax_global_extensions()
        || entry_type.is_pax_local_extensions()
        || entry_type.is_gnu_longname()
        || entry_type.is_gnu_longlink()
    {
        return Ok(());
    }
    if entry_type.is_symlink() {
        let target = tar_link_target(label, entry)?;
        if symlink_target_stays_within_archive(&path, &target, max_path_bytes) {
            return Ok(());
        }
        return Err(archive_drift(
            label,
            "tar archive contained an unsafe symlink target",
        ));
    }
    if entry_type.is_hard_link() {
        let target = tar_link_target(label, entry)?;
        if is_safe_archive_path(&target, max_path_bytes) {
            return Ok(());
        }
        return Err(archive_drift(
            label,
            "tar archive contained an unsafe hard-link target",
        ));
    }

    Err(unsupported_tar_entry_type(label, entry_type))
}

fn tar_link_target<R: io::Read>(
    label: &str,
    entry: &tar::Entry<'_, R>,
) -> Result<PathBuf, UpdateError> {
    entry
        .link_name()
        .map_err(|source| archive_drift(label, format!("invalid tar link target: {source}")))?
        .map(|target| target.into_owned())
        .ok_or_else(|| archive_drift(label, "tar link target was missing"))
}

fn unsupported_tar_entry_type(label: &str, entry_type: EntryType) -> UpdateError {
    archive_drift(
        label,
        format!(
            "tar archive contained unsupported entry type 0x{:02x}",
            entry_type.as_byte()
        ),
    )
}

fn is_safe_archive_path(path: &Path, max_path_bytes: usize) -> bool {
    !path.as_os_str().is_empty()
        && path.as_os_str().as_encoded_bytes().len() <= max_path_bytes
        && path
            .components()
            .all(|component| matches!(component, Component::Normal(_) | Component::CurDir))
}

fn symlink_target_stays_within_archive(
    entry_path: &Path,
    target: &Path,
    max_path_bytes: usize,
) -> bool {
    if target.as_os_str().is_empty() || target.as_os_str().as_encoded_bytes().len() > max_path_bytes
    {
        return false;
    }
    let mut depth = entry_path
        .parent()
        .into_iter()
        .flat_map(Path::components)
        .filter(|component| matches!(component, Component::Normal(_)))
        .count();
    for component in target.components() {
        match component {
            Component::Normal(_) => depth = depth.saturating_add(1),
            Component::CurDir => {}
            Component::ParentDir if depth > 0 => depth -= 1,
            Component::ParentDir | Component::RootDir | Component::Prefix(_) => return false,
        }
    }
    true
}

fn enforce_expanded_limit(
    label: &str,
    expanded_bytes: u64,
    max_expanded_bytes: u64,
) -> Result<(), UpdateError> {
    if expanded_bytes <= max_expanded_bytes {
        Ok(())
    } else {
        Err(archive_drift(
            label,
            format!("tar archive exceeded the {max_expanded_bytes}-byte expanded limit"),
        ))
    }
}

fn archive_drift(label: &str, detail: impl Into<String>) -> UpdateError {
    UpdateError::fetch(
        label.split(':').next().unwrap_or("update-pins"),
        "tar.gz preflight",
        FetchFailureKind::UpstreamDrift,
        detail,
    )
}

fn is_tar_gz_url(url: &str) -> bool {
    let path = url.split(['?', '#']).next().unwrap_or(url);
    path.ends_with(".tar.gz") || path.ends_with(".tgz")
}

fn local_file_url(path: &Path) -> Result<String, UpdateError> {
    if !path.is_absolute() {
        return Err(UpdateError::message(format!(
            "prefetch temporary path is not absolute: {}",
            path.display()
        )));
    }
    let bytes = path.as_os_str().as_encoded_bytes();
    let mut url = String::from("file://");
    for &byte in bytes {
        if byte.is_ascii_alphanumeric() || matches!(byte, b'/' | b'-' | b'.' | b'_' | b'~') {
            url.push(char::from(byte));
        } else {
            use std::fmt::Write as _;
            write!(url, "%{byte:02X}").expect("writing to a String cannot fail");
        }
    }
    Ok(url)
}

fn deterministic_store_name(url: &str) -> String {
    let basename = url
        .split(['?', '#'])
        .next()
        .and_then(|path| path.rsplit('/').next())
        .filter(|basename| !basename.is_empty())
        .unwrap_or("download");
    let sanitized = basename
        .chars()
        .map(|character| {
            if character.is_ascii_alphanumeric() || matches!(character, '+' | '-' | '.' | '_') {
                character
            } else {
                '-'
            }
        })
        .take(96)
        .collect::<String>();
    format!("update-pins-{sanitized}")
}

#[cfg(test)]
mod tests {
    use std::cell::Cell;
    use std::io;
    use std::path::{Path, PathBuf};
    use std::time::Duration;

    use flate2::Compression;
    use flate2::write::GzEncoder;

    use super::{
        TarPreflightLimits, deterministic_store_name, local_file_url, prefetch_result_bounded,
        preflight_tar_gz,
    };
    use crate::command::{CommandOutput, CommandRunner, CommandSpec};
    use crate::error::{FetchFailureKind, UpdateError};
    use crate::fetch::FetchLimits;
    use crate::policy::RunPolicy;

    #[test]
    fn local_file_url_percent_encodes_reserved_path_bytes() {
        assert_eq!(
            local_file_url(Path::new("/tmp/update pins/#asset%.zip")).expect("absolute UTF-8 path"),
            "file:///tmp/update%20pins/%23asset%25.zip"
        );
        assert!(local_file_url(Path::new("relative")).is_err());
    }

    #[test]
    fn store_name_is_deterministic_and_url_independent() {
        assert_eq!(
            deterministic_store_name("https://example.com/releases/tool-v1.tar.gz?token=hidden"),
            "update-pins-tool-v1.tar.gz"
        );
        assert_eq!(
            deterministic_store_name("https://example.com/"),
            "update-pins-download"
        );
    }

    #[test]
    fn oversized_download_is_rejected_before_nix_runs() {
        let runner = DownloadRunner::new(vec![0; 17]);
        let error = bounded_prefetch(&runner, 16)
            .err()
            .expect("download must be rejected");

        assert!(error.to_string().contains("download exceeded"));
        assert_upstream_drift(&error);
        assert_eq!(runner.nix_calls.get(), 0);
    }

    #[test]
    fn expansion_bomb_is_rejected_before_nix_runs() {
        let archive = tar_gz_file("source/large", &vec![0; 300 * 1024]);
        assert!(archive.len() < 4 * 1024);
        let runner = DownloadRunner::new(archive);
        let error = bounded_prefetch(&runner, 4 * 1024)
            .err()
            .expect("bomb must be rejected");

        assert!(error.to_string().contains("expanded limit"));
        assert_upstream_drift(&error);
        assert_eq!(runner.nix_calls.get(), 0);
    }

    #[test]
    fn hidden_longname_expansion_bomb_is_rejected_before_nix_runs() {
        let archive = tar_gz_hidden_longname_bomb(300 * 1024);
        assert!(archive.len() < 4 * 1024);
        let runner = DownloadRunner::new(archive);
        let error = bounded_prefetch(&runner, 4 * 1024)
            .err()
            .expect("hidden extension bomb must be rejected");

        assert!(error.to_string().contains("131072-byte expanded limit"));
        assert_upstream_drift(&error);
        assert_eq!(runner.nix_calls.get(), 0);
    }

    #[test]
    fn unsafe_tar_entry_is_rejected_before_nix_runs() {
        let runner = DownloadRunner::new(tar_gz_escaping_symlink());
        let error = bounded_prefetch(&runner, 4 * 1024)
            .err()
            .expect("link must be rejected");

        assert!(error.to_string().contains("unsafe symlink target"));
        assert_upstream_drift(&error);
        assert_eq!(runner.nix_calls.get(), 0);
    }

    #[test]
    fn absolute_tar_path_is_rejected_before_nix_runs() {
        let runner = DownloadRunner::new(tar_gz_absolute_file());
        let error = bounded_prefetch(&runner, 4 * 1024)
            .err()
            .expect("absolute path must be rejected");

        assert!(error.to_string().contains("unsafe entry path"));
        assert_upstream_drift(&error);
        assert_eq!(runner.nix_calls.get(), 0);
    }

    #[test]
    fn special_tar_type_is_rejected_before_nix_runs() {
        let runner = DownloadRunner::new(tar_gz_fifo());
        let error = bounded_prefetch(&runner, 4 * 1024)
            .err()
            .expect("special type must be rejected");

        assert!(error.to_string().contains("unsupported entry type"));
        assert_upstream_drift(&error);
        assert_eq!(runner.nix_calls.get(), 0);
    }

    #[test]
    fn tar_entry_count_is_bounded() {
        let archive = tar_gz_files(&[("source/one", b"1"), ("source/two", b"2")]);
        let file = tempfile::NamedTempFile::new().expect("temporary archive");
        std::fs::write(file.path(), archive).expect("write archive");

        let error = preflight_tar_gz(
            "test",
            file.path(),
            TarPreflightLimits {
                max_entries: 1,
                max_expanded_bytes: 1024,
                max_path_bytes: 4096,
            },
        )
        .expect_err("entry count must be rejected");
        assert!(error.to_string().contains("1-entry limit"));
        assert_upstream_drift(&error);
    }

    struct DownloadRunner {
        body: Vec<u8>,
        nix_calls: Cell<usize>,
    }

    impl DownloadRunner {
        fn new(body: Vec<u8>) -> Self {
            Self {
                body,
                nix_calls: Cell::new(0),
            }
        }
    }

    impl CommandRunner for DownloadRunner {
        fn run(&self, command: &CommandSpec) -> Result<CommandOutput, UpdateError> {
            Err(UpdateError::message(format!(
                "unexpected unbounded command {}",
                command.display()
            )))
        }

        fn run_limited_with_timeout(
            &self,
            command: &CommandSpec,
            _stdout_limit: usize,
            _stderr_limit: usize,
            _timeout: Duration,
        ) -> Result<CommandOutput, UpdateError> {
            match command.program.to_string_lossy().as_ref() {
                "curl" => {
                    let output_index = command
                        .args
                        .iter()
                        .position(|argument| argument == "--output")
                        .expect("curl output argument");
                    let output_path = PathBuf::from(&command.args[output_index + 1]);
                    std::fs::write(&output_path, &self.body)
                        .map_err(|source| UpdateError::io(&output_path, source))?;
                    Ok(CommandOutput {
                        status: Some(0),
                        stdout: b"200".to_vec(),
                        stderr: Vec::new(),
                    })
                }
                "nix" => {
                    self.nix_calls.set(self.nix_calls.get() + 1);
                    Err(UpdateError::message("nix must not run"))
                }
                program => Err(UpdateError::message(format!(
                    "unexpected command {program}"
                ))),
            }
        }

        fn is_available(&self, _program: &Path) -> bool {
            false
        }
    }

    fn bounded_prefetch(
        runner: &DownloadRunner,
        max_download_bytes: u64,
    ) -> Result<super::PrefetchResult, UpdateError> {
        let root = tempfile::tempdir().expect("root");
        prefetch_result_bounded(
            "test: source",
            RunPolicy::default(),
            runner,
            root.path(),
            "https://example.invalid/source.tar.gz",
            true,
            max_download_bytes,
            FetchLimits::default(),
            Duration::from_secs(1),
        )
    }

    fn tar_gz_file(path: &str, bytes: &[u8]) -> Vec<u8> {
        tar_gz_files(&[(path, bytes)])
    }

    fn tar_gz_files(entries: &[(&str, &[u8])]) -> Vec<u8> {
        let encoder = GzEncoder::new(Vec::new(), Compression::fast());
        let mut builder = tar::Builder::new(encoder);
        for (path, bytes) in entries {
            let mut header = tar::Header::new_gnu();
            header.set_size(bytes.len() as u64);
            header.set_mode(0o644);
            header.set_entry_type(tar::EntryType::Regular);
            header.set_cksum();
            builder
                .append_data(&mut header, path, *bytes)
                .expect("append file");
        }
        finish_tar_gz(builder)
    }

    fn tar_gz_escaping_symlink() -> Vec<u8> {
        let encoder = GzEncoder::new(Vec::new(), Compression::fast());
        let mut builder = tar::Builder::new(encoder);
        let mut header = tar::Header::new_gnu();
        header.set_size(0);
        header.set_mode(0o777);
        header.set_entry_type(tar::EntryType::Symlink);
        header
            .set_link_name("../../outside")
            .expect("set link target");
        header.set_cksum();
        builder
            .append_data(&mut header, "source/link", io::empty())
            .expect("append symlink");
        finish_tar_gz(builder)
    }

    fn tar_gz_absolute_file() -> Vec<u8> {
        let encoder = GzEncoder::new(Vec::new(), Compression::fast());
        let mut builder = tar::Builder::new(encoder);
        builder.preserve_absolute(true);
        let mut header = tar::Header::new_gnu();
        header.set_size(1);
        header.set_mode(0o644);
        header.set_entry_type(tar::EntryType::Regular);
        builder
            .append_data(&mut header, "/outside", b"x".as_slice())
            .expect("append absolute path");
        finish_tar_gz(builder)
    }

    fn tar_gz_fifo() -> Vec<u8> {
        let encoder = GzEncoder::new(Vec::new(), Compression::fast());
        let mut builder = tar::Builder::new(encoder);
        let mut header = tar::Header::new_gnu();
        header.set_size(0);
        header.set_mode(0o644);
        header.set_entry_type(tar::EntryType::Fifo);
        builder
            .append_data(&mut header, "source/pipe", io::empty())
            .expect("append FIFO");
        finish_tar_gz(builder)
    }

    fn tar_gz_hidden_longname_bomb(size: usize) -> Vec<u8> {
        let encoder = GzEncoder::new(Vec::new(), Compression::fast());
        let mut builder = tar::Builder::new(encoder);
        let payload = vec![b'a'; size];
        let mut extension = tar::Header::new_gnu();
        extension.set_size(payload.len() as u64);
        extension.set_mode(0o644);
        extension.set_entry_type(tar::EntryType::GNULongName);
        extension.set_cksum();
        builder
            .append(&extension, payload.as_slice())
            .expect("append GNU longname extension");

        let mut file = tar::Header::new_gnu();
        file.set_size(0);
        file.set_mode(0o644);
        file.set_entry_type(tar::EntryType::Regular);
        builder
            .append_data(&mut file, "source/file", io::empty())
            .expect("append file");
        finish_tar_gz(builder)
    }

    fn finish_tar_gz(builder: tar::Builder<GzEncoder<Vec<u8>>>) -> Vec<u8> {
        let encoder = builder.into_inner().expect("finish tar");
        encoder.finish().expect("finish gzip")
    }

    fn assert_upstream_drift(error: &UpdateError) {
        assert_eq!(error.fetch_kind(), Some(FetchFailureKind::UpstreamDrift));
    }
}
