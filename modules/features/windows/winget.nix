{ ... }:
{
  features.windows-winget = {
    name = "feature/windows/winget";
    windows.dotfiles.windows.wingetEnabled = true;
    homeManager =
      {
        cli-tools,
        config,
        lib,
        pkgs,
        ...
      }:
      let
        aggregated = import ../packages/_lib/aggregate-cli-tools.nix { inherit lib pkgs; } cli-tools;
        mkPackage =
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
            // lib.optionalAttrs (source == "winget") { useLatest = true; };
          }
          // lib.optionalAttrs (dependsOn != [ ]) { inherit dependsOn; };
        packages = map (entry: mkPackage ({ inherit (entry) id; } // entry.winget)) aggregated.winget;
        yaml = pkgs.formats.yaml { };
        raw = yaml.generate "dev-raw.winget" {
          properties = {
            assertions = [
              {
                resource = "Microsoft.Windows.Developer/OsVersion";
                directives = {
                  description = "Win11 22H2 or later";
                  allowPrerelease = true;
                };
                settings.MinVersion = "10.0.22621";
              }
            ];
            resources = packages;
            configurationVersion = "0.2.0";
          };
        };
        source = pkgs.runCommand "dev.winget" { rawYaml = raw; } ''
          {
            echo '# yaml-language-server: $schema=https://aka.ms/configuration-dsc-schema/0.2'
            cat "$rawYaml"
          } > "$out"
        '';
      in
      {
        config = lib.mkIf config.dotfiles.platform.windows.enable {
          dotfiles.windows.deployments.winget = {
            directories = [ ".config" ];
            files = [
              {
                source = toString source;
                destination = ".config/dev.winget";
              }
            ];
          };
        };
      };
  };
}
