{ hostKind }:
{
  isDarwin = hostKind == "darwin";
  isLinux = hostKind == "linux";
  isWsl = hostKind == "wsl";
  isWindows = hostKind == "windows";

  isPosix = hostKind != "windows";
  hasWindowsCompanion = hostKind == "wsl";
}
