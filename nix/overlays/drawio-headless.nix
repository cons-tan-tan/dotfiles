_final: prev: {
  drawio-headless = prev.callPackage ../packages/drawio-headless {
    inherit (prev) coreutils gnugrep;
  };
}
