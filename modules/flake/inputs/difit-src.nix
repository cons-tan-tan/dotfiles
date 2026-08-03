{
  # CLI pin と agent skill source は update-pins が同じ release へ揃える。
  flake-file.inputs.difit-src = {
    url = "github:yoshiko-pg/difit/v5.0.8";
    flake = false;
  };
}
