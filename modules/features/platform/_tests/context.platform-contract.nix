{
  darwin,
  integratedWsl,
  standaloneLinux,
  standaloneWsl,
}:
let
  describe = config: {
    inherit (config.dotfiles.platform)
      environment
      standalone
      windows
      ;
  };
in
{
  actual = {
    linux = describe standaloneLinux;
    standaloneWsl = describe standaloneWsl;
    integratedWsl = describe integratedWsl;
    darwin = describe darwin;
  };
  expected = {
    linux = {
      environment = "linux";
      standalone = true;
      windows = {
        enable = false;
        username = null;
        homedir = null;
      };
    };
    standaloneWsl = {
      environment = "wsl";
      standalone = true;
      windows = {
        enable = true;
        username = "zhouc";
        homedir = "/mnt/c/Users/zhouc";
      };
    };
    integratedWsl = {
      environment = "wsl";
      standalone = false;
      windows = {
        enable = true;
        username = "zhouc";
        homedir = "/mnt/c/Users/zhouc";
      };
    };
    darwin = {
      environment = "darwin";
      standalone = false;
      windows = {
        enable = false;
        username = null;
        homedir = null;
      };
    };
  };
}
