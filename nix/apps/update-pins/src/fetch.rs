use std::io::Read as _;
use std::path::Path;
use std::time::Duration;

use tempfile::{Builder, NamedTempFile};

use crate::command::{CommandOutput, CommandRunner, CommandSpec};
use crate::error::{FetchFailureKind, UpdateError};
use crate::policy::RetryPolicy;

const FETCH_STDOUT_LIMIT: usize = 64;
const FETCH_STDERR_LIMIT: usize = 64 * 1024;
const DEFAULT_CONNECT_TIMEOUT: Duration = Duration::from_secs(15);
const DEFAULT_TRANSFER_TIMEOUT: Duration = Duration::from_secs(110);
const DEFAULT_PROCESS_TIMEOUT: Duration = Duration::from_secs(120);

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) struct FetchLimits {
    connect_timeout: Duration,
    transfer_timeout: Duration,
    process_timeout: Duration,
    github_rate_limit_header: bool,
}

impl Default for FetchLimits {
    fn default() -> Self {
        Self {
            connect_timeout: DEFAULT_CONNECT_TIMEOUT,
            transfer_timeout: DEFAULT_TRANSFER_TIMEOUT,
            process_timeout: DEFAULT_PROCESS_TIMEOUT,
            github_rate_limit_header: false,
        }
    }
}

impl FetchLimits {
    pub(crate) const fn new(
        connect_timeout: Duration,
        transfer_timeout: Duration,
        process_timeout: Duration,
    ) -> Self {
        Self {
            connect_timeout,
            transfer_timeout,
            process_timeout,
            github_rate_limit_header: false,
        }
    }

    pub(crate) const fn with_github_rate_limit_header(mut self) -> Self {
        self.github_rate_limit_header = true;
        self
    }
}

pub trait Sleeper {
    fn sleep(&self, duration: Duration);
}

#[derive(Clone, Copy, Debug, Default)]
pub struct ThreadSleeper;

impl Sleeper for ThreadSleeper {
    fn sleep(&self, duration: Duration) {
        std::thread::sleep(duration);
    }
}

#[derive(Debug)]
pub enum RetryableError {
    Transient(UpdateError),
    Permanent(UpdateError),
}

impl RetryableError {
    fn into_error(self) -> UpdateError {
        match self {
            Self::Transient(error) | Self::Permanent(error) => error,
        }
    }

    fn is_transient(&self) -> bool {
        matches!(self, Self::Transient(_))
    }
}

pub fn retry_fetch<T, S, F>(
    policy: RetryPolicy,
    sleeper: &S,
    target: &str,
    operation: &str,
    mut attempt: F,
) -> Result<T, UpdateError>
where
    S: Sleeper,
    F: FnMut() -> Result<T, RetryableError>,
{
    for attempt_number in 1..=policy.max_attempts() {
        match attempt() {
            Ok(value) => return Ok(value),
            Err(failure) if failure.is_transient() && attempt_number < policy.max_attempts() => {
                let next_attempt = attempt_number + 1;
                eprintln!(
                    "{target}: {operation}: retrying attempt {next_attempt}/{}",
                    policy.max_attempts()
                );
                sleeper.sleep(policy.backoff_after(attempt_number));
            }
            Err(failure) => return Err(failure.into_error()),
        }
    }
    unreachable!("a retry policy always allows at least one attempt")
}

pub struct DownloadedFile {
    file: NamedTempFile,
}

impl DownloadedFile {
    pub fn path(&self) -> &Path {
        self.file.path()
    }
}

struct DownloadRequest<'a> {
    root: &'a Path,
    target: &'a str,
    operation: &'a str,
    url: &'a str,
    max_bytes: u64,
    limits: FetchLimits,
}

