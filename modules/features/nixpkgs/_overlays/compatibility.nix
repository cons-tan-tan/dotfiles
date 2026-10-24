_final: prev: {
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
