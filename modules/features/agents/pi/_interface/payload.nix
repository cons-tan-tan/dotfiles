let
  extensionsRoot = ../../../../../pi/extensions;
in
{
  inherit extensionsRoot;
  agentCommandGuard = extensionsRoot + "/agent-command-guard.ts";
  herdrSkillLoader = extensionsRoot + "/herdr-skill-loader.ts";
  repositoryRelative.extensionsRoot = "pi/extensions";
}