#[allow(clippy::too_many_arguments)]
pub(crate) fn download_bounded_with_limits<R: CommandRunner>(
    policy: RetryPolicy,
    runner: &R,
    root: &Path,
    target: &str,
    operation: &str,
    url: &str,
    max_bytes: u64,
    limits: FetchLimits,
) -> Result<DownloadedFile, UpdateError> {
    download_with_sleeper(
        policy,
        runner,
        &ThreadSleeper,
        DownloadRequest {
            root,
            target,
            operation,
            url,
            max_bytes,
            limits,
        },
    )
}

fn download_with_sleeper<R: CommandRunner, S: Sleeper>(
    policy: RetryPolicy,
    runner: &R,
    sleeper: &S,
    request: DownloadRequest<'_>,
) -> Result<DownloadedFile, UpdateError> {
    let DownloadRequest {
        root,
        target,
        operation,
        url,
        max_bytes,
        limits,
    } = request;
    retry_fetch(policy, sleeper, target, operation, || {
        let suffix = safe_download_suffix(url);
        let temporary = Builder::new()
            .prefix("update-pins-fetch-")
            .suffix(suffix)
            .tempfile()
            .map_err(|source| {
                RetryableError::Permanent(UpdateError::io("<fetch temporary file>", source))
            })?;
        let command =
            curl_download_command(url, temporary.path(), max_bytes, limits).current_dir(root);
        let output = runner
            .run_limited_with_timeout(
                &command,
                FETCH_STDOUT_LIMIT,
                FETCH_STDERR_LIMIT,
                limits.process_timeout,
            )
            .map_err(|error| classify_runner_error(target, operation, error))?;
        classify_curl_output(target, operation, &output, limits.github_rate_limit_header)?;
        Ok(DownloadedFile { file: temporary })
    })
}

pub fn download_bytes<R: CommandRunner>(
    policy: RetryPolicy,
    runner: &R,
    root: &Path,
    target: &str,
    operation: &str,
    url: &str,
    limit: usize,
) -> Result<Vec<u8>, UpdateError> {
    download_bytes_with_limits(
        policy,
        runner,
        root,
        target,
        operation,
        url,
        limit,
        FetchLimits::default(),
    )
}

#[allow(clippy::too_many_arguments)]
pub(crate) fn download_bytes_with_limits<R: CommandRunner>(
    policy: RetryPolicy,
    runner: &R,
    root: &Path,
    target: &str,
    operation: &str,
    url: &str,
    limit: usize,
    limits: FetchLimits,
) -> Result<Vec<u8>, UpdateError> {
    let downloaded = download_with_sleeper(
        policy,
        runner,
        &ThreadSleeper,
        DownloadRequest {
            root,
            target,
            operation,
            url,
            max_bytes: limit as u64,
            limits,
        },
    )?;
    let file = std::fs::File::open(downloaded.path())
        .map_err(|source| UpdateError::io(downloaded.path(), source))?;
    let mut bytes = Vec::new();
    file.take(limit.saturating_add(1) as u64)
        .read_to_end(&mut bytes)
        .map_err(|source| UpdateError::io(downloaded.path(), source))?;
    if bytes.len() > limit {
        return Err(UpdateError::fetch(
            target,
            operation,
            FetchFailureKind::UpstreamDrift,
            format!("response exceeded {limit} bytes"),
        ));
    }
    Ok(bytes)
}

pub fn gh_api_bytes<R: CommandRunner>(
    policy: RetryPolicy,
    runner: &R,
    root: &Path,
    target: &str,
    operation: &str,
    endpoint: &str,
    limit: usize,
) -> Result<Vec<u8>, UpdateError> {
    retry_fetch(policy, &ThreadSleeper, target, operation, || {
        let command = CommandSpec::new("gh")
            .args(["api", "--include", endpoint])
            .current_dir(root);
        let output = runner
            .run_limited(&command, limit, FETCH_STDERR_LIMIT)
            .map_err(|error| classify_runner_error(target, operation, error))?;
        classify_gh_output(target, operation, output)
    })
}

