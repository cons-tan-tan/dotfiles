{ lib }:
{
  describe =
    target:
    let
      inherit (target) config;
      sshenc = lib.findFirst (package: lib.getName package == "sshenc") null config.home.packages;
    in
    {
      signing = {
        inherit (config.programs.git.signing)
          format
          key
          signByDefault
          ;
        sshencSigner = sshenc != null && config.programs.git.signing.signer == "${sshenc}/bin/sshenc";
      };
    };
  expected = facts: {
    signing =
      if facts.environment == "wsl" && !facts.standalone then
        {
          format = "ssh";
          key = "~/.ssh/git-signing.pub";
          signByDefault = true;
          sshencSigner = true;
        }
      else
        {
          format = "openpgp";
          key = "6250E02A31E09AFE";
          signByDefault = true;
          sshencSigner = false;
        };
  };
}
