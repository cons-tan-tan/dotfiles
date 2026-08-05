use std::fmt;
use std::path::Path;
use std::time::Duration;

use crate::codex_app;
use crate::command::{CommandRunner, SystemCommandRunner};
use crate::error::{FetchFailureKind, UpdateError};
use crate::fetch::{FetchLimits, download_bytes_with_limits};
use crate::policy::{RetryPolicy, RunPolicy};
use crate::prefetch::{PrefetchResult, prefetch_result_bounded};
use crate::shellfirm;
use crate::upstream::{
    github_latest_release_url, npm_latest_url, parse_latest_release_tag, parse_npm_latest_version,
    validate_release_version,
};
use crate::value_validation::validate_sri_hash;

const SHELLFIRM_REPOSITORY: &str = "kaplanelad/shellfirm";
const SHELLFIRM_SOURCE_MAX_BYTES: u64 = 16 * 1024 * 1024;
const SMOKE_PREFETCH_TIMEOUT: Duration = Duration::from_secs(60);
const SMOKE_FETCH_LIMITS: FetchLimits = FetchLimits::new(
    Duration::from_secs(10),
    Duration::from_secs(45),
    Duration::from_secs(50),
);
const SMOKE_GITHUB_FETCH_LIMITS: FetchLimits = SMOKE_FETCH_LIMITS.with_github_rate_limit_header();
const GITHUB_RELEASE_MAX_BYTES: usize = 4 * 1024 * 1024;
const NPM_LATEST_MAX_BYTES: usize = 1024 * 1024;
const APPCAST_MAX_BYTES: usize = 4 * 1024 * 1024;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum MetadataEndpoint {
    GithubLatestRelease,
    NpmLatest,
    CodexAppcast,
}

impl MetadataEndpoint {
    fn class(self) -> &'static str {
        match self {
            Self::GithubLatestRelease => "github-latest-release",
            Self::NpmLatest => "npm-latest",
            Self::CodexAppcast => "sparkle-appcast",
        }
    }
}

trait ReadOnlyClient {
    fn metadata(&self, endpoint: MetadataEndpoint) -> Result<Vec<u8>, UpdateError>;
    fn shellfirm_source(&self, tag: &str) -> Result<PrefetchResult, UpdateError>;
}

struct SystemReadOnlyClient<'a, R> {
    runner: &'a R,
    root: &'a Path,
}

impl<R: CommandRunner> ReadOnlyClient for SystemReadOnlyClient<'_, R> {
    fn metadata(&self, endpoint: MetadataEndpoint) -> Result<Vec<u8>, UpdateError> {
        let (target, operation, url, limit) = match endpoint {
            MetadataEndpoint::GithubLatestRelease => (
                "shellfirm",
                "GitHub latest release",
                github_latest_release_url(SHELLFIRM_REPOSITORY),
                GITHUB_RELEASE_MAX_BYTES,
            ),
            MetadataEndpoint::NpmLatest => (
                "difit",
                "npm latest metadata",
                npm_latest_url("difit"),
                NPM_LATEST_MAX_BYTES,
            ),
            MetadataEndpoint::CodexAppcast => (
                "codex-app",
                "appcast download",
                codex_app::APPCAST_URL.to_owned(),
                APPCAST_MAX_BYTES,
            ),
        };
        download_bytes_with_limits(
            smoke_policy().retry,
            self.runner,
            self.root,
            target,
            operation,
            &url,
            limit,
            if endpoint == MetadataEndpoint::GithubLatestRelease {
                SMOKE_GITHUB_FETCH_LIMITS
            } else {
                SMOKE_FETCH_LIMITS
            },
        )
    }

    fn shellfirm_source(&self, tag: &str) -> Result<PrefetchResult, UpdateError> {
        let url =
            format!("https://github.com/{SHELLFIRM_REPOSITORY}/archive/refs/tags/{tag}.tar.gz");
        prefetch_result_bounded(
            "shellfirm smoke: source",
            smoke_policy(),
            self.runner,
            self.root,
            &url,
            true,
            SHELLFIRM_SOURCE_MAX_BYTES,
            SMOKE_FETCH_LIMITS,
            SMOKE_PREFETCH_TIMEOUT,
        )
    }
}

