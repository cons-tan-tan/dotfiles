# coding agentへ投影するcommand allowと共通guard policyのSSOT。
let
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
      trash = true;
      trash-put = true;
      trash-list = true;
      trash-empty = false;
      trash-rm = false;

      rm = {
        decision = true;
        guidance = trashGuidance;
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
              trashGuidance
            ];
          }
        ];
      };

      fd = {
        decision = true;
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

      trash-restore = {
        decision = true;
        optionSyntax = {
          # argparse also accepts unique long-option abbreviations for these.
          valueTaking = [
            "--p"
            "--pr"
            "--pri"
            "--prin"
            "--print"
            "--print-"
            "--print-c"
            "--print-co"
            "--print-com"
            "--print-comp"
            "--print-compl"
            "--print-comple"
            "--print-complet"
            "--print-completi"
            "--print-completio"
            "--print-completion"
            "--s"
            "--so"
            "--sor"
            "--sort"
            "--t"
            "--tr"
            "--tra"
            "--tras"
            "--trash"
            "--trash-"
            "--trash-d"
            "--trash-di"
            "--trash-dir"
          ];
          optionalEquals = [ ];
        };
        deny = [
          {
            # trash-cli's argparse accepts every unique long-option abbreviation.
            when.options.all = [
              [
                "--o"
                "--ov"
                "--ove"
                "--over"
                "--overw"
                "--overwr"
                "--overwri"
                "--overwrit"
                "--overwrite"
              ]
            ];
            reason = "Overwriting an existing path during trash restore is disabled for coding agents.";
            alternatives = [ "Restore only when the original path does not exist." ];
          }
        ];
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
