# coding agentへ投影するcommand allowと共通guard policyのSSOT。
{
  agentCommandPolicy = {
    argv = {
      rg = true;
      bat = true;
      eza = true;
      jq = true;
      fd = true;
      ast-grep = true;

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
        repo.view = true;
        search = true;
        api-get = true;
      };

      curl-fetch = true;
    };

    semantic = {
      rm = {
        optionSyntax = {
          valueTaking = [ ];
          optionalEquals = [ ];
        };
        deny = [
          {
            when.options.all = [
              [
                "-r"
                "-R"
                "--recursive"
              ]
              [
                "-f"
                "--force"
              ]
            ];
            reason = "Recursive forced deletion is disabled for coding agents.";
            alternatives = [
              "Move the target to trash or remove it without recursive force."
            ];
          }
        ];
      };

      fd = {
        optionSyntax = {
          valueTaking = [
            "--and"
            "-d"
            "--max-depth"
            "--min-depth"
            "--exact-depth"
            "-E"
            "--exclude"
            "-t"
            "--type"
            "-e"
            "--extension"
            "-S"
            "--size"
            "--changed-within"
            "--change-newer-than"
            "--newer"
            "--changed-after"
            "--changed-before"
            "--change-older-than"
            "--older"
            "-o"
            "--owner"
            "--format"
            "--batch-size"
            "--ignore-file"
            "-c"
            "--color"
            "--ignore-contain"
            "-j"
            "--threads"
            "--max-results"
            "-C"
            "--base-directory"
            "--path-separator"
            "--search-path"
          ];
          optionalEquals = [
            "--hyperlink"
            "--strip-cwd-prefix"
          ];
        };
        deny = [
          {
            when.options.all = [
              [
                "-x"
                "-X"
                "--exec"
                "--exec-batch"
              ]
            ];
            reason = "fd command execution options are disabled for coding agents.";
            alternatives = [
              "List matching paths first, then run a separately reviewed command."
            ];
          }
        ];
      };
    };

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
      rules = { };
    };
  };
}