fn smoke_policy() -> RunPolicy {
    RunPolicy {
        force: false,
        retry: RetryPolicy::new(2).expect("two attempts are within the retry policy bounds"),
        ..RunPolicy::default()
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum FailureClass {
    UpstreamDrift,
    TransientNetwork,
    RateLimit,
    Environment,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum OperationKind {
    Fetch,
    NixPrefetch,
    UpstreamContract,
}

impl fmt::Display for FailureClass {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(match self {
            Self::UpstreamDrift => "upstream-drift",
            Self::TransientNetwork => "transient-network",
            Self::RateLimit => "rate-limit",
            Self::Environment => "environment",
        })
    }
}

#[derive(Debug)]
pub struct SmokeFailure {
    class: FailureClass,
    target: &'static str,
    endpoint_class: &'static str,
    invariant: &'static str,
    source: Box<UpdateError>,
}

impl SmokeFailure {
    pub fn class(&self) -> FailureClass {
        self.class
    }
}

impl fmt::Display for SmokeFailure {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            formatter,
            "update-pins smoke [{}]: target={}, endpoint={}, invariant={}: {}",
            self.class, self.target, self.endpoint_class, self.invariant, self.source
        )
    }
}

#[derive(Debug, Eq, PartialEq)]
pub struct SmokeReport {
    pub github_release_version: String,
    pub npm_version: String,
    pub codex_app_version: String,
    pub shellfirm_version: String,
    pub shellfirm_hash: String,
    pub shellfirm_download_bytes: u64,
}

pub fn run() -> Result<SmokeReport, SmokeFailure> {
    let work = tempfile::tempdir().map_err(|source| SmokeFailure {
        class: FailureClass::Environment,
        target: "update-pins-smoke",
        endpoint_class: "local-temporary-directory",
        invariant: "an isolated working directory can be created",
        source: Box::new(UpdateError::io("<smoke temporary directory>", source)),
    })?;
    let runner = SystemCommandRunner;
    let client = SystemReadOnlyClient {
        runner: &runner,
        root: work.path(),
    };
    run_with_client(&client)
}

