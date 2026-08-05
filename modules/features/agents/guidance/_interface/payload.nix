let
  contextRoot = ../../../../../agents/context;
  repositoryRelative = rec {
    contextRoot = "agents/context";
    globalContext = "${contextRoot}/global.md";
  };
in
{
  inherit contextRoot repositoryRelative;
  globalContext = contextRoot + "/global.md";
  rulesDirectory = contextRoot + "/rules";
}
