use std::ffi::{OsStr, OsString};
use std::os::unix::ffi::OsStrExt;

use crate::PolicyError;

const LONG_NO_VALUE: &[&str] = &[
    "--silent",
    "--show-error",
    "--location",
    "--fail",
    "--fail-with-body",
    "--compressed",
    "--no-progress-meter",
    "--ipv4",
    "--ipv6",
    "--head",
    "--show-headers",
    "--globoff",
];

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum ValueOption {
    UserAgent,
    Header,
    MaxTime,
    ConnectTimeout,
    Retry,
    RetryDelay,
    RetryMaxTime,
    MaxRedirs,
    Range,
    Url,
    Output,
    WriteOut,
}

impl ValueOption {
    const fn name(self) -> &'static str {
        match self {
            Self::UserAgent => "--user-agent",
            Self::Header => "--header",
            Self::MaxTime => "--max-time",
            Self::ConnectTimeout => "--connect-timeout",
            Self::Retry => "--retry",
            Self::RetryDelay => "--retry-delay",
            Self::RetryMaxTime => "--retry-max-time",
            Self::MaxRedirs => "--max-redirs",
            Self::Range => "--range",
            Self::Url => "--url",
            Self::Output => "--output",
            Self::WriteOut => "--write-out",
        }
    }
}

const LONG_VALUE: &[(&str, ValueOption)] = &[
    ("--user-agent", ValueOption::UserAgent),
    ("--header", ValueOption::Header),
    ("--max-time", ValueOption::MaxTime),
    ("--connect-timeout", ValueOption::ConnectTimeout),
    ("--retry", ValueOption::Retry),
    ("--retry-delay", ValueOption::RetryDelay),
    ("--retry-max-time", ValueOption::RetryMaxTime),
    ("--max-redirs", ValueOption::MaxRedirs),
    ("--range", ValueOption::Range),
    ("--url", ValueOption::Url),
    ("--output", ValueOption::Output),
    ("--write-out", ValueOption::WriteOut),
];

const SHORT_NO_VALUE: &[u8] = b"sSLfIig";
const SHORT_VALUE: &[(u8, ValueOption)] = &[
    (b'A', ValueOption::UserAgent),
    (b'H', ValueOption::Header),
    (b'm', ValueOption::MaxTime),
    (b'o', ValueOption::Output),
    (b'w', ValueOption::WriteOut),
    (b'r', ValueOption::Range),
];

pub fn build_arguments(arguments: Vec<OsString>) -> Result<Vec<OsString>, PolicyError> {
    let mut pending: Option<ValueOption> = None;
    for argument in &arguments {
        let bytes = argument.as_os_str().as_bytes();
        if let Some(option) = pending.take() {
            validate_value(option, bytes)?;
            continue;
        }
        if bytes == b"--" {
            return Err(PolicyError::new(
                "Error: '--' is not allowed by curl-fetch.",
            ));
        }
        if bytes.starts_with(b"--") {
            pending = parse_long(bytes)?;
        } else if bytes.starts_with(b"-") {
            pending = parse_short(bytes)?;
        } else {
            validate_url(bytes)?;
        }
    }
    if let Some(option) = pending {
        return Err(PolicyError::new(format!(
            "Error: '{}' requires a value",
            option.name()
        )));
    }

    let mut child = vec![
        OsString::from("-q"),
        OsString::from("--globoff"),
        OsString::from("--proto"),
        OsString::from("=http,https"),
        OsString::from("--proto-redir"),
        OsString::from("=http,https"),
    ];
    child.extend(arguments);
    Ok(child)
}

fn parse_long(argument: &[u8]) -> Result<Option<ValueOption>, PolicyError> {
    let split = argument.iter().position(|byte| *byte == b'=');
    let (flag, value) = split.map_or((argument, None), |index| {
        (&argument[..index], Some(&argument[index + 1..]))
    });
    if let Some(canonical) = find_flag(flag, LONG_NO_VALUE) {
        if value.is_some() {
            return Err(PolicyError::new(format!(
                "Error: '{canonical}' does not accept a value in curl-fetch."
            )));
        }
        return Ok(None);
    }
    if let Some(option) = find_value_flag(flag) {
        if let Some(value) = value {
            validate_value(option, value)?;
            Ok(None)
        } else {
            Ok(Some(option))
        }
    } else {
        reject_lossy(flag)
    }
}