fn curl_download_command(
    url: &str,
    output: &Path,
    max_bytes: u64,
    limits: FetchLimits,
) -> CommandSpec {
    let max_bytes = max_bytes.to_string();
    let connect_timeout = limits.connect_timeout.as_secs().to_string();
    let transfer_timeout = limits.transfer_timeout.as_secs().to_string();
    let write_out = if limits.github_rate_limit_header {
        "%{http_code}\n%header{x-ratelimit-remaining}"
    } else {
        "%{http_code}"
    };
    CommandSpec::new("curl")
        .args([
            "-sS",
            "--location",
            "--proto",
            "=https",
            "--proto-redir",
            "=https",
            "--connect-timeout",
            &connect_timeout,
            "--max-time",
            &transfer_timeout,
            "--max-filesize",
            &max_bytes,
            "--output",
        ])
        .arg(output.as_os_str())
        .args(["--write-out", write_out, url])
}

fn classify_runner_error(target: &str, operation: &str, error: UpdateError) -> RetryableError {
    let transient = matches!(
        &error,
        UpdateError::Spawn { source, .. }
            if matches!(
                source.kind(),
                std::io::ErrorKind::Interrupted
                    | std::io::ErrorKind::WouldBlock
                    | std::io::ErrorKind::TimedOut
            )
    ) || matches!(&error, UpdateError::CommandTimedOut { .. });
    let kind = if transient {
        FetchFailureKind::TransientNetwork
    } else {
        FetchFailureKind::Environment
    };
    let detail = match &error {
        UpdateError::Spawn { .. } | UpdateError::CommandTimedOut { .. } => error.to_string(),
        _ => "fetch process failed".to_owned(),
    };
    let error = UpdateError::fetch(target, operation, kind, detail);
    if transient {
        RetryableError::Transient(error)
    } else {
        RetryableError::Permanent(error)
    }
}

fn classify_curl_output(
    target: &str,
    operation: &str,
    output: &CommandOutput,
    github_rate_limit_header: bool,
) -> Result<(), RetryableError> {
    if !output.success() {
        let status = output.status;
        let kind = match status {
            Some(status) if is_transient_curl_exit(status) => FetchFailureKind::TransientNetwork,
            Some(63) => FetchFailureKind::UpstreamDrift,
            _ => FetchFailureKind::Environment,
        };
        let error = UpdateError::fetch(
            target,
            operation,
            kind,
            format!(
                "curl failed with status {}",
                status.map_or_else(|| "signal".to_owned(), |code| code.to_string())
            ),
        );
        return if kind == FetchFailureKind::TransientNetwork {
            Err(RetryableError::Transient(error))
        } else {
            Err(RetryableError::Permanent(error))
        };
    }

    let metadata =
        parse_curl_metadata(&output.stdout, github_rate_limit_header).ok_or_else(|| {
            RetryableError::Permanent(UpdateError::fetch(
                target,
                operation,
                FetchFailureKind::Environment,
                "curl returned invalid bounded response metadata",
            ))
        })?;
    if (200..=299).contains(&metadata.status) {
        return Ok(());
    }
    Err(classify_http_status(
        target,
        operation,
        metadata.status,
        github_rate_limit_header,
        metadata.rate_limit_remaining,
    ))
}

