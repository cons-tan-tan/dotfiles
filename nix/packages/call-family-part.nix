# callPackage が自動付与する override / overrideDerivation を剥がす。
# family の attrset は package-families.test.nix が attrNames を固定する
# 純データ契約なので、合成用の synthetic attr を混ぜない。
{ callPackage }:
path: args:
builtins.removeAttrs (callPackage path args) [
  "override"
  "overrideDerivation"
]
