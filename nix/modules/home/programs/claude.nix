{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
let
  inherit (config.my) dotfilesDir;

  claudeCodePackage = pkgs.claude-code.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.makeWrapper ];
    postFixup =
      let
        oldPostFixup = old.postFixup or "";
      in
      oldPostFixup
      + ''
        wrapProgram $out/bin/.claude-wrapped \
          --prefix PATH : ${pkgs.nodejs}/bin \
          --add-flags "--effort xhigh"
      '';
  });

  settingsLib = import ../../../lib/settings/claude.nix { inherit lib; };

  jsonFormat = pkgs.formats.json { };

  baseSettingsFile = jsonFormat.generate "claude-settings-base.json" (
    settingsLib.mkSettings {
      isDarwin = config.my.isDarwin;
      hcomPath = "${pkgs.hcom}/bin/hcom";
    }
  );

  # hcom 分は生成物 (overlay が hcom 実行で生成) から取り、手書きで二重管理しない。
  # hcom も PreToolUse を使うため、gh-api guard と両立させる。
  mergedSettingsFile =
    pkgs.runCommand "claude-settings.json"
      {
        nativeBuildInputs = [ pkgs.jq ];
      }
      ''
        jq -s '
          .[0] as $base | .[1] as $hcom |
          $base
          | .permissions.allow += $hcom.permissions.allow
          | .hooks = ($hcom.hooks + { PreToolUse: (($hcom.hooks.PreToolUse // []) + $base.hooks.PreToolUse) })
        ' ${baseSettingsFile} ${pkgs.hcom-claude-hooks} > $out
      '';
in
{
  programs.claude-code = {
    enable = true;
    package = claudeCodePackage;
    plugins = [
      "${inputs.codex-plugin-cc}/plugins/codex"
    ];
    # settings は指定しない: settings = { } なら HM モジュールは settings.json を
    # 書かないので、build 時マージ結果 (mergedSettingsFile) を home.file で置ける。
  };

  home.file.".claude/settings.json".source = mergedSettingsFile;

  home.file.".claude/CLAUDE.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/claude/CLAUDE.md";
  home.file.".claude/commands".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/claude/commands";
  home.file.".claude/rules".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/claude/rules";
  home.file.".claude/output-styles".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/claude/output-styles";
  home.file.".claude/hooks".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/claude/hooks";
}
