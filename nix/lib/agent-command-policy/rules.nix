# coding agentへ投影するcommand allowと共通guard policyのSSOT。
{ lib, ... }:
let
  profiles = import ./command-profiles.nix { inherit lib; };
  inherit (import ./rule-dsl.nix { inherit lib; }) guarded;
  trashGuidance = "Use `trash` instead of `rm`.";
in
{
  agentCommandPolicy = {
    commands = {
      rg = true;
      bat = true;
      eza = true;
      jq = true;
      ast-grep = true;
      git = {
        clone = true;
        commit = true;
      };

      gh = {
        issue = {
          list = true;
          view = true;
        };
        pr = {
          list = true;
          view = true;
          diff = true;
          checks = true;
        };
        run = {
          list = true;
          view = true;
        };
        repo = {
          clone = true;
          read-dir = true;
          read-file = true;
          view = true;
        };
        search = true;
        api-get = true;
      };

      curl-fetch = true;
      trash = true;
      trash-put = true;
      trash-list = true;
      trash-empty = false;
      trash-rm = false;

      rm = guarded profiles.rm {
        guidance = trashGuidance;
        deny.recursiveForce = {
          reason = "Recursive forced deletion is disabled for coding agents.";
          alternatives = [ trashGuidance ];
        };
      };

      fd = guarded profiles.fd {
        deny.execution = {
          reason = "fd command execution options are disabled for coding agents.";
          alternatives = [
            "List matching paths first, then run a separately reviewed command."
          ];
        };
      };

      trash-restore = guarded profiles.trashRestore {
        deny.overwrite = {
          reason = "Overwriting an existing path during trash restore is disabled for coding agents.";
          alternatives = [ "Restore only when the original path does not exist." ];
        };
      };
    };

    shell.redirection.emptyFile = false;

    shellfirm = {
      enabled = true;
      minimumSeverity = "High";
      categories = {
        aws = true;
        docker = true;
        fs = true;
        gcp = true;
        git = true;
        github = true;
        kubernetes = true;
        network = true;
        npm = true;
        shell = true;
      };
      ruleNamespaces = {
        fs-strict = false;
        git-strict = false;
        kubernetes-strict = false;
      };
      rules.fs.flush_file_content = false;
    };
  };
}
