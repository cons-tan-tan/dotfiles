{
  pkgs,
  repoRoot,
}:
let
  appSet = import ../../../apps/_interface/app-set.nix { lib = pkgs.lib; };
  manifest = import ../_data/manifest.nix;
  manifestFile = pkgs.writeText "secrets-manifest.json" (builtins.toJSON manifest);
  source = pkgs.lib.fileset.toSource {
    root = repoRoot;
    fileset = pkgs.lib.fileset.unions (map (entry: repoRoot + "/${entry.src}") manifest);
  };
  core = pkgs.callPackage ../_packages/apply-secrets { };
  script = pkgs.writeShellApplication {
    name = "apply-secrets";
    runtimeInputs = [ pkgs.gnupg ];
    text = ''
      export APPLY_SECRETS_ROOT=${source}
      export APPLY_SECRETS_MANIFEST=${manifestFile}
      export APPLY_SECRETS_SOPS_BIN=${pkgs.lib.getExe pkgs.sops}
      exec ${pkgs.lib.getExe core} "$@"
    '';
  };
in
appSet.mkAppSet {
  entries.apply-secrets = {
    description = "Decrypt sops-managed secrets into place (skips gracefully without the GPG key)";
    inherit script;
  };
}
