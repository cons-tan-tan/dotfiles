{
  lib,
  go,
  fetchurl,
}:
let
  release =
    if lib.versionAtLeast go.version "1.27" then
      {
        version = "1.27.3";
        hash = "sha256-bndJA1zzYPBrJXXRYup535/ajvZxiJ5cN1+OUHd/Jrs=";
      }
    else
      {
        version = "1.26.10";
        hash = "sha256-/WPog7ovK/ypPBZGsx6+9j4rHk0rMXyXidl2po2B828=";
      };
in
# Keep the SDK backport local: overriding the build-time compiler also rebuilds
# Chromium. Go's default verifier uses the CA store protected by the NixOS update.
# https://github.com/NixOS/nixpkgs/issues/576485
if lib.versionOlder go.version release.version then
  go.overrideAttrs {
    inherit (release) version;
    src = fetchurl {
      url = "https://go.dev/dl/go${release.version}.src.tar.gz";
      inherit (release) hash;
    };
  }
else
  go
