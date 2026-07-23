use std::ffi::{OsStr, OsString};
use std::os::unix::ffi::OsStrExt;

use crate::PolicyError;

const LONG_NO_VALUE: &[&str] = &["--include", "--paginate", "--silent", "--slurp", "--help"];

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum ValueOption {
    Field,
    Header,
    Hostname,
    Jq,
    Preview,
    RawField,
    Template,
}

impl ValueOption {
    const fn name(self) -> &'static str {
        match self {
            Self::Field => "--field",
            Self::Header => "--header",
            Self::Hostname => "--hostname",
            Self::Jq => "--jq",
            Self::Preview => "--preview",
            Self::RawField => "--raw-field",
            Self::Template => "--template",
        }
    }
}

const LONG_VALUE: &[(&str, ValueOption)] = &[
    ("--field", ValueOption::Field),
    ("--header", ValueOption::Header),
    ("--hostname", ValueOption::Hostname),
    ("--jq", ValueOption::Jq),
    ("--preview", ValueOption::Preview),
    ("--raw-field", ValueOption::RawField),
    ("--template", ValueOption::Template),
];

pub fn build_arguments(arguments: Vec<OsString>) -> Result<Vec<OsString>, PolicyError> {
    let mut pending: Option<ValueOption> = None;
    let mut endpoint_count = 0usize;
    for argument in &arguments {
        let bytes = argument.as_os_str().as_bytes();
        if let Some(option) = pending.take() {
            validate_value(option, bytes)?;
            continue;
        }
        if bytes == b"--" {
            return reject("--", "argument separators are not allowed");
        }
        if bytes.starts_with(b"--") {
            pending = parse_long(bytes)?;
        } else if bytes.starts_with(b"-") {
            pending = parse_short(bytes)?;
        } else {
            validate_endpoint(bytes)?;
            endpoint_count += 1;
        }
    }
    if let Some(option) = pending {
        return Err(PolicyError::new(format!(
            "gh-api-get: '{}' requires a value",
            option.name()
        )));
    }
    let requested_help = arguments
        .iter()
        .any(|argument| argument.as_os_str().as_bytes() == b"--help");
    if endpoint_count != 1 && !(requested_help && endpoint_count == 0) {
        return Err(PolicyError::new(
            "gh-api-get: exactly one API endpoint is required",
        ));
    }

    let mut child = Vec::with_capacity(arguments.len() + 5);
    child.push(OsString::from("api"));
    // Pinning the host prevents ambient GH_HOST or gh config from redirecting
    // authenticated requests outside the trust boundary.
    child.push(OsString::from("--hostname"));
    child.push(OsString::from("github.com"));
    child.extend(arguments);
    child.push(OsString::from("--method"));
    child.push(OsString::from("GET"));
    Ok(child)
}

fn parse_long(argument: &[u8]) -> Result<Option<ValueOption>, PolicyError> {
    let split = argument.iter().position(|byte| *byte == b'=');
    let (flag, value) = split.map_or((argument, None), |index| {
        (&argument[..index], Some(&argument[index + 1..]))
    });
    if matches!(flag, b"--method" | b"--input") {
        return reject_lossy(
            flag,
            "it can change the request method or read a request body",
        );
    }
    if let Some(canonical) = find_flag(flag, LONG_NO_VALUE) {
        if value.is_some() {
            return reject(canonical, "this option does not accept a value");
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
        reject_lossy(flag, "it is not on the positive read-only allowlist")
    }
}

fn parse_short(argument: &[u8]) -> Result<Option<ValueOption>, PolicyError> {
    if argument == b"-i" {
        return Ok(None);
    }
    if argument.starts_with(b"-X") {
        return reject("-X", "this wrapper always uses GET");
    }
    let (option, value) = match argument.get(1).copied() {
        Some(b'F') => (ValueOption::Field, &argument[2..]),
        Some(b'H') => (ValueOption::Header, &argument[2..]),
        Some(b'q') => (ValueOption::Jq, &argument[2..]),
        Some(b'p') => (ValueOption::Preview, &argument[2..]),
        Some(b'f') => (ValueOption::RawField, &argument[2..]),
        Some(b't') => (ValueOption::Template, &argument[2..]),
        _ => return reject_lossy(argument, "it is not on the positive read-only allowlist"),
    };
    if value.is_empty() {
        Ok(Some(option))
    } else {
        validate_value(option, value)?;
        Ok(None)
    }
}

fn validate_value(option: ValueOption, value: &[u8]) -> Result<(), PolicyError> {
    let name = option.name();
    if matches!(option, ValueOption::Field | ValueOption::RawField) {
        let Some(equals) = value.iter().position(|byte| *byte == b'=') else {
            return reject(name, "fields must use key=value syntax");
        };
        if equals == 0 {
            return reject(name, "field keys must not be empty");
        }
        if value[equals + 1..].starts_with(b"@") {
            return reject(
                name,
                "field values must not read local files or standard input",
            );
        }
        if [
            b"{owner}".as_slice(),
            b"{repo}".as_slice(),
            b"{branch}".as_slice(),
        ]
        .iter()
        .any(|placeholder| contains(&value[equals + 1..], placeholder))
        {
            return reject(
                name,
                "field values must be literal and must not expand local repository metadata",
            );
        }
    }
    if option == ValueOption::Header {
        validate_header(name, value)?;
    }
    if option == ValueOption::Jq && contains_ascii_case_insensitive(value, b"env") {
        return reject(
            name,
            "jq environment access is not allowed by the response-only policy",
        );
    }
    if option == ValueOption::Hostname && !value.eq_ignore_ascii_case(b"github.com") {
        return reject(
            name,
            "only github.com is trusted by the automatically allowed wrapper",
        );
    }
    Ok(())
}

fn validate_endpoint(value: &[u8]) -> Result<(), PolicyError> {
    let has_scheme = value
        .iter()
        .position(|byte| *byte == b':')
        .is_some_and(|colon| {
            colon > 0
                && value[0].is_ascii_alphabetic()
                && value[1..colon]
                    .iter()
                    .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'+' | b'-' | b'.'))
        });
    if value.is_empty() || value.starts_with(b"//") || has_scheme {
        return reject(
            "endpoint",
            "absolute and scheme-relative URLs are not allowed; use a relative GitHub API endpoint",
        );
    }
    Ok(())
}

