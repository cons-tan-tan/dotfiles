{
  config,
  pkgs,
  lib,
  hostKind,
  dotfilesDir,
  windowsHomedir,
  codex-plugin-cc,
  ...
}:
let
  hk = import ../../../lib/host-kind.nix { inherit hostKind; };

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

  mkSettings =
    { hostKind }:
    let
      isDarwin = hostKind == "darwin";
      isWindows = hostKind == "windows";

      hooksPath =
        if isWindows then
          "C:/Users/zhouc/.claude/hooks/validate-gh-api.sh"
        else
          "~/.claude/hooks/validate-gh-api.sh";
    in
    {
      includeCoAuthoredBy = false;
      autoMemoryEnabled = false;
      language = "japanese";
      model = "opus[1m]";
      effortLevel = "xhigh";
      # Fable 5 の安全分類でフラグされた時に Opus へ自動継続せず、確認で止める。
      switchModelsOnFlag = false;
      env = {
        USE_BUILTIN_RIPGREP = "0";
        CLAUDE_CODE_NO_FLICKER = "1";
        CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING = "1";
        # 1M context は維持しつつ、Codex と近い 270k tokens 付近で自動圧縮する。
        CLAUDE_CODE_AUTO_COMPACT_WINDOW = "300000";
        CLAUDE_AUTOCOMPACT_PCT_OVERRIDE = "90";
        # CLAUDE_CODE_EFFORT_LEVEL はハードピンされ、起動後のモデル/effort
        # 切り替えより優先されるため使わない。起動時の xhigh 既定値は
        # claude-code wrapper の --effort xhigh で指定する。
        # macOS のトラックパッドだと速すぎるのでデフォルトの 3 のまま
        CLAUDE_CODE_SCROLL_SPEED = if isDarwin then "3" else "6";
        # サブエージェントを最新 Sonnet に固定する。
        # この変数はエイリアス (sonnet) を受け付けず完全なモデル名のみ許容するため、
        # Sonnet 更新時はここを書き換える必要がある。
        CLAUDE_CODE_SUBAGENT_MODEL = "claude-sonnet-4-6";
      }
      // lib.optionalAttrs (!isWindows) {
        # フックが参照する hcom を store path に固定し PATH 非依存にする。
        HCOM = "${pkgs.hcom}/bin/hcom";
      };
      permissions = {
        allow = [
          "WebSearch"
          "WebFetch(*)"
          "Bash(rg *)"
          "Bash(bat *)"
          "Bash(eza *)"
          "Bash(jq *)"
          "Bash(fd *)"
          "Bash(ast-grep *)"
          "Bash(gh issue list *)"
          "Bash(gh issue view *)"
          "Bash(gh pr list *)"
          "Bash(gh pr view *)"
          "Bash(gh pr diff *)"
          "Bash(gh pr checks *)"
          "Bash(gh run list *)"
          "Bash(gh run view *)"
          "Bash(gh repo view *)"
          "Bash(gh search *)"
          "Bash(gh api-get *)"
          "Bash(curl-fetch *)"
        ]
        ++ lib.optionals isWindows [
          "Bash(wsl.exe *)"
          "Bash(pwsh.exe *)"
        ];
        deny = [
          "Bash(rm -rf *)"
          "Bash(fd *--exec*)"
          "Bash(fd *--exec-batch*)"
          "Bash(fd *-x *)"
          "Bash(fd *-X *)"
        ]
        ++ lib.optionals isWindows [
          "Bash(Remove-Item -Recurse -Force *)"
        ];
      };
      # hcom 分の hooks/permissions はここに書かず、build 時に hcom の生成物と
      # マージする (mergedSettingsFile)。eval 時に生成 JSON を読む (IFD) と、
      # 異種プラットフォーム向け構成の評価 (nix flake check 等) が壊れるため。
      hooks.PreToolUse = [
        {
          matcher = "Bash";
          hooks = [
            {
              type = "command";
              command = hooksPath;
            }
          ];
        }
      ];
      # programs.claude-code.settings 経由で HM が付与していた schema と揃える。
      "$schema" = "https://json.schemastore.org/claude-code-settings.json";
    };

  jsonFormat = pkgs.formats.json { };

  # Windows companion には hcom (linux/darwin バイナリ) が無いので gh-api guard
  # のみ。マージ不要なのでそのまま書き出す。
  windowsSettingsFile = jsonFormat.generate "claude-windows-settings.json" (mkSettings {
    hostKind = "windows";
  });

  baseSettingsFile = jsonFormat.generate "claude-settings-base.json" (mkSettings {
    inherit hostKind;
  });

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
      "${codex-plugin-cc}/plugins/codex"
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

  home.activation = lib.mkIf hk.hasWindowsCompanion {
    deployWindowsClaudeSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run mkdir -p ${windowsHomedir}/.claude
      run install -m644 ${windowsSettingsFile} ${windowsHomedir}/.claude/settings.json
    '';
  };
}
