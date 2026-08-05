{ }:
{
  describe =
    target:
    let
      inherit (target) config pkgs;
      hasPackage = package: builtins.elem package config.home.packages;
    in
    builtins.all hasPackage (
      with pkgs;
      [
        ast-grep
        bat
        eza
        fd
        fzf
        jq
        reuse
        ripgrep
      ]
    );
  expected = _: true;
}
