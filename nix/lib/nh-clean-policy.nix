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

  resultRoots = {
    dates = "Sun *-*-* 03:00:00";
    keepMinutes = 10080;
  };
}
