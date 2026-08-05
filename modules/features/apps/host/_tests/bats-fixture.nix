{
  lib,
  pkgs,
  publicApps,
}:
let
  isLinux = pkgs.stdenv.hostPlatform.isLinux;
  expectedArch = if pkgs.stdenv.hostPlatform.isx86_64 then "x86_64" else "aarch64";
in
{
  nativeBuildInputs = [ ];
  environment = {
    HOST_APP_KIND = if pkgs.stdenv.hostPlatform.isDarwin then "darwin" else "linux-host";
    HOST_BUILD_PUBLIC_BIN = publicApps.build.program;
    HOST_EXPECTED_HM_LINUX = "constantan@linux-${expectedArch}";
    HOST_EXPECTED_HM_WSL = "constantan@wsl-${expectedArch}";
    HOST_EXPECTED_NIXOS_WSL = if pkgs.stdenv.hostPlatform.isx86_64 then "wsl" else "wsl-aarch64";
    HOST_SWITCH_PUBLIC_BIN = publicApps.switch.program;
  }
  // lib.optionalAttrs isLinux {
    APPLY_WINGET_EXPECTED_WINDOWS_HOMEDIR = "/mnt/c/Users/zhouc";
    APPLY_WINGET_PUBLIC_BIN = publicApps.apply-winget.program;
  };
  requiredEnvironment = [
    "HOST_APP_KIND"
    "HOST_BUILD_PUBLIC_BIN"
    "HOST_EXPECTED_HM_LINUX"
    "HOST_EXPECTED_HM_WSL"
    "HOST_EXPECTED_NIXOS_WSL"
    "HOST_SWITCH_PUBLIC_BIN"
  ]
  ++ lib.optionals isLinux [
    "APPLY_WINGET_EXPECTED_WINDOWS_HOMEDIR"
    "APPLY_WINGET_PUBLIC_BIN"
  ];
}
