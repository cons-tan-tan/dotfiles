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
}