fn classify_gh_output(
    target: &str,
    operation: &str,
    output: CommandOutput,
) -> Result<Vec<u8>, RetryableError> {
    let parsed = parse_gh_response(&output.stdout);
    if output.success() {
        let response = parsed.ok_or_else(|| {
            RetryableError::Permanent(UpdateError::fetch(
                target,
                operation,
                FetchFailureKind::Environment,
                "gh returned an invalid bounded HTTP response",
            ))
        })?;
        if (200..=299).contains(&response.status) {
            return Ok(response.body.to_vec());
        }
        return Err(classify_http_status(
            target,
            operation,
            response.status,
            true,
            response.rate_limit_remaining,
        ));
    }

    if output.status == Some(4) {
        return Err(RetryableError::Permanent(UpdateError::fetch(
            target,
            operation,
            FetchFailureKind::Environment,
            "gh authentication failed",
        )));
    }
    if let Some(response) = parsed {
        return Err(classify_http_status(
            target,
            operation,
            response.status,
            true,
            response.rate_limit_remaining,
        ));
    }
    Err(RetryableError::Permanent(UpdateError::fetch(
        target,
        operation,
        FetchFailureKind::Environment,
        format!(
            "gh failed with status {}",
            output
                .status
                .map_or_else(|| "signal".to_owned(), |code| code.to_string())
        ),
    )))
}

fn classify_http_status(
    target: &str,
    operation: &str,
    status: u16,
    github: bool,
    rate_limit_remaining: Option<u64>,
) -> RetryableError {
    let kind = if status == 429 || (github && status == 403 && rate_limit_remaining == Some(0)) {
        FetchFailureKind::RateLimit
    } else if status == 408 || status >= 500 {
        FetchFailureKind::TransientNetwork
    } else {
        FetchFailureKind::UpstreamDrift
    };
    let error = UpdateError::fetch(target, operation, kind, format!("HTTP {status}"));
    if status == 408 || status == 429 || status >= 500 {
        RetryableError::Transient(error)
    } else {
        RetryableError::Permanent(error)
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
struct CurlMetadata {
    status: u16,
    rate_limit_remaining: Option<u64>,
}

fn parse_curl_metadata(bytes: &[u8], github_rate_limit_header: bool) -> Option<CurlMetadata> {
    let text = std::str::from_utf8(bytes).ok()?;
    let mut lines = text.lines();
    let status = lines
        .next()?
        .trim()
        .parse::<u16>()
        .ok()
        .filter(|status| (100..=599).contains(status))?;
    let rate_limit_remaining = if github_rate_limit_header {
        lines
            .next()
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .and_then(|value| value.parse::<u64>().ok())
    } else {
        None
    };
    if lines.any(|line| !line.trim().is_empty()) {
        return None;
    }
    Some(CurlMetadata {
        status,
        rate_limit_remaining,
    })
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
struct GhResponse<'a> {
    status: u16,
    rate_limit_remaining: Option<u64>,
    body: &'a [u8],
}

fn parse_gh_response(bytes: &[u8]) -> Option<GhResponse<'_>> {
    let separator = bytes
        .windows(4)
        .position(|window| window == b"\r\n\r\n")
        .map(|index| (index, 4))
        .or_else(|| {
            bytes
                .windows(2)
                .position(|window| window == b"\n\n")
                .map(|index| (index, 2))
        })?;
    let headers = &bytes[..separator.0];
    let first_line_end = headers
        .iter()
        .position(|byte| *byte == b'\n')
        .unwrap_or(headers.len());
    let first_line = std::str::from_utf8(&headers[..first_line_end])
        .ok()?
        .trim_end_matches('\r');
    let mut fields = first_line.split_ascii_whitespace();
    let protocol = fields.next()?;
    let status = fields.next()?.parse::<u16>().ok()?;
    if !protocol.starts_with("HTTP/") || !(100..=599).contains(&status) {
        return None;
    }
    Some(GhResponse {
        status,
        rate_limit_remaining: parse_rate_limit_remaining(headers),
        body: &bytes[separator.0 + separator.1..],
    })
}

fn parse_rate_limit_remaining(headers: &[u8]) -> Option<u64> {
    let headers = std::str::from_utf8(headers).ok()?;
    let mut values = headers.lines().skip(1).filter_map(|line| {
        let (name, value) = line.trim_end_matches('\r').split_once(':')?;
        name.eq_ignore_ascii_case("x-ratelimit-remaining")
            .then(|| value.trim())
    });
    let value = values.next()?;
    if values.next().is_some() {
        return None;
    }
    value.parse().ok()
}

fn is_transient_curl_exit(status: i32) -> bool {
    matches!(status, 5 | 6 | 7 | 18 | 28 | 35 | 52 | 55 | 56 | 92)
}

fn safe_download_suffix(url: &str) -> &'static str {
    let path = url.split(['?', '#']).next().unwrap_or(url);
    for suffix in [".tar.gz", ".tar.xz", ".tgz", ".zip", ".json", ".xml"] {
        if path.ends_with(suffix) {
            return suffix;
        }
    }
    ".download"
}

