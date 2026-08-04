{ pkgs }:

let
  contract = import ./contract.nix;
  runnerFactory = import ./runner.nix { inherit pkgs; };
  validation = import ./validation.nix {
    inherit contract pkgs runnerFactory;
  };

  nodeLint = import ../mk-node-lint-app.nix { inherit pkgs; } {
    name = "textlint";
    inherit (contract) nodeDir;
  };
  lintEngine = pkgs.writeShellApplication {
    name = "textlint-engine";
    text = ''
      ${nodeLint.mkExec "${contract.packageName}/${contract.entry}"} \
        "$@"
    '';
  };
  runner = runnerFactory {
    inherit (contract) modes;
    lintExecutable = pkgs.lib.getExe lintEngine;
  };
in
{
  app = {
    type = "app";
    meta.description = "Run textlint with repository-managed Japanese documentation lint modes";
    program = pkgs.lib.getExe runner.package;
  };
  inherit validation;
}
