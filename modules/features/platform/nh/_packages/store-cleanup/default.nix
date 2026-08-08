{
  fastNixGc,
  fastNixGcArguments ? [ ],
  lib,
  nix,
  profileCleanup,
  writeShellApplication,
}:
writeShellApplication {
  name = "nix-store-cleanup";
  runtimeInputs = [
    fastNixGc
    nix
    profileCleanup
  ];

  text = ''
    if (($# != 0)); then
      echo "nix-store-cleanup does not accept arguments" >&2
      exit 2
    fi

    ${lib.getExe profileCleanup} --no-gc
    exec ${lib.getExe fastNixGc} ${lib.escapeShellArgs fastNixGcArguments}
  '';
}