#[cfg(test)]
mod tests {
    use std::cell::{Cell, RefCell};
    use std::path::{Path, PathBuf};
    use std::time::Duration;

    use super::{
        CurlMetadata, GhResponse, RetryableError, Sleeper, classify_curl_output,
        classify_gh_output, classify_runner_error, download_with_sleeper, parse_curl_metadata,
        parse_gh_response, retry_fetch,
    };
    use crate::command::{CommandOutput, CommandRunner, CommandSpec};
    use crate::error::{FetchFailureKind, UpdateError};
    use crate::policy::RetryPolicy;

    #[derive(Default)]
    struct RecordingSleeper {
        durations: RefCell<Vec<Duration>>,
    }

    impl Sleeper for RecordingSleeper {
        fn sleep(&self, duration: Duration) {
            self.durations.borrow_mut().push(duration);
        }
    }

    struct CurlRunner {
        outcomes: RefCell<Vec<CommandOutput>>,
        paths: RefCell<Vec<PathBuf>>,
    }

    impl CommandRunner for CurlRunner {
        fn run(&self, command: &CommandSpec) -> Result<CommandOutput, UpdateError> {
            let output_index = command
                .args
                .iter()
                .position(|argument| argument == "--output")
                .expect("curl output argument");
            let path = PathBuf::from(&command.args[output_index + 1]);
            self.paths.borrow_mut().push(path.clone());
            std::fs::write(&path, b"fresh response")
                .map_err(|source| UpdateError::io(&path, source))?;
            Ok(self.outcomes.borrow_mut().remove(0))
        }

        fn is_available(&self, _program: &Path) -> bool {
            true
        }
    }

    fn output(status: i32, http_status: &str) -> CommandOutput {
        CommandOutput {
            status: Some(status),
            stdout: http_status.as_bytes().to_vec(),
            stderr: Vec::new(),
        }
    }

    #[test]
    fn transient_failures_back_off_and_use_fresh_files() {
        let runner = CurlRunner {
            outcomes: RefCell::new(vec![output(7, "000"), output(28, "000"), output(0, "200")]),
            paths: RefCell::new(Vec::new()),
        };
        let sleeper = RecordingSleeper::default();
        let downloaded = download_with_sleeper(
            RetryPolicy::default(),
            &runner,
            &sleeper,
            super::DownloadRequest {
                root: Path::new("/repo"),
                target: "demo",
                operation: "asset download",
                url: "https://example.com/archive.tar.gz",
                max_bytes: 2 * 1024 * 1024 * 1024,
                limits: super::FetchLimits::default(),
            },
        )
        .expect("third attempt succeeds");

        assert_eq!(std::fs::read(downloaded.path()).unwrap(), b"fresh response");
        let paths = runner.paths.into_inner();
        assert_eq!(paths.len(), 3);
        assert_ne!(paths[0], paths[1]);
        assert_ne!(paths[1], paths[2]);
        assert_eq!(
            sleeper.durations.into_inner(),
            [Duration::from_millis(250), Duration::from_millis(500)]
        );
    }