fn run_with_client(client: &impl ReadOnlyClient) -> Result<SmokeReport, SmokeFailure> {
    let github_response = client
        .metadata(MetadataEndpoint::GithubLatestRelease)
        .map_err(|error| {
            failure(
                OperationKind::Fetch,
                "shellfirm",
                MetadataEndpoint::GithubLatestRelease.class(),
                "the bounded metadata request succeeds",
                error,
            )
        })?;
    let shellfirm_tag =
        parse_latest_release_tag(&github_response, SHELLFIRM_REPOSITORY).map_err(|error| {
            failure(
                OperationKind::UpstreamContract,
                "shellfirm",
                MetadataEndpoint::GithubLatestRelease.class(),
                "tag_name is non-empty and matches the production parser",
                error,
            )
        })?;
    let shellfirm_version = shellfirm_tag
        .strip_prefix('v')
        .unwrap_or(&shellfirm_tag)
        .to_owned();
    validate_release_version("shellfirm smoke", &shellfirm_version).map_err(|error| {
        failure(
            OperationKind::UpstreamContract,
            "shellfirm",
            MetadataEndpoint::GithubLatestRelease.class(),
            "the latest tag contains a supported release version",
            error,
        )
    })?;

    let npm_response = client
        .metadata(MetadataEndpoint::NpmLatest)
        .map_err(|error| {
            failure(
                OperationKind::Fetch,
                "difit",
                MetadataEndpoint::NpmLatest.class(),
                "the bounded metadata request succeeds",
                error,
            )
        })?;
    let npm_version = parse_npm_latest_version(&npm_response, "difit").map_err(|error| {
        failure(
            OperationKind::UpstreamContract,
            "difit",
            MetadataEndpoint::NpmLatest.class(),
            "version is non-empty and matches the production parser",
            error,
        )
    })?;
    validate_release_version("difit smoke", &npm_version).map_err(|error| {
        failure(
            OperationKind::UpstreamContract,
            "difit",
            MetadataEndpoint::NpmLatest.class(),
            "the latest package contains a supported release version",
            error,
        )
    })?;

    let appcast_response = client
        .metadata(MetadataEndpoint::CodexAppcast)
        .map_err(|error| {
            failure(
                OperationKind::Fetch,
                "codex-app",
                MetadataEndpoint::CodexAppcast.class(),
                "the bounded metadata request succeeds",
                error,
            )
        })?;
    let appcast =
        codex_app::parse_appcast(&appcast_response, "<live appcast>").map_err(|error| {
            failure(
                OperationKind::UpstreamContract,
                "codex-app",
                MetadataEndpoint::CodexAppcast.class(),
                "one arm64 enclosure has a supported version and canonical HTTPS URL",
                error,
            )
        })?;

    let source = client.shellfirm_source(&shellfirm_tag).map_err(|error| {
        failure(
            OperationKind::NixPrefetch,
            "shellfirm",
            "source-archive-prefetch",
            "a bounded archive produces a valid SRI hash and unpacked storePath",
            error,
        )
    })?;
    if source.download_bytes > SHELLFIRM_SOURCE_MAX_BYTES {
        return Err(failure(
            OperationKind::UpstreamContract,
            "shellfirm",
            "source-archive-prefetch",
            "the representative archive stays within the weekly download budget",
            UpdateError::message(format!(
                "archive reported {} bytes, limit is {SHELLFIRM_SOURCE_MAX_BYTES}",
                source.download_bytes
            )),
        ));
    }
    validate_sri_hash("shellfirm smoke source", &source.hash).map_err(|error| {
        failure(
            OperationKind::NixPrefetch,
            "shellfirm",
            "source-archive-prefetch",
            "nix store prefetch-file returns a valid sha256 SRI hash",
            error,
        )
    })?;
    let store_path = source.store_path.as_deref().ok_or_else(|| {
        failure(
            OperationKind::NixPrefetch,
            "shellfirm",
            "source-archive-prefetch",
            "nix store prefetch-file returns an unpacked storePath",
            UpdateError::message("prefetch response omitted storePath"),
        )
    })?;
    shellfirm::read_lock_from_source("shellfirm smoke", store_path, &shellfirm_version).map_err(
        |error| {
            failure(
                OperationKind::UpstreamContract,
                "shellfirm",
                "source-archive-layout",
                "Cargo.toml and Cargo.lock identify the latest release without unsupported dependencies",
                error,
            )
        },
    )?;

    Ok(SmokeReport {
        github_release_version: shellfirm_version.clone(),
        npm_version,
        codex_app_version: appcast.version,
        shellfirm_version,
        shellfirm_hash: source.hash,
        shellfirm_download_bytes: source.download_bytes,
    })
}

fn failure(
    operation: OperationKind,
    target: &'static str,
    endpoint_class: &'static str,
    invariant: &'static str,
    source: UpdateError,
) -> SmokeFailure {
    SmokeFailure {
        class: classify_failure(operation, &source),
        target,
        endpoint_class,
        invariant,
        source: Box::new(source),
    }
}

fn classify_failure(operation: OperationKind, error: &UpdateError) -> FailureClass {
    if let Some(kind) = error.fetch_kind() {
        return match kind {
            FetchFailureKind::TransientNetwork => FailureClass::TransientNetwork,
            FetchFailureKind::RateLimit => FailureClass::RateLimit,
            FetchFailureKind::UpstreamDrift => FailureClass::UpstreamDrift,
            FetchFailureKind::Environment => FailureClass::Environment,
        };
    }
    match operation {
        OperationKind::UpstreamContract => FailureClass::UpstreamDrift,
        OperationKind::Fetch | OperationKind::NixPrefetch => FailureClass::Environment,
    }
}

#[cfg(test)]
mod tests {
    use std::cell::RefCell;
    use std::io::Write as _;
    use std::path::PathBuf;
    use std::time::Duration;

    use flate2::Compression;
    use flate2::write::GzEncoder;

    use super::{
        FailureClass, MetadataEndpoint, OperationKind, ReadOnlyClient, SystemReadOnlyClient,
        classify_failure, run_with_client,
    };
    use crate::command::{CommandOutput, CommandRunner, CommandSpec};
    use crate::error::{FetchFailureKind, UpdateError};
    use crate::prefetch::PrefetchResult;

    const HASH: &str = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";

    struct RecordedCommand {
        command: CommandSpec,
        stdout_limit: usize,
        stderr_limit: usize,
        timeout: Duration,
    }

