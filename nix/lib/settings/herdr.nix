# herdr session hook の起動コマンドを Claude Code と Codex で共有し、
# エージェント統合ごとの構築式が分岐しないようにする。
{ lib, pkgs }:
{
  mkSessionHookCommand =
    hookPath:
    "${pkgs.coreutils}/bin/env PATH=${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.python3
      ]
    } ${pkgs.bash}/bin/bash ${lib.escapeShellArg hookPath} session";
}
