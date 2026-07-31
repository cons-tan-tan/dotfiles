let
  settings = (import ./codex.nix).mkMergePayload {
    codexHome = "/home/test/.codex";
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
}
