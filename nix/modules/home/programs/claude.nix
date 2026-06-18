{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
let
  inherit (config.my) dotfilesDir;

  # 上流パッケージの内部実装 (.claude-wrapped という wrapper 名) に依存しない
  # よう、パッケージはそのままに symlinkJoin の上から wrapProgram で包む。
  # HM 側 (programs.claude-code) が plugins 用にさらに symlinkJoin で包むが、
  # 各 wrapper は絶対パスで自身の実体を参照するため多段でも安全に合成される。
  claudeCodePackage = pkgs.symlinkJoin {
    name = "claude-code-wrapped";
    paths = [ pkgs.claude-code ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/claude \
        --prefix PATH : ${pkgs.nodejs}/bin \
        --add-flags "--effort xhigh"
    '';
    inherit (pkgs.claude-code) meta;
  };

  settingsLib = import ../../../lib/settings/claude.nix { inherit lib; };
  settingsValidator = import ../../../lib/mk-claude-settings-validator.nix { inherit pkgs; };

  jsonFormat = pkgs.formats.json { };

  baseSettingsFile = jsonFormat.generate "claude-settings-base.json" (
    settingsLib.mkSettings {
      isDarwin = config.my.isDarwin;
      hcomPath = "${pkgs.hcom}/bin/hcom";
    }
  );

  # hcom 分は生成物 (overlay が hcom 実行で生成) から取り、手書きで二重管理しない。
  mergedSettingsRaw =
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

  mergedSettingsFile = settingsValidator.validate "claude-settings.json" mergedSettingsRaw;
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
