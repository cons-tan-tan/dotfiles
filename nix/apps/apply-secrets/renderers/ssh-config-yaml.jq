def fail_msg($msg): error("ssh config secret: " + $msg);

def string_array($field):
  if type != "array" then
    fail_msg($field + " must be an array")
  else
    map(
      if type == "string" and length > 0 and (test("[[:space:][:cntrl:]]") | not) then
        .
      else
        fail_msg($field + " entries must be non-empty strings without whitespace or control characters")
      end
    )
  end;

def reject_line_breaks:
  if test("[\r\n]") then
    fail_msg("option values must not contain line breaks")
  else
    .
  end;

def option_value:
  if type == "string" or type == "number" then
    tostring | reject_line_breaks
  elif type == "boolean" then
    if . then "yes" else "no" end
  else
    fail_msg("option values must be scalar")
  end;

def host_patterns:
  if has("patterns_unencrypted") then
    .patterns_unencrypted | string_array("patterns_unencrypted")
  elif has("host_unencrypted") then
    [.host_unencrypted] | string_array("host_unencrypted")
  else
    fail_msg("host entries must define host_unencrypted or patterns_unencrypted")
  end;

def host_options:
  .options // fail_msg("host entries must define options")
  | if type == "object" then
      to_entries
    else
      fail_msg("options must be an object")
    end
  | map(select(.value != null))
  | map(
      if .key | test("^[A-Za-z][A-Za-z0-9]*$") then
        "    \(.key) \(.value | option_value)"
      else
        fail_msg("option names must be OpenSSH keywords")
      end
    );

.hosts // fail_msg("top-level hosts is required")
| if type == "array" then
    .
  else
    fail_msg("top-level hosts must be an array")
  end
| [
    "# Managed by apply-secrets - do not edit directly",
    "",
    (
      .[]
      | "Host \(host_patterns | join(" "))",
        (host_options[]),
        ""
    )
  ]
| .[]
