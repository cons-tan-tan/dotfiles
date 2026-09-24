{ flake }:
let
  home = flake.homeConfigurations."constantan@linux-x86_64".config;
  trashDirectory = "${home.xdg.dataHome}/Trash";
  settings = (import ../_lib/merge-payload.nix) {
    codexHome = "/home/test/.codex";
    settings = home.dotfiles.codex.settings;
  };
in
{
  testManagedHookTrustStateIsAlwaysReplaced = {
    expr = settings.__delete_prefixes;
    expected = [
      {
        path = [
          "hooks"
          "state"
        ];
        prefix = "/home/test/.codex/hooks.json:";
      }
    ];
  };

  testTrashIsWritableWithoutOpeningTheWholeDataDirectory = {
    expr = {
      trash = settings.permissions.local-dev.filesystem.${trashDirectory};
      dataDirectory = builtins.hasAttr home.xdg.dataHome settings.permissions.local-dev.filesystem;
    };
    expected = {
      trash = "write";
      dataDirectory = false;
    };
  };
}