fn parse_short(argument: &[u8]) -> Result<Option<ValueOption>, PolicyError> {
    let characters = &argument[1..];
    if characters.is_empty() {
        return reject("-");
    }
    let mut index = 0;
    while index < characters.len() {
        let character = characters[index];
        if SHORT_NO_VALUE.contains(&character) {
            index += 1;
            continue;
        }
        let Some((_, option)) = SHORT_VALUE
            .iter()
            .find(|(candidate, _)| *candidate == character)
        else {
            return reject(&format!("-{}", char::from(character)));
        };
        let rest = &characters[index + 1..];
        if rest.is_empty() {
            return Ok(Some(*option));
        }
        validate_value(*option, rest)?;
        return Ok(None);
    }
    Ok(None)
}

fn validate_value(option: ValueOption, value: &[u8]) -> Result<(), PolicyError> {
    let name = option.name();
    if option == ValueOption::Header {
        validate_header(name, value)?;
    }
    if option == ValueOption::UserAgent && contains_control(value) {
        return Err(PolicyError::new(format!(
            "Error: '{name}' does not allow control characters in curl-fetch.\n\
             Reason: control characters can inject additional HTTP headers.\n\
             Alternative: Pass a literal User-Agent without control characters."
        )));
    }
    if option == ValueOption::Range
        && (value.is_empty()
            || !value
                .iter()
                .all(|byte| byte.is_ascii_digit() || matches!(byte, b'-' | b','))
            || !value.iter().any(u8::is_ascii_digit))
    {
        return Err(PolicyError::new(format!(
            "Error: '{name}' requires a literal byte range in curl-fetch.\n\
             Reason: range values are limited to digits, hyphens, and commas.\n\
             Alternative: Use a form such as 0-499, 500-, or -500."
        )));
    }
    if option == ValueOption::WriteOut {
        if value.starts_with(b"@") {
            return Err(PolicyError::new(format!(
                "Error: '{name}' does not allow @file values in curl-fetch.\n\
                 Reason: @file syntax reads a local format string from disk.\n\
                 Alternative: Pass a literal write-out format, for example --write-out '%{{http_code}}'."
            )));
        }
        if contains(value, b"%output{") {
            return Err(PolicyError::new(format!(
                "Error: '{name}' does not allow %output{{...}} in curl-fetch.\n\
                 Reason: the directive writes write-out data to a local file.\n\
                 Alternative: Keep write-out output on stdout."
            )));
        }
    }
    if option == ValueOption::Url {
        validate_url(value)?;
    }
    Ok(())
}

fn validate_header(option: &str, value: &[u8]) -> Result<(), PolicyError> {
    if value.starts_with(b"@") {
        return Err(PolicyError::new(format!(
            "Error: '{option}' does not allow @file values in curl-fetch.\n\
             Reason: @file syntax reads a local file into the request.\n\
             Alternative: Pass a literal header value, or use raw curl with explicit approval."
        )));
    }
    if contains_control(value) {
        return Err(PolicyError::new(format!(
            "Error: '{option}' does not allow control characters in curl-fetch.\n\
             Reason: control characters can inject or reframe HTTP headers.\n\
             Alternative: Pass one literal header without control characters."
        )));
    }

    let name_end = value
        .iter()
        .position(|byte| matches!(byte, b':' | b';'))
        .unwrap_or(value.len());
    let name = trim_ascii_space(&value[..name_end]);
    if name.is_empty()
        || name.starts_with(b":")
        || contains_ascii_case_insensitive(name, b"method")
        || is_unsafe_framing_header(name)
    {
        return Err(PolicyError::new(format!(
            "Error: '{option}' does not allow this header name in curl-fetch.\n\
             Reason: method override, pseudo, routing, and framing headers can bypass a read-only GET.\n\
             Alternative: Use ordinary end-to-end request headers, or raw curl with explicit approval."
        )));
    }
    Ok(())
}

fn contains_control(value: &[u8]) -> bool {
    value.iter().any(|byte| *byte < 0x20 || *byte == 0x7f)
}

fn trim_ascii_space(mut value: &[u8]) -> &[u8] {
    while value.first() == Some(&b' ') {
        value = &value[1..];
    }
    while value.last() == Some(&b' ') {
        value = &value[..value.len() - 1];
    }
    value
}

fn contains_ascii_case_insensitive(value: &[u8], needle: &[u8]) -> bool {
    value
        .windows(needle.len())
        .any(|window| window.eq_ignore_ascii_case(needle))
}

fn is_unsafe_framing_header(name: &[u8]) -> bool {
    [
        b"connection".as_slice(),
        b"content-length".as_slice(),
        b"expect".as_slice(),
        b"host".as_slice(),
        b"keep-alive".as_slice(),
        b"proxy-connection".as_slice(),
        b"te".as_slice(),
        b"trailer".as_slice(),
        b"transfer-encoding".as_slice(),
        b"upgrade".as_slice(),
    ]
    .iter()
    .any(|candidate| name.eq_ignore_ascii_case(candidate))
}