    struct AdapterRunner {
        source: PathBuf,
        commands: RefCell<Vec<RecordedCommand>>,
    }

    impl CommandRunner for AdapterRunner {
        fn run(&self, command: &CommandSpec) -> Result<CommandOutput, UpdateError> {
            Err(UpdateError::message(format!(
                "unexpected unbounded command {}",
                command.display()
            )))
        }

        fn run_limited_with_timeout(
            &self,
            command: &CommandSpec,
            stdout_limit: usize,
            stderr_limit: usize,
            timeout: Duration,
        ) -> Result<CommandOutput, UpdateError> {
            self.commands.borrow_mut().push(RecordedCommand {
                command: command.clone(),
                stdout_limit,
                stderr_limit,
                timeout,
            });
            match command.program.to_string_lossy().as_ref() {
                "curl" => {
                    let output_index = command
                        .args
                        .iter()
                        .position(|argument| argument == "--output")
                        .expect("curl output argument");
                    let output_path = PathBuf::from(&command.args[output_index + 1]);
                    let url = command.args.last().expect("curl URL").to_string_lossy();
                    let body = match url.as_ref() {
                        "https://api.github.com/repos/kaplanelad/shellfirm/releases/latest" => {
                            br#"{"tag_name":"v9.9.9"}"#.to_vec()
                        }
                        "https://registry.npmjs.org/difit/latest" => {
                            br#"{"version":"8.8.8"}"#.to_vec()
                        }
                        "https://persistent.oaistatic.com/codex-app-prod/appcast.xml" => {
                            include_bytes!("fixtures/codex-app-appcast.xml").to_vec()
                        }
                        "https://github.com/kaplanelad/shellfirm/archive/refs/tags/v9.9.9.tar.gz" => {
                            representative_shellfirm_archive()
                        }
                        _ => {
                            return Err(UpdateError::message(format!(
                                "unexpected smoke URL {url}"
                            )));
                        }
                    };
                    std::fs::write(&output_path, &body)
                        .map_err(|source| UpdateError::io(&output_path, source))?;
                    Ok(CommandOutput {
                        status: Some(0),
                        stdout: b"200".to_vec(),
                        stderr: Vec::new(),
                    })
                }
                "nix" => Ok(CommandOutput {
                    status: Some(0),
                    stdout: serde_json::json!({
                        "hash": HASH,
                        "storePath": self.source,
                    })
                    .to_string()
                    .into_bytes(),
                    stderr: Vec::new(),
                }),
                program => Err(UpdateError::message(format!(
                    "smoke attempted forbidden command {program}"
                ))),
            }
        }

        fn is_available(&self, _program: &std::path::Path) -> bool {
            false
        }
    }

    struct FakeReadOnlyClient {
        source: PathBuf,
        operations: RefCell<Vec<String>>,
    }

    impl ReadOnlyClient for FakeReadOnlyClient {
        fn metadata(&self, endpoint: MetadataEndpoint) -> Result<Vec<u8>, UpdateError> {
            self.operations
                .borrow_mut()
                .push(endpoint.class().to_owned());
            Ok(match endpoint {
                MetadataEndpoint::GithubLatestRelease => br#"{"tag_name":"v9.9.9"}"#.to_vec(),
                MetadataEndpoint::NpmLatest => br#"{"version":"8.8.8"}"#.to_vec(),
                MetadataEndpoint::CodexAppcast => {
                    include_bytes!("fixtures/codex-app-appcast.xml").to_vec()
                }
            })
        }

        fn shellfirm_source(&self, tag: &str) -> Result<PrefetchResult, UpdateError> {
            self.operations
                .borrow_mut()
                .push(format!("shellfirm-source:{tag}"));
            Ok(PrefetchResult {
                hash: HASH.to_owned(),
                store_path: Some(self.source.clone()),
                download_bytes: 822_779,
            })
        }
    }

    #[test]
    fn smoke_uses_only_the_typed_read_only_contract() {
        let source = shellfirm_source();
        let client = FakeReadOnlyClient {
            source: source.path().to_owned(),
            operations: RefCell::new(Vec::new()),
        };

        let report = run_with_client(&client).expect("smoke succeeds");

        assert_eq!(report.github_release_version, "9.9.9");
        assert_eq!(report.npm_version, "8.8.8");
        assert_eq!(report.codex_app_version, "9.9.9");
        assert_eq!(report.shellfirm_version, "9.9.9");
        assert_eq!(report.shellfirm_hash, HASH);
        assert_eq!(
            client.operations.into_inner(),
            [
                "github-latest-release",
                "npm-latest",
                "sparkle-appcast",
                "shellfirm-source:v9.9.9",
            ]
        );
    }

