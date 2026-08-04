{
  lib,
  linuxSettings,
  pkgs,
  wslSettings,
}:
pkgs.runCommand "claude-userprofile-contract"
  {
    nativeBuildInputs = [ pkgs.jq ];
  }
  ''
    actual="$(${lib.getExe pkgs.jq} --raw-output '.env.USERPROFILE // empty' ${wslSettings})"
    if [ "$actual" != ${lib.escapeShellArg "/mnt/c/Users/zhouc"} ]; then
      echo "WSL Claude USERPROFILE mismatch: $actual" >&2
      exit 1
    fi

    if ${lib.getExe pkgs.jq} --exit-status '.env | has("USERPROFILE")' ${linuxSettings} >/dev/null; then
      echo "non-WSL Claude settings unexpectedly contain USERPROFILE" >&2
      exit 1
    fi

    touch "$out"
  ''
