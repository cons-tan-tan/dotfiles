use serde_json::{Map, Value};

const HEADER: &str = "# Managed by apply-secrets - do not edit directly";

pub fn render_ssh_config(bytes: &[u8]) -> Result<Vec<u8>, String> {
    let document: Value = serde_json::from_slice(bytes)
        .map_err(|error| format!("invalid decrypted JSON: {error}"))?;
    let root = document
        .as_object()
        .ok_or_else(|| "top-level value must be an object".to_owned())?;
    let hosts = root
        .get("hosts")
        .ok_or_else(|| "top-level hosts is required".to_owned())?
        .as_array()
        .ok_or_else(|| "top-level hosts must be an array".to_owned())?;

    let mut output = String::from(HEADER);
    output.push_str("\n\n");
    for host in hosts {
        render_host(host, &mut output)?;
    }
    Ok(output.into_bytes())
}

fn render_host(host: &Value, output: &mut String) -> Result<(), String> {
    let object = host
        .as_object()
        .ok_or_else(|| "host entries must be objects".to_owned())?;
    let patterns = host_patterns(object)?;
    let options = object
        .get("options")
        .ok_or_else(|| "host entries must define options".to_owned())?
        .as_object()
        .ok_or_else(|| "options must be an object".to_owned())?;

    output.push_str("Host ");
    output.push_str(&patterns.join(" "));
    output.push('\n');
    for (name, value) in options {
        if value.is_null() {
            continue;
        }
        if !valid_option_name(name) {
            return Err("option names must be OpenSSH keywords".to_owned());
        }
        output.push_str("    ");
        output.push_str(name);
        output.push(' ');
        output.push_str(&option_value(value)?);
        output.push('\n');
    }
    output.push('\n');
    Ok(())
}

fn host_patterns(object: &Map<String, Value>) -> Result<Vec<&str>, String> {
    let values: Vec<&Value> = if let Some(patterns) = object.get("patterns_unencrypted") {
        patterns
            .as_array()
            .ok_or_else(|| "patterns_unencrypted must be an array".to_owned())?
            .iter()
            .collect()
    } else if let Some(host) = object.get("host_unencrypted") {
        vec![host]
    } else {
        return Err("host entries must define host_unencrypted or patterns_unencrypted".to_owned());
    };

    values
        .into_iter()
        .map(|value| {
            let pattern = value.as_str().ok_or_else(|| {
                "host patterns must be non-empty strings without whitespace or control characters"
                    .to_owned()
            })?;
            if pattern.is_empty()
                || pattern
                    .chars()
                    .any(|character| character.is_whitespace() || character.is_control())
            {
                return Err(
                    "host patterns must be non-empty strings without whitespace or control characters"
                        .to_owned(),
                );
            }
            Ok(pattern)
        })
        .collect()
}

fn valid_option_name(name: &str) -> bool {
    let mut bytes = name.bytes();
    matches!(bytes.next(), Some(byte) if byte.is_ascii_alphabetic())
        && bytes.all(|byte| byte.is_ascii_alphanumeric())
}

fn option_value(value: &Value) -> Result<String, String> {
    let rendered = match value {
        Value::String(value) => value.clone(),
        Value::Number(value) => jq_number(value)?,
        Value::Bool(true) => "yes".to_owned(),
        Value::Bool(false) => "no".to_owned(),
        _ => return Err("option values must be scalar".to_owned()),
    };
    if rendered.contains(['\r', '\n']) {
        return Err("option values must not contain line breaks".to_owned());
    }
    Ok(rendered)
}