    #[test]
    fn permanent_http_failure_does_not_retry() {
        let attempts = Cell::new(0);
        let sleeper = RecordingSleeper::default();
        let result = retry_fetch(RetryPolicy::default(), &sleeper, "demo", "metadata", || {
            attempts.set(attempts.get() + 1);
            classify_curl_output("demo", "metadata", &output(0, "404"), false)
        });
        assert!(result.is_err());
        assert_eq!(attempts.get(), 1);
        assert!(sleeper.durations.borrow().is_empty());
    }

    #[test]
    fn transient_http_failure_stops_at_the_bound() {
        let attempts = Cell::new(0);
        let sleeper = RecordingSleeper::default();
        let result = retry_fetch(RetryPolicy::default(), &sleeper, "demo", "metadata", || {
            attempts.set(attempts.get() + 1);
            classify_curl_output("demo", "metadata", &output(0, "503"), false)
        });
        assert!(result.is_err());
        assert_eq!(attempts.get(), 3);
        assert_eq!(sleeper.durations.borrow().len(), 2);
    }

    #[test]
    fn transient_spawn_failures_are_retried_without_real_sleep() {
        let attempts = Cell::new(0);
        let sleeper = RecordingSleeper::default();
        let result = retry_fetch(RetryPolicy::default(), &sleeper, "demo", "metadata", || {
            attempts.set(attempts.get() + 1);
            if attempts.get() < 3 {
                Err(classify_runner_error(
                    "demo",
                    "metadata",
                    UpdateError::Spawn {
                        program: "curl".to_owned(),
                        source: std::io::Error::from(std::io::ErrorKind::Interrupted),
                    },
                ))
            } else {
                Ok("done")
            }
        });
        assert_eq!(result.expect("third spawn succeeds"), "done");
        assert_eq!(attempts.get(), 3);
        assert_eq!(sleeper.durations.borrow().len(), 2);
    }

    #[test]
    fn command_timeouts_are_retryable() {
        let attempts = Cell::new(0);
        let sleeper = RecordingSleeper::default();
        let result = retry_fetch(RetryPolicy::default(), &sleeper, "demo", "metadata", || {
            attempts.set(attempts.get() + 1);
            if attempts.get() == 1 {
                Err(classify_runner_error(
                    "demo",
                    "metadata",
                    UpdateError::CommandTimedOut {
                        program: "gh".to_owned(),
                        seconds: 120,
                    },
                ))
            } else {
                Ok("done")
            }
        });
        assert_eq!(result.expect("second attempt succeeds"), "done");
        assert_eq!(attempts.get(), 2);
        assert_eq!(
            sleeper.durations.borrow().as_slice(),
            [Duration::from_millis(250)]
        );
    }

    #[test]
    fn gh_transient_statuses_retry_but_authentication_does_not() {
        let attempts = Cell::new(0);
        let sleeper = RecordingSleeper::default();
        let result = retry_fetch(
            RetryPolicy::default(),
            &sleeper,
            "demo",
            "GitHub latest release",
            || {
                attempts.set(attempts.get() + 1);
                let status = if attempts.get() < 3 { 503 } else { 200 };
                classify_gh_output(
                    "demo",
                    "GitHub latest release",
                    CommandOutput {
                        status: Some(if status == 200 { 0 } else { 1 }),
                        stdout: format!("HTTP/2.0 {status} status\r\n\r\n{{}}").into_bytes(),
                        stderr: Vec::new(),
                    },
                )
            },
        );
        assert_eq!(result.expect("third GitHub attempt succeeds"), b"{}");
        assert_eq!(attempts.get(), 3);

        let authentication = classify_gh_output(
            "demo",
            "GitHub latest release",
            CommandOutput {
                status: Some(4),
                stdout: Vec::new(),
                stderr: Vec::new(),
            },
        );
        assert!(matches!(
            authentication,
            Err(super::RetryableError::Permanent(_))
        ));
        let unclassified = classify_gh_output(
            "demo",
            "GitHub latest release",
            CommandOutput {
                status: Some(1),
                stdout: Vec::new(),
                stderr: b"unstructured diagnostic".to_vec(),
            },
        );
        assert!(matches!(
            unclassified,
            Err(super::RetryableError::Permanent(_))
        ));
    }

