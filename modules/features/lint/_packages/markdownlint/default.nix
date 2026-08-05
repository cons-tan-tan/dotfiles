{ pkgs }:

let
  contract = import ./contract.nix;
  runnerFactory = import ./runner.nix { inherit pkgs; };
  validation = import ./validation.nix {
    inherit
      contract
      pkgs
      runnerFactory
      ;
    productionLintExecutable = pkgs.lib.getExe lintEngine;
    productionRunner = runner;
  };

  nodeLint = import ../../_lib/mk-node-lint-app.nix { inherit pkgs; } {
    name = "markdownlint";
    inherit (contract) nodeDir;
  };
  lintEngine = pkgs.writeShellApplication {
    name = "markdownlint-engine";
    text = ''
      ${nodeLint.mkExec "${contract.packageName}/${contract.entry}"} \
        "$@"
    '';
  };
  runner = runnerFactory {
    inherit (contract) config;
    lintExecutable = pkgs.lib.getExe lintEngine;
  };
in
{
  app = {
    type = "app";
    meta.description = "Run markdownlint with repository-managed technical documentation modes";
    program = pkgs.lib.getExe runner.package;
  };
  inherit validation;
}
