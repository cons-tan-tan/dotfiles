# coding agentと共通wrapperへ投影するコマンド権限ポリシーの宣言。
# ruleを追加・変更するときはこのファイルだけを編集する。
{
  agentCommandPolicy.rules = [
    {
      match.commands = [
        "rg"
        "bat"
        "eza"
        "jq"
        "fd"
        "ast-grep"
      ];
      decision = "allow";
      justification = "Local inspection commands are auto-approved by the shared policy.";
    }

    {
      match.argvGroups.gh = {
        issue = [
          "list"
          "view"
        ];
        pr = [
          "list"
          "view"
          "diff"
          "checks"
        ];
        run = [
          "list"
          "view"
        ];
        repo = [ "view" ];
        search = [ ];
      };
      decision = "allow";
      justification = "Read-only GitHub operations are auto-approved.";
    }

    {
      match = {
        commands = [ "curl-fetch" ];
        argvGroups.gh."api-get" = [ ];
      };
      decision = "allow";
      justification = "Managed wrappers restrict network operations to read-only requests.";
    }

    {
      match.argvGroups.rm."-rf" = [ ];
      decision = "forbidden";
      justification = "The literal rm -rf argv prefix is forbidden.";
    }

    {
      match.commandOptions.fd = [
        "--exec"
        "--exec-batch"
        "-x"
        "-X"
      ];
      decision = "forbidden";
      justification = "fd must not execute commands for search results.";
    }
  ];
}
