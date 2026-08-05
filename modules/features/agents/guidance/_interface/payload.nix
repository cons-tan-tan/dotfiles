let
  contextRoot = ../_data/context;
  repositoryRelative = rec {
    contextRoot = "modules/features/agents/guidance/_data/context";
    globalContext = "${contextRoot}/global.md";
  };
in
{
  inherit contextRoot repositoryRelative;
  globalContext = contextRoot + "/global.md";
  rulesDirectory = contextRoot + "/rules";
}
