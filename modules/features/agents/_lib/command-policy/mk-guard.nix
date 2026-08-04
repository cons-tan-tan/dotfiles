# guard policy は Nix schema と Rust/Shellfirm catalog の両方を通ったものだけを公開する。
{
  lib,
  pkgs,
  policy,
}:
let
  guard = pkgs.dotfilesPackages.agent-command-guard;
  jsonFormat = pkgs.formats.json { };
  uncheckedPolicy = jsonFormat.generate "agent-command-guard-policy-unchecked.json" policy;
  policyFile = pkgs.runCommandLocal "agent-command-guard-policy.json" { } ''
    ${lib.getExe guard} --validate-policy --policy ${uncheckedPolicy}
    cp ${uncheckedPolicy} "$out"
  '';
in
{
  inherit guard policyFile;
  command = lib.escapeShellArgs [
    (lib.getExe guard)
    "--policy"
    (toString policyFile)
  ];
}
