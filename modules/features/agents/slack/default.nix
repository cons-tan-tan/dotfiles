{ inputs, ... }:
{
  flake-file.inputs.agent-slack-skill = {
    url = "github:stablyai/agent-slack/v0.9.3";
    flake = false;
  };

  features.agent-slack = {
    name = "feature/agents/slack";
    agent-skills = [
      {
        name = "agent-slack";
        provenance = "external";
        definition = {
          root = inputs.agent-slack-skill.outPath + "/skills/agent-slack";
          customization.frontmatter.description = ''
            Slack automation CLI for AI agents. Use when the user asks to read,
            search, send, reply to, edit, delete, or react to Slack messages;
            inspect threads, channels, DMs, unread messages, saved-for-later items,
            files, canvases, users, or workflows; upload local files to Slack; or
            manage channels and conversations.
          '';
        };
      }
    ];
    homeManager = { pkgs, ... }: {
      home.packages = [ pkgs.dotfilesPackages.agent-slack ];
    };
  };
}
