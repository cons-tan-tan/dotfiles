# coding agentと共通wrapperへ投影するコマンド権限ポリシーの宣言。
# argvではtrueがallow、falseがforbidden、未記述はagentのdefault decisionに委ねる。
# optionsはagentの文字列matcherで安全に表現できない拒否条件をfalseで宣言する。
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
      rm."-rf" = false;
    };

    options.fd = {
      "--exec" = false;
      "--exec-batch" = false;
      "-x" = false;
      "-X" = false;
    };
  };
}
