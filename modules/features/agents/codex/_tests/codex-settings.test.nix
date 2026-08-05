let
  trashDirectory = "/home/test/.local/share/Trash";
  settings = (import ../_lib/settings.nix).mkMergePayload {
    codexHome = "/home/test/.codex";
    inherit trashDirectory;
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
      dataDirectory = settings.permissions.local-dev.filesystem ? "/home/test/.local/share";
    };
    expected = {
      trash = "write";
      dataDirectory = false;
    };
  };
}