fn validate_header(option: &str, value: &[u8]) -> Result<(), PolicyError> {
    if value.iter().any(|byte| *byte < 0x20 || *byte == 0x7f) {
        return reject(
            option,
            "control characters can inject or reframe HTTP headers",
        );
    }
    let name = value.split(|byte| *byte == b':').next().unwrap_or_default();
    let name = trim_ascii(name);
    if name.is_empty()
        || name.starts_with(b":")
        || contains_ascii_case_insensitive(name, b"method")
        || is_unsafe_framing_header(name)
    {
        return reject(
            option,
            "method override, pseudo, routing, and framing headers are not allowed",
        );
    }
    Ok(())
}

fn contains(haystack: &[u8], needle: &[u8]) -> bool {
    haystack
        .windows(needle.len())
        .any(|window| window == needle)
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

fn trim_ascii(mut value: &[u8]) -> &[u8] {
    while value.first().is_some_and(u8::is_ascii_whitespace) {
        value = &value[1..];
    }
    while value.last().is_some_and(u8::is_ascii_whitespace) {
        value = &value[..value.len() - 1];
    }
    value
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

fn reject_lossy<T>(option: &[u8], reason: &str) -> Result<T, PolicyError> {
    reject(&OsStr::from_bytes(option).to_string_lossy(), reason)
}

fn reject<T>(option: &str, reason: &str) -> Result<T, PolicyError> {
    Err(PolicyError::new(format!(
        "gh-api-get: '{option}' is not allowed: {reason}"
    )))
}

#[cfg(test)]
mod tests {
    use super::*;
    use proptest::prelude::*;
    use std::os::unix::ffi::OsStringExt;

    fn args(values: &[&str]) -> Vec<OsString> {
        values.iter().map(OsString::from).collect()
    }

    #[test]
    fn allows_response_flags_and_forces_get() {
        let child = build_arguments(args(&[
            "repos/o/r/issues",
            "-Fstate=open",
            "--jq",
            ".",
            "--paginate",
        ]))
        .unwrap();
        assert_eq!(
            &child[..3],
            [
                OsString::from("api"),
                OsString::from("--hostname"),
                OsString::from("github.com")
            ]
        );
        assert_eq!(
            &child[child.len() - 2..],
            [OsString::from("--method"), OsString::from("GET")]
        );
    }

    #[test]
    fn rejects_input_method_and_field_indirection() {
        for values in [
            vec!["repos/o/r", "--input", "/tmp/body"],
            vec!["repos/o/r", "--method=POST"],
            vec!["repos/o/r", "-XDELETE"],
            vec!["repos/o/r", "-F", "body=@/tmp/body"],
            vec!["repos/o/r", "--raw-field=query=@-"],
            vec!["repos/o/r", "--", "--method", "DELETE"],
        ] {
            assert!(build_arguments(args(&values)).is_err(), "{values:?}");
        }
    }

    #[test]
    fn rejects_method_override_headers_and_extra_endpoints() {
        assert!(
            build_arguments(args(&["repos/o/r", "-H", "X-HTTP-Method-Override: DELETE"])).is_err()
        );
        assert!(build_arguments(args(&["repos/o/r", "repos/o/other"])).is_err());
    }

    #[test]
    fn rejects_external_endpoints_and_untrusted_hosts() {
        for values in [
            vec!["https://example.com/x"],
            vec!["HTTPS://example.com/x"],
            vec!["//example.com/x"],
            vec!["http://169.254.169.254/latest/meta-data"],
            vec!["repos/o/r", "--hostname", "example.com"],
        ] {
            assert!(build_arguments(args(&values)).is_err(), "{values:?}");
        }
    }

    #[test]
    fn rejects_jq_environment_access() {
        for values in [
            vec!["repos/o/r", "--jq", "env.GH_TOKEN"],
            vec!["repos/o/r", "-q$ENV.GH_TOKEN"],
        ] {
            assert!(build_arguments(args(&values)).is_err(), "{values:?}");
        }
    }

    #[test]
    fn preserves_non_utf8_endpoint_bytes() {
        let endpoint = OsString::from_vec(b"repos/o/r/\xff".to_vec());
        let child = build_arguments(vec![endpoint.clone()]).unwrap();
        assert!(child.contains(&endpoint));
    }

    proptest! {
        #[test]
        fn unknown_long_options_are_default_denied(name in "[a-z]{1,24}") {
            let flag = format!("--{name}");
            prop_assume!(!LONG_NO_VALUE.contains(&flag.as_str()));
            prop_assume!(!LONG_VALUE.iter().any(|(allowed, _)| *allowed == flag));
            prop_assume!(flag != "--method" && flag != "--input");
            prop_assert!(build_arguments(vec![
                OsString::from("repos/o/r"),
                OsString::from(flag),
            ]).is_err());
        }
    }
}