fn jq_number(value: &serde_json::Number) -> Result<String, String> {
    let raw = value.to_string();
    let (negative, unsigned) = raw
        .strip_prefix('-')
        .map_or((false, raw.as_str()), |value| (true, value));
    let (mantissa, explicit_exponent) =
        if let Some((mantissa, exponent)) = unsigned.split_once(['e', 'E']) {
            let exponent = exponent
                .parse::<i64>()
                .map_err(|_| "number exponent is out of range".to_owned())?;
            (mantissa, exponent)
        } else {
            (unsigned, 0)
        };
    let fractional_digits = mantissa
        .split_once('.')
        .map_or(0usize, |(_, fraction)| fraction.len());
    let mut coefficient = mantissa
        .bytes()
        .filter(|byte| *byte != b'.')
        .collect::<Vec<_>>();
    let first_nonzero = coefficient.iter().position(|byte| *byte != b'0');
    let all_zero = first_nonzero.is_none();
    if let Some(index) = first_nonzero {
        coefficient.drain(..index);
    } else {
        coefficient.clear();
        coefficient.push(b'0');
    }

    let digit_count =
        i64::try_from(coefficient.len()).map_err(|_| "number has too many digits".to_owned())?;
    let fractional_digits = i64::try_from(fractional_digits)
        .map_err(|_| "number has too many fractional digits".to_owned())?;
    let exponent = explicit_exponent
        .checked_sub(fractional_digits)
        .ok_or_else(|| "number exponent is out of range".to_owned())?;
    let adjusted_exponent = exponent
        .checked_add(digit_count - 1)
        .ok_or_else(|| "number exponent is out of range".to_owned())?;
    let coefficient =
        String::from_utf8(coefficient).map_err(|_| "number is not ASCII".to_owned())?;

    let mut rendered = if exponent > 0 || adjusted_exponent < -6 {
        let mut scientific = String::new();
        scientific.push(coefficient.as_bytes()[0] as char);
        if coefficient.len() > 1 {
            scientific.push('.');
            scientific.push_str(&coefficient[1..]);
        }
        scientific.push('E');
        if adjusted_exponent >= 0 {
            scientific.push('+');
        }
        scientific.push_str(&adjusted_exponent.to_string());
        scientific
    } else {
        let decimal_position = digit_count + exponent;
        if decimal_position <= 0 {
            let zero_count = usize::try_from(-decimal_position)
                .map_err(|_| "number exponent is out of range".to_owned())?;
            format!("0.{}{coefficient}", "0".repeat(zero_count))
        } else if decimal_position < digit_count {
            let decimal_position = usize::try_from(decimal_position)
                .map_err(|_| "number exponent is out of range".to_owned())?;
            format!(
                "{}.{}",
                &coefficient[..decimal_position],
                &coefficient[decimal_position..]
            )
        } else {
            coefficient
        }
    };
    if negative && !all_zero {
        rendered.insert(0, '-');
    }
    Ok(rendered)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn renders_ordered_hosts_and_scalars() {
        let rendered = render_ssh_config(
            br#"{
              "hosts": [
                {
                  "host_unencrypted": "work",
                  "options": {
                    "HostName": "192.0.2.10",
                    "Port": 2222,
                    "Score": 1.50,
                    "ForwardAgent": false,
                    "Ignored": null
                  }
                },
                {
                  "patterns_unencrypted": ["lab", "lab.local"],
                  "options": {"User": "alice"}
                }
              ]
            }"#,
        )
        .unwrap();
        assert_eq!(
            String::from_utf8(rendered).unwrap(),
            "\
# Managed by apply-secrets - do not edit directly

Host work
    HostName 192.0.2.10
    Port 2222
    Score 1.50
    ForwardAgent no

Host lab lab.local
    User alice

"
        );
    }

    #[test]
    fn rejects_invalid_shapes_and_injection() {
        for fixture in [
            br#"{"#.as_slice(),
            br#"{}"#.as_slice(),
            br#"{"hosts":{}}"#.as_slice(),
            br#"{"hosts":[{"host_unencrypted":"bad host","options":{}}]}"#.as_slice(),
            br#"{"hosts":[{"host_unencrypted":"ok","options":{"Bad-Key":"x"}}]}"#.as_slice(),
            br#"{"hosts":[{"host_unencrypted":"ok","options":{"HostName":"x\nHost evil"}}]}"#
                .as_slice(),
            br#"{"hosts":[{"host_unencrypted":"ok","options":{"HostName":[]}}]}"#.as_slice(),
        ] {
            assert!(render_ssh_config(fixture).is_err());
        }
    }

    #[test]
    fn renders_numbers_like_jq_tostring() {
        let fixture = br#"{
          "hosts": [{
            "host_unencrypted": "work",
            "options": {
              "Decimal": 1.50,
              "Exponent": 1e20,
              "Shifted": 1.50e2,
              "Small": 1e-7,
              "Zero": -0e3
            }
          }]
        }"#;
        let rendered = String::from_utf8(render_ssh_config(fixture).unwrap()).unwrap();
        assert!(rendered.contains("    Decimal 1.50\n"));
        assert!(rendered.contains("    Exponent 1E+20\n"));
        assert!(rendered.contains("    Shifted 150\n"));
        assert!(rendered.contains("    Small 1E-7\n"));
        assert!(rendered.contains("    Zero 0E+3\n"));
    }
}