fn validate_url(value: &[u8]) -> Result<(), PolicyError> {
    if value.starts_with(b"http://") || value.starts_with(b"https://") {
        Ok(())
    } else {
        Err(PolicyError::new(
            "Error: URLs passed to curl-fetch must use http:// or https://",
        ))
    }
}

fn contains(haystack: &[u8], needle: &[u8]) -> bool {
    haystack
        .windows(needle.len())
        .any(|window| window == needle)
}

fn find_flag(flag: &[u8], allowed: &[&'static str]) -> Option<&'static str> {
    allowed
        .iter()
        .copied()
        .find(|candidate| flag == candidate.as_bytes())
}

fn find_value_flag(flag: &[u8]) -> Option<ValueOption> {
    LONG_VALUE
        .iter()
        .find_map(|(name, option)| (flag == name.as_bytes()).then_some(*option))
}

fn reject_lossy<T>(option: &[u8]) -> Result<T, PolicyError> {
    reject(&OsStr::from_bytes(option).to_string_lossy())
}

fn reject<T>(option: &str) -> Result<T, PolicyError> {
    let (reason, alternative) = rejection_guidance(option);
    Err(PolicyError::new(format!(
        "Error: '{option}' is not allowed by curl-fetch.\n\
         Reason: {reason}\n\
         Alternative: {alternative}"
    )))
}

fn rejection_guidance(option: &str) -> (&'static str, &'static str) {
    match option {
        "-X" | "--request" | "--request-target" | "-d" | "-F" | "-T" | "--upload-file"
        | "--json" | "--post301" | "--post302" | "--post303" => (
            "it can change the request away from a read-only fetch.",
            "Use raw curl with explicit approval, or gh api-get for GitHub API requests.",
        ),
        "-O"
        | "--remote-name"
        | "--remote-name-all"
        | "-J"
        | "--remote-header-name"
        | "--output-dir"
        | "--create-dirs"
        | "--create-file-mode"
        | "--no-clobber"
        | "--skip-existing"
        | "--remove-on-error" => (
            "it lets curl derive or manage local output paths beyond an explicit output file.",
            "Use -o/--output with an explicit path.",
        ),
        _ => (
            "it is not on curl-fetch's small read-only allowlist.",
            "Use WebFetch/agent-browser, raw curl with explicit approval, or review the option before adding it.",
        ),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use proptest::prelude::*;
    use std::os::unix::ffi::OsStringExt;

    fn args(values: &[&str]) -> Vec<OsString> {
        values.iter().map(OsString::from).collect()
    }

    fn assert_allowed(values: &[&str]) {
        assert!(
            build_arguments(args(values)).is_ok(),
            "expected arguments to be allowed: {values:?}"
        );
    }

    fn assert_denied(values: &[&str]) {
        assert!(
            build_arguments(args(values)).is_err(),
            "expected arguments to be denied: {values:?}"
        );
    }

    #[test]
    fn long_no_value_inventory_is_complete_and_allowed() {
        let cases = [
            "--silent",
            "--show-error",
            "--location",
            "--fail",
            "--fail-with-body",
            "--compressed",
            "--no-progress-meter",
            "--ipv4",
            "--ipv6",
            "--head",
            "--show-headers",
            "--globoff",
        ];

        assert_eq!(cases.as_slice(), LONG_NO_VALUE);
        for option in cases {
            assert_allowed(&[option, "https://example.com"]);
            assert_denied(&[&format!("{option}=true"), "https://example.com"]);
        }
    }

    #[test]
    fn long_value_inventory_is_complete_and_classified() {
        let literal_values = [
            ("--user-agent", "safe-fetch/1"),
            ("--header", "Accept: application/json"),
            ("--max-time", "10"),
            ("--connect-timeout", "5"),
            ("--retry", "2"),
            ("--retry-delay", "1"),
            ("--retry-max-time", "30"),
            ("--max-redirs", "4"),
            ("--range", "0-499"),
        ];
        let url_values = [("--url", "https://example.com")];
        let explicit_output_values = [("--output", "/tmp/explicit-output")];
        let response_output_values = [("--write-out", "%{http_code}")];
        let classified = literal_values
            .iter()
            .chain(&url_values)
            .chain(&explicit_output_values)
            .chain(&response_output_values)
            .map(|(name, _)| *name)
            .collect::<Vec<_>>();
        let inventory = LONG_VALUE.iter().map(|(name, _)| *name).collect::<Vec<_>>();

        assert_eq!(classified, inventory);
        for (option, value) in literal_values
            .iter()
            .chain(&url_values)
            .chain(&explicit_output_values)
            .chain(&response_output_values)
        {
            assert_allowed(&[option, value, "https://example.com"]);
            assert_allowed(&[&format!("{option}={value}"), "https://example.com"]);
            assert_denied(&[option]);
        }
    }

    #[test]
    fn short_option_inventory_is_classified() {
        assert_eq!(SHORT_NO_VALUE, b"sSLfIig");
        assert_eq!(
            SHORT_VALUE,
            &[
                (b'A', ValueOption::UserAgent),
                (b'H', ValueOption::Header),
                (b'm', ValueOption::MaxTime),
                (b'o', ValueOption::Output),
                (b'w', ValueOption::WriteOut),
                (b'r', ValueOption::Range),
            ]
        );
        for option in ["-s", "-S", "-L", "-f", "-I", "-i", "-g", "-fsSL"] {
            assert_allowed(&[option, "https://example.com"]);
        }
        for (option, attached, value) in [
            ("-A", "-Asafe-fetch/1", "safe-fetch/1"),
            (
                "-H",
                "-HAccept: application/json",
                "Accept: application/json",
            ),
            ("-m", "-m10", "10"),
            ("-o", "-o/tmp/explicit-output", "/tmp/explicit-output"),
            ("-w", "-w%{http_code}", "%{http_code}"),
            ("-r", "-r0-499", "0-499"),
        ] {
            assert_allowed(&[option, value, "https://example.com"]);
            assert_allowed(&[attached, "https://example.com"]);
            assert_denied(&[option]);
        }
    }

    #[test]
    fn rejected_effectful_option_inventory_is_default_denied() {
        for arguments in [
            vec!["-X", "POST"],
            vec!["--request", "POST"],
            vec!["--request-target", "/other"],
            vec!["-d", "body"],
            vec!["--data", "body"],
            vec!["-F", "file=@/tmp/body"],
            vec!["-T", "/tmp/body"],
            vec!["--upload-file", "/tmp/body"],
            vec!["--json", "{}"],
            vec!["--config", "/tmp/config"],
            vec!["--netrc-file", "/tmp/netrc"],
            vec!["--variable", "name=@/tmp/value"],
            vec!["-O"],
            vec!["--remote-name"],
            vec!["--remote-name-all"],
            vec!["-J"],
            vec!["--remote-header-name"],
            vec!["--output-dir", "/tmp"],
            vec!["--create-dirs"],
            vec!["--create-file-mode", "0600"],
            vec!["--no-clobber"],
            vec!["--skip-existing"],
            vec!["--remove-on-error"],
            vec!["-D", "/tmp/headers"],
            vec!["--dump-header", "/tmp/headers"],
            vec!["-c", "/tmp/cookies"],
            vec!["--cookie-jar", "/tmp/cookies"],
            vec!["--trace", "/tmp/trace"],
            vec!["--etag-save", "/tmp/etag"],
            vec!["--libcurl", "/tmp/request.c"],
            vec!["--hsts", "/tmp/hsts"],
            vec!["--alt-svc", "/tmp/alt-svc"],
            vec!["--stderr", "/tmp/stderr"],
            vec!["--ssl-sessions", "/tmp/sessions"],
        ] {
            let mut values = arguments;
            values.push("https://example.com");
            assert_denied(&values);
        }
    }

    #[test]
    fn url_and_argument_boundaries_are_fixed() {
        for values in [
            vec!["https://example.com"],
            vec!["http://example.com"],
            vec!["http://127.0.0.1/resource"],
            vec!["http://169.254.169.254/latest/meta-data"],
            vec!["--url=https://example.com"],
            vec!["--url", "http://example.com"],
        ] {
            assert_allowed(&values);
        }
        for values in [
            vec!["--", "https://example.com"],
            vec!["--unknown", "https://example.com"],
            vec!["-Z", "https://example.com"],
            vec!["file:///etc/passwd"],
            vec!["ftp://example.com/file"],
            vec!["--url=file:///etc/passwd"],
            vec!["--url", "ftp://example.com/file"],
        ] {
            assert_denied(&values);
        }
    }

    #[test]
    fn accepts_documented_forms_and_pins_protocols() {
        let child =
            build_arguments(args(&["-fsSL", "-Aagent/1", "--url=https://example.com"])).unwrap();
        assert_eq!(
            &child[..6],
            args(&[
                "-q",
                "--globoff",
                "--proto",
                "=http,https",
                "--proto-redir",
                "=http,https"
            ])
        );
    }

    #[test]
    fn handles_short_value_clusters() {
        assert!(build_arguments(args(&["-sLo/path", "https://example.com"])).is_ok());
        assert!(build_arguments(args(&["-sLo", "/path", "https://example.com"])).is_ok());
    }

    #[test]
    fn supports_multiple_explicit_url_output_pairs() {
        assert!(
            build_arguments(args(&[
                "--output",
                "/tmp/one",
                "https://example.com/one",
                "--output=/tmp/two",
                "http://example.com/two",
            ]))
            .is_ok()
        );
    }

    #[test]
    fn preserves_non_utf8_option_values() {
        let header = OsString::from_vec(b"X-Test: \xff".to_vec());
        let child = build_arguments(vec![
            OsString::from("--header"),
            header.clone(),
            OsString::from("https://example.com"),
        ])
        .unwrap();
        assert!(child.contains(&header));
    }

    #[test]
    fn rejects_file_effects_and_unsafe_protocols() {
        for values in [
            vec!["--write-out", "@/tmp/format", "https://example.com"],
            vec!["--write-out=%output{/tmp/status}", "https://example.com"],
            vec![
                "--write-out",
                "%output{>>/tmp/status}%{http_code}",
                "https://example.com",
            ],
            vec!["-H@/tmp/header", "https://example.com"],
            vec!["file:///etc/passwd"],
            vec!["--url", "ftp://example.com"],
            vec!["--config", "/tmp/config", "https://example.com"],
            vec!["-XPOST", "https://example.com"],
        ] {
            assert!(build_arguments(args(&values)).is_err(), "{values:?}");
        }
    }

    #[test]
    fn rejects_header_injection_method_override_and_framing() {
        for values in [
            vec![
                "--header",
                "X-Test: ok\r\nX-HTTP-Method-Override: DELETE",
                "https://example.com",
            ],
            vec![
                "--header",
                "X-HTTP-Method-Override: DELETE",
                "https://example.com",
            ],
            vec!["--header", "Content-Length: 1", "https://example.com"],
            vec!["--header", ":method: POST", "https://example.com"],
            vec![
                "--user-agent",
                "safe\r\nX-HTTP-Method-Override: POST",
                "https://example.com",
            ],
            vec!["--range", "0-1\r\nX-Evil: yes", "https://example.com"],
        ] {
            assert!(build_arguments(args(&values)).is_err(), "{values:?}");
        }
    }

    #[test]
    fn rejects_missing_values_and_unknown_short_characters() {
        assert!(build_arguments(args(&["--header"])).is_err());
        assert!(build_arguments(args(&["-sZ", "https://example.com"])).is_err());
    }

    proptest! {
        #[test]
        fn unknown_long_options_are_default_denied(name in "[a-z]{1,24}") {
            let flag = format!("--{name}");
            prop_assume!(!LONG_NO_VALUE.contains(&flag.as_str()));
            prop_assume!(!LONG_VALUE.iter().any(|(allowed, _)| *allowed == flag));
            prop_assert!(build_arguments(vec![OsString::from(flag)]).is_err());
        }

        #[test]
        fn unknown_short_options_are_default_denied(character in 0x21u8..0x7fu8) {
            prop_assume!(!matches!(
                character,
                b's' | b'S' | b'L' | b'f' | b'I' | b'i' | b'g'
                    | b'A' | b'H' | b'm' | b'o' | b'w' | b'r'
            ));
            let flag = OsString::from_vec(vec![b'-', character]);
            prop_assert!(build_arguments(vec![flag]).is_err());
        }

        #[test]
        fn every_header_control_byte_is_denied(
            prefix in "[ -~]{0,16}",
            control in prop::sample::select(
                (0u8..=0x1f).chain(std::iter::once(0x7f)).collect::<Vec<_>>()
            ),
            suffix in "[ -~]{0,16}",
        ) {
            let mut header = format!("X-Test: {prefix}").into_bytes();
            header.push(control);
            header.extend(suffix.bytes());
            prop_assert!(build_arguments(vec![
                OsString::from("--header"),
                OsString::from_vec(header),
                OsString::from("https://example.com"),
            ]).is_err());
        }

        #[test]
        fn non_http_url_schemes_are_denied(scheme in "[A-Za-z][A-Za-z0-9+.-]{0,12}") {
            prop_assume!(scheme != "http" && scheme != "https");
            let url = format!("{scheme}://example.com/resource");
            prop_assert!(build_arguments(vec![OsString::from(url)]).is_err());
        }
    }
}
