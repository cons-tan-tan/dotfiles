# cli-tools.nix の対応表がスキーマを満たし、移行時のデータ欠落が
# 起きていないことを固定する。
let
  cliTools = import ./cli-tools.nix;
  homePackagesTools = builtins.filter (tool: tool.linux == "home-packages") cliTools;
in
{
  testEveryEntryHasWingetIdAndPackageId = {
    expr = builtins.all (tool: tool.winget ? id && tool.winget ? packageId) cliTools;
    expected = true;
  };

  testHomePackagesEntriesCarryNixpkgsAttr = {
    expr = builtins.all (tool: tool ? nixpkgsAttr) homePackagesTools;
    expected = true;
  };

  testWingetIdsSnapshot = {
    expr = map (tool: tool.winget.id) cliTools;
    expected = [
      "git"
      "gpg4win"
      "op-cli"
      "claude-code"
      "rg"
      "fd"
      "bat"
      "eza"
      "jq"
      "ast-grep"
      "fzf"
      "gh"
      "ghq"
      "starship"
      "zoxide"
      "wt"
      "pwsh"
    ];
  };

  testSharedNixpkgsAttrsSnapshot = {
    expr = map (tool: tool.nixpkgsAttr) homePackagesTools;
    expected = [
      "ripgrep"
      "fd"
      "bat"
      "eza"
      "jq"
      "ast-grep"
      "fzf"
      "ghq"
      "zoxide"
    ];
  };
}
