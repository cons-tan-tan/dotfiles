{
  fetchFromGitHub,
  lib,
  rustPlatform,
  zizmor,
}:
let
  version = "1.29.0";
  src = fetchFromGitHub {
    owner = "zizmorcore";
    repo = "zizmor";
    tag = "v${version}";
    hash = "sha256-2I4RvLsAzsq8HMCiXeG2IrZ9fRvr/VIGCw9qKQ5NHlA=";
  };
in
if lib.versionAtLeast zizmor.version version then
  zizmor
else
  zizmor.overrideAttrs (previous: {
    inherit src version;
    cargoDeps = rustPlatform.fetchCargoVendor {
      inherit src;
      hash = "sha256-B8TMVvNWKdGUqXWBZ4900alkItj8tIikKFEv8cbpEVw=";
    };
    meta = previous.meta // {
      changelog = "https://github.com/zizmorcore/zizmor/releases/tag/v${version}";
    };
  })
