{
  # CLI pin と agent skill source は update-pins が同じ release へ揃える。
  flake-file.inputs.hcom-src = {
    url = "github:aannoo/hcom/v0.7.21";
    flake = false;
  };
}
