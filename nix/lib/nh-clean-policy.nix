{
  dates = "*-*-* 00/6:00:00";
  arguments = [
    "--keep"
    "5"
    "--keep-since"
    "1d"
    "--no-gcroots"
    "--no-direnv"
  ];

  growth = {
    checkInterval = "5m";
    maximumAgeSeconds = 6 * 60 * 60;
    queryTimeout = "2m";
    retryIntervalSeconds = 30 * 60;
    thresholdBytes = 32 * 1024 * 1024 * 1024;
    stateDirectory = "nix-store-growth-checker";
  };

  resultRoots = {
    dates = "Sun *-*-* 03:00:00";
    keepMinutes = 10080;
  };
}