    #[test]
    fn system_adapter_enforces_exact_urls_argv_and_resource_limits() {
        let work = tempfile::tempdir().expect("work directory");
        let source = shellfirm_source();
        let runner = AdapterRunner {
            source: source.path().to_owned(),
            commands: RefCell::new(Vec::new()),
        };
        let client = SystemReadOnlyClient {
            runner: &runner,
            root: work.path(),
        };

        run_with_client(&client).expect("adapter-backed smoke succeeds");

        let commands = runner.commands.into_inner();
        assert_eq!(commands.len(), 5);
        let expected_urls = [
            "https://api.github.com/repos/kaplanelad/shellfirm/releases/latest",
            "https://registry.npmjs.org/difit/latest",
            "https://persistent.oaistatic.com/codex-app-prod/appcast.xml",
            "https://github.com/kaplanelad/shellfirm/archive/refs/tags/v9.9.9.tar.gz",
        ];
        let expected_max_bytes = ["4194304", "1048576", "4194304", "16777216"];
        for (index, ((recorded, expected_url), expected_max_bytes)) in commands[..4]
            .iter()
            .zip(expected_urls)
            .zip(expected_max_bytes)
            .enumerate()
        {
            assert_eq!(recorded.command.program, "curl");
            assert_eq!(recorded.command.cwd.as_deref(), Some(work.path()));
            assert_eq!(recorded.command.args.last().unwrap(), expected_url);
            assert_eq!(recorded.stdout_limit, 64);
            assert_eq!(recorded.stderr_limit, 64 * 1024);
            assert_eq!(recorded.timeout, Duration::from_secs(50));
            assert_option_value(&recorded.command, "--connect-timeout", "10");
            assert_option_value(&recorded.command, "--max-time", "45");
            assert_option_value(&recorded.command, "--max-filesize", expected_max_bytes);
            assert_option_value(
                &recorded.command,
                "--write-out",
                if index == 0 {
                    "%{http_code}\n%header{x-ratelimit-remaining}"
                } else {
                    "%{http_code}"
                },
            );
        }

        let prefetch = &commands[4];
        assert_eq!(prefetch.command.program, "nix");
        assert_eq!(prefetch.command.cwd.as_deref(), Some(work.path()));
        assert_eq!(prefetch.stdout_limit, 64 * 1024);
        assert_eq!(prefetch.stderr_limit, 64 * 1024);
        assert_eq!(prefetch.timeout, Duration::from_secs(60));
        assert_eq!(
            &prefetch.command.args[..6],
            [
                "store",
                "prefetch-file",
                "--json",
                "--name",
                "update-pins-v9.9.9.tar.gz",
                "--unpack",
            ]
        );
        assert!(
            prefetch.command.args[6]
                .to_string_lossy()
                .starts_with("file:///")
        );
    }

    #[test]
    fn parser_drift_is_classified_without_rendering_response_bodies() {
        struct MalformedGithub;

        impl ReadOnlyClient for MalformedGithub {
            fn metadata(&self, endpoint: MetadataEndpoint) -> Result<Vec<u8>, UpdateError> {
                Ok(match endpoint {
                    MetadataEndpoint::GithubLatestRelease => {
                        br#"{"private":"do-not-render"}"#.to_vec()
                    }
                    MetadataEndpoint::NpmLatest => br#"{"version":"8.8.8"}"#.to_vec(),
                    MetadataEndpoint::CodexAppcast => {
                        include_bytes!("fixtures/codex-app-appcast.xml").to_vec()
                    }
                })
            }

            fn shellfirm_source(&self, _tag: &str) -> Result<PrefetchResult, UpdateError> {
                unreachable!("GitHub parser fails first")
            }
        }

        let failure = run_with_client(&MalformedGithub).expect_err("missing tag");
        assert_eq!(failure.class(), FailureClass::UpstreamDrift);
        assert!(!failure.to_string().contains("do-not-render"));
    }

