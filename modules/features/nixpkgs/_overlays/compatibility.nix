_final: prev: {
  # gh's go-keyring needs the alias unlocking and MIME parameter fixes in 0.7.
  # Upstream recommends the beta instead of backporting these fixes to 0.6.
  # https://github.com/linux-credentials/oo7/pull/585
  # https://github.com/linux-credentials/oo7/pull/517
  oo7 =
    if prev.oo7.version == "0.6.0" then
      prev.oo7.overrideAttrs {
        version = "0.7.0-beta";
        src = prev.fetchFromGitHub {
          owner = "linux-credentials";
          repo = "oo7";
          tag = "0.7.0.beta";
          hash = "sha256-HdKWP+4A7pJpGRMTIm6ST1H5PZLdbPz2sbTZv5+2LaA=";
        };
        cargoHash = "sha256-X+yNxuVqfOo9uSPx3FZ9RlIg7sQJTK6xNiLgsxENWac=";
      }
    else
      prev.oo7;

  # sphinxHook reads only the first array entry with structuredAttrs enabled,
  # so reuse's declared man output is never created. Keep both builders active.
  # https://github.com/NixOS/nixpkgs/blob/5adc50831c259f87faeb09ddf930d43597197473/pkgs/development/interpreters/python/hooks/sphinx-hook.sh
  reuse =
    if prev.reuse.version == "6.2.0" then
      prev.reuse.overridePythonAttrs {
        sphinxBuilders = "html man";
      }
    else
      prev.reuse;
}