    #[test]
    fn gh_response_parser_separates_status_headers_and_body() {
        assert_eq!(
            parse_gh_response(
                b"HTTP/2.0 200 OK\r\ncontent-type: application/json\r\nx-ratelimit-remaining: 0\r\n\r\n{\"tag_name\":\"v1\"}"
            ),
            Some(GhResponse {
                status: 200,
                rate_limit_remaining: Some(0),
                body: b"{\"tag_name\":\"v1\"}",
            })
        );
        assert_eq!(parse_gh_response(b"{\"tag_name\":\"v1\"}"), None);
    }

    #[test]
    fn curl_exit_codes_have_exact_typed_classification() {
        let tls = classify_curl_output("demo", "metadata", &output(35, "000"), false);
        assert_retryable_kind(
            tls,
            true,
            FetchFailureKind::TransientNetwork,
            "curl status 35",
        );

        let oversized = classify_curl_output("demo", "metadata", &output(63, "000"), false);
        assert_retryable_kind(
            oversized,
            false,
            FetchFailureKind::UpstreamDrift,
            "curl status 63",
        );
    }

    #[test]
    fn github_403_is_rate_limit_only_with_an_exact_zero_remaining_header() {
        for (metadata, expected) in [
            ("403\n0", FetchFailureKind::RateLimit),
            ("403\n1", FetchFailureKind::UpstreamDrift),
            ("403\n", FetchFailureKind::UpstreamDrift),
            ("403\ninvalid", FetchFailureKind::UpstreamDrift),
        ] {
            assert_retryable_kind(
                classify_curl_output("demo", "metadata", &output(0, metadata), true),
                false,
                expected,
                metadata,
            );
        }
        assert_retryable_kind(
            classify_curl_output("demo", "metadata", &output(0, "403"), false),
            false,
            FetchFailureKind::UpstreamDrift,
            "non-GitHub 403",
        );

        for (remaining, expected) in [
            ("0", FetchFailureKind::RateLimit),
            ("1", FetchFailureKind::UpstreamDrift),
        ] {
            let response = CommandOutput {
                status: Some(1),
                stdout: format!(
                    "HTTP/2.0 403 Forbidden\r\nx-ratelimit-remaining: {remaining}\r\n\r\n{{}}"
                )
                .into_bytes(),
                stderr: Vec::new(),
            };
            assert_retryable_kind(
                classify_gh_output("demo", "metadata", response).map(|_| ()),
                false,
                expected,
                remaining,
            );
        }
    }

    #[test]
    fn curl_metadata_parser_bounds_the_selected_rate_limit_value() {
        assert_eq!(
            parse_curl_metadata(b"403\n0", true),
            Some(CurlMetadata {
                status: 403,
                rate_limit_remaining: Some(0),
            })
        );
        assert_eq!(
            parse_curl_metadata(b"403\nnot-a-number", true),
            Some(CurlMetadata {
                status: 403,
                rate_limit_remaining: None,
            })
        );
        assert_eq!(parse_curl_metadata(b"403\n0\nunexpected", true), None);
        assert_eq!(parse_curl_metadata(b"403\n0", false), None);
    }

    fn assert_retryable_kind<T>(
        result: Result<T, RetryableError>,
        transient: bool,
        expected: FetchFailureKind,
        context: &str,
    ) {
        let (actual_transient, error) = match result {
            Err(RetryableError::Transient(error)) => (true, error),
            Err(RetryableError::Permanent(error)) => (false, error),
            Ok(_) => panic!("{context}: expected a classified fetch failure"),
        };
        assert_eq!(actual_transient, transient, "{context}: retryability");
        assert_eq!(
            error.fetch_kind(),
            Some(expected),
            "{context}: failure kind"
        );
    }
}
