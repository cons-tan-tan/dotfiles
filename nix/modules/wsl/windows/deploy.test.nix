{ lib }:
let
  fixtureLib = lib // {
    hm.dag.entryAfter = after: data: { inherit after data; };
  };
  deploy = import ./deploy.nix { lib = fixtureLib; };
  activation = deploy.mkDeployActivation {
    dirs = [
      "/mnt/c/Users/test/.config"
      "/mnt/c/Users/test/.local/share"
    ];
    files = [
      {
        src = "/nix/store/source-a";
        dst = "/mnt/c/Users/test/.config/a";
      }
      {
        src = "/nix/store/source-b";
        dst = "/mnt/c/Users/test/.local/share/b";
      }
    ];
  };
  staticModule = import ./static.nix {
    lib = fixtureLib;
    pkgs.rsync = "/nix/store/rsync";
    config.my = {
      dotfilesDir = "/repo";
      windows.homedir = "/mnt/c/Users/test";
    };
  };
  staticActivation = staticModule.home.activation.deployWindowsClaudeStatic;
in
{
  testCreatesWriteBoundaryActivation = {
    expr = activation.after;
    expected = [ "writeBoundary" ];
  };

  testRendersDirectoriesAndFiles = {
    expr = activation.data;
    expected = ''
      run mkdir -p "/mnt/c/Users/test/.config" "/mnt/c/Users/test/.local/share"
      run install -m644 "/nix/store/source-a" "/mnt/c/Users/test/.config/a"
      run install -m644 "/nix/store/source-b" "/mnt/c/Users/test/.local/share/b"
    '';
  };

  testStaticSkillSyncExcludesLinuxOnlyAx = {
    expr = {
      inherit (staticActivation) after;
      axExcludeCount = builtins.length (lib.splitString "--exclude=ax/" staticActivation.data) - 1;
      deletesExcludedSkills =
        builtins.length (lib.splitString "--delete --delete-excluded --exclude=ax/" staticActivation.data)
        - 1;
    };
    expected = {
      after = [ "linkGeneration" ];
      axExcludeCount = 2;
      deletesExcludedSkills = 2;
    };
  };
}