    #[test]
    fn nix_prefetch_timeout_is_an_environment_failure() {
        struct TimedOutPrefetch;

        impl ReadOnlyClient for TimedOutPrefetch {
            fn metadata(&self, endpoint: MetadataEndpoint) -> Result<Vec<u8>, UpdateError> {
                Ok(match endpoint {
                    MetadataEndpoint::GithubLatestRelease => br#"{"tag_name":"v9.9.9"}"#.to_vec(),
                    MetadataEndpoint::NpmLatest => br#"{"version":"8.8.8"}"#.to_vec(),
                    MetadataEndpoint::CodexAppcast => {
                        include_bytes!("fixtures/codex-app-appcast.xml").to_vec()
                    }
                })
            }

            fn shellfirm_source(&self, _tag: &str) -> Result<PrefetchResult, UpdateError> {
                Err(UpdateError::CommandTimedOut {
                    program: "nix".to_owned(),
                    seconds: 60,
                })
            }
        }

        let failure = run_with_client(&TimedOutPrefetch).expect_err("prefetch times out");
        assert_eq!(failure.class(), FailureClass::Environment);
        assert_eq!(failure.endpoint_class, "source-archive-prefetch");
    }

    #[test]
    fn diagnostics_use_typed_fetch_and_operation_kinds() {
        for (kind, expected) in [
            (
                FetchFailureKind::TransientNetwork,
                FailureClass::TransientNetwork,
            ),
            (FetchFailureKind::RateLimit, FailureClass::RateLimit),
            (FetchFailureKind::UpstreamDrift, FailureClass::UpstreamDrift),
            (FetchFailureKind::Environment, FailureClass::Environment),
        ] {
            let error = UpdateError::fetch("target", "operation", kind, "opaque detail");
            assert_eq!(classify_failure(OperationKind::Fetch, &error), expected);
        }

        assert_eq!(
            classify_failure(
                OperationKind::NixPrefetch,
                &UpdateError::CommandTimedOut {
                    program: "nix".to_owned(),
                    seconds: 60,
                },
            ),
            FailureClass::Environment
        );
        assert_eq!(
            classify_failure(
                OperationKind::UpstreamContract,
                &UpdateError::message("HTTP 429 and timed out are only untyped words"),
            ),
            FailureClass::UpstreamDrift
        );
    }

    fn shellfirm_source() -> tempfile::TempDir {
        let source = tempfile::tempdir().expect("source");
        std::fs::write(
            source.path().join("Cargo.toml"),
            "[package]\nname = \"shellfirm\"\nversion = \"9.9.9\"\n",
        )
        .expect("manifest");
        std::fs::write(
            source.path().join("Cargo.lock"),
            "version = 4\n\n[[package]]\nname = \"shellfirm\"\nversion = \"9.9.9\"\n",
        )
        .expect("lockfile");
        source
    }

    fn representative_shellfirm_archive() -> Vec<u8> {
        let encoder = GzEncoder::new(Vec::new(), Compression::default());
        let mut archive = tar::Builder::new(encoder);
        append_archive_file(
            &mut archive,
            "shellfirm-9.9.9/Cargo.toml",
            b"[package]\nname = \"shellfirm\"\nversion = \"9.9.9\"\n",
        );
        append_archive_file(
            &mut archive,
            "shellfirm-9.9.9/Cargo.lock",
            b"version = 4\n\n[[package]]\nname = \"shellfirm\"\nversion = \"9.9.9\"\n",
        );
        let encoder = archive.into_inner().expect("finish tar archive");
        encoder.finish().expect("finish gzip stream")
    }

    fn append_archive_file(
        archive: &mut tar::Builder<GzEncoder<Vec<u8>>>,
        path: &str,
        bytes: &[u8],
    ) {
        let mut header = tar::Header::new_gnu();
        header.set_mode(0o644);
        header.set_size(bytes.len() as u64);
        header.set_cksum();
        archive
            .append_data(&mut header, path, bytes)
            .expect("append tar entry");
        archive.get_mut().flush().expect("flush gzip stream");
    }

    fn assert_option_value(command: &CommandSpec, option: &str, expected: &str) {
        let index = command
            .args
            .iter()
            .position(|argument| argument == option)
            .expect("expected curl option");
        assert_eq!(command.args[index + 1], expected);
    }
}
