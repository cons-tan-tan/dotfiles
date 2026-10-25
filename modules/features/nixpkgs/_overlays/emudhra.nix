# Temporary release updates while the pinned channels catch up with the
# eMudhra and Brotli fixes. Version guards retire each override automatically.
# https://github.com/NixOS/nixpkgs/issues/576485
_final: prev:
let
  inherit (prev) lib;
in
{
  # Bun embeds both its CA bundle and Brotli; system libraries do not replace them.
  # https://bun.com/blog/bun-v1.4.4
  bun =
    if lib.versionOlder prev.bun.version "1.4.4" then
      prev.bun.overrideAttrs (
        finalAttrs: old: {
          version = "1.4.4";
          src = finalAttrs.passthru.sources.${prev.stdenv.hostPlatform.system};
          passthru = old.passthru // {
            sources =
              lib.mapAttrs
                (
                  _system: asset:
                  prev.fetchurl {
                    url = "https://github.com/oven-sh/bun/releases/download/bun-v${finalAttrs.version}/${asset.name}.zip";
                    inherit (asset) hash;
                  }
                )
                {
                  aarch64-darwin = {
                    name = "bun-darwin-aarch64";
                    hash = "sha256-wkDX8My5DCY6hJ/NsJt+5iYw2SE0jtaq/ahrnVd7xRA=";
                  };
                  aarch64-linux = {
                    name = "bun-linux-aarch64";
                    hash = "sha256-uqa7NvUdblhWHgK76oJQOKnfRU9nPW13bou/hvjHhQ4=";
                  };
                  x86_64-linux = {
                    name = "bun-linux-x64-baseline";
                    hash = "sha256-4ERutVmVdy65iUvrrppr42jZhai5Jx7hJEhvmUbu3XY=";
                  };
                };
          };
        }
      )
    else
      prev.bun;

  # Rustup also carries fallback roots, so updating only the OS store is insufficient.
  # https://blog.rust-lang.org/2026/10/20/Rustup-1.29.2/
  rustup =
    if lib.versionOlder prev.rustup.version "1.29.2" then
      prev.rustup.overrideAttrs (
        finalAttrs: old: {
          version = "1.29.2";
          src = prev.fetchFromGitHub {
            owner = "rust-lang";
            repo = "rustup";
            tag = "1.29.2";
            hash = "sha256-vtfZNMkUAmbdXv0sv7wdm62AjCkYJY188jLx8RrmO2M=";
          };
          cargoHash = "sha256-UL6nS3SbxKXFWftJLeFY622VQEyAimhNz+YJgZsLHJc=";
          cargoDeps = prev.rustPlatform.fetchCargoVendor {
            inherit (finalAttrs) src;
            name = "rustup-${finalAttrs.version}";
            hash = finalAttrs.cargoHash;
          };
          # The SOCKS test can connect before its background thread binds the listener.
          patches = (old.patches or [ ]) ++ [ ./rustup-test-listener.patch ];
        }
      )
    else
      prev.rustup;

  # uv embeds its own roots; the OS bundle update does not replace them.
  # 0.13.5 also rejects the compromised intermediate keys and refreshes managed Python.
  # https://github.com/astral-sh/uv/releases/tag/0.13.5
  uv =
    if lib.versionOlder prev.uv.version "0.13.5" then
      prev.uv.overrideAttrs (
        finalAttrs: _old: {
          version = "0.13.5";
          src = prev.fetchFromGitHub {
            owner = "astral-sh";
            repo = "uv";
            tag = finalAttrs.version;
            hash = "sha256-SXTusm2EJ49tk03c3vSHcZp3AtAuj9SGOzsMwpnjXDw=";
          };
          cargoHash = "sha256-spQmSFAjNs6pWnw2nd/d3ZysIMK9j+BjDjrwcnUCmWw=";
          cargoDeps = prev.rustPlatform.fetchCargoVendor {
            inherit (finalAttrs) src;
            name = "uv-${finalAttrs.version}";
            hash = finalAttrs.cargoHash;
          };
        }
      )
    else
      prev.uv;
}
