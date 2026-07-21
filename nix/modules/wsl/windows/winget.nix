# Windows companion: WinGet DSC 構成 (dev.winget) を書き出す。
#
# 適用は 2 段階フロー:
#   1. `nix run .#switch`       — この activation が dev.winget を Windows 側へ配置
#   2. `nix run .#apply-winget` — WSL から winget.exe configure を起動して適用
# switch だけでは Windows 側のパッケージは変わらない点に注意。
#
# バージョンは useLatest 運用でピン留めしない: ピンすると手動でのバージョン
# 追従が必要になり、保守コストが利点を上回るため。
{
  config,
  pkgs,
  lib,
  ...
}:
let
  windowsHomedir = config.my.windows.homedir;

  yamlFormat = pkgs.formats.yaml { };

  mkWinGetPackage =
    {
      id,
      packageId,
      source ? "winget",
      dependsOn ? [ ],
      elevated ? false,
      description ? null,
    }:
    {
      resource = "Microsoft.WinGet.DSC/WinGetPackage";
      inherit id;
      directives =
        lib.optionalAttrs (description != null) { inherit description; }
        // lib.optionalAttrs elevated { securityContext = "elevated"; };
      settings = {
        id = packageId;
        inherit source;
      }
      // lib.optionalAttrs (source == "winget") {
        useLatest = true;
      };
    }
    // lib.optionalAttrs (dependsOn != [ ]) { inherit dependsOn; };

  cliTools = import ../../../lib/settings/cli-tools.nix;
  packages = map (tool: mkWinGetPackage tool.winget) cliTools;

  wingetConfig = {
    properties = {
      assertions = [
        {
          resource = "Microsoft.Windows.Developer/OsVersion";
          directives = {
            description = "Win11 22H2 or later";
            allowPrerelease = true;
          };
          settings = {
            MinVersion = "10.0.22621";
          };
        }
      ];
      resources = packages;
      configurationVersion = "0.2.0";
    };
  };

  # pkgs.formats.yaml does not preserve top-level comments; prepend the
  # language-server schema directive so editors get completion.
  wingetConfigFile =
    pkgs.runCommand "dev.winget"
      {
        rawYaml = yamlFormat.generate "dev-raw.winget" wingetConfig;
      }
      ''
        {
          echo '# yaml-language-server: $schema=https://aka.ms/configuration-dsc-schema/0.2'
          cat $rawYaml
        } > $out
      '';
in
{
  home.activation.deployWingetConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run mkdir -p "${windowsHomedir}/.config"
    run install -m644 "${wingetConfigFile}" "${windowsHomedir}/.config/dev.winget"
  '';
}
