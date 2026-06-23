# LLM agents from llm-agents.nix (https://github.com/numtide/llm-agents.nix)
llm-agents: final: prev:
let
  system = prev.stdenv.hostPlatform.system;
  llm = llm-agents.packages.${system};
  herdrVersionData = builtins.fromJSON (builtins.readFile "${llm-agents}/packages/herdr/hashes.json");
  herdrBinaryAssets = {
    x86_64-linux = "herdr-linux-x86_64";
    aarch64-linux = "herdr-linux-aarch64";
    x86_64-darwin = "herdr-macos-x86_64";
    aarch64-darwin = "herdr-macos-aarch64";
  };
  herdrBinaryHashes = herdrVersionData.binaryHashes // {
    x86_64-linux = "sha256-4Vmg+svgoXzosEGXJNJLuEd9c0XKulFl91lBwSaotLk=";
    aarch64-linux = "sha256-pFpiZTM2PopGiR2Ab7wksJBKY9ZfheO0TJPMwBJBDSE=";
  };
in
{
  inherit (llm)
    codex
    claude-code
    opencode
    pi
    ccusage
    agent-browser
    ;

  # llm-agents.nix builds Herdr from source on Linux and imports a generated
  # Zig file from that source path during package evaluation. This binary form
  # keeps our --no-build flake checks pure while tracking llm-agents' version.
  herdr = prev.stdenvNoCC.mkDerivation {
    pname = "herdr";
    version = herdrVersionData.version;

    src = prev.fetchurl {
      url = "https://github.com/ogulcancelik/herdr/releases/download/v${herdrVersionData.version}/${herdrBinaryAssets.${system}}";
      hash = herdrBinaryHashes.${system};
    };

    dontUnpack = true;

    installPhase = ''
      runHook preInstall
      install -Dm755 "$src" "$out/bin/herdr"
      runHook postInstall
    '';

    meta = {
      description = "Terminal workspace manager for AI coding agents";
      homepage = "https://herdr.dev";
      changelog = "https://github.com/ogulcancelik/herdr/releases/tag/v${herdrVersionData.version}";
      license = prev.lib.licenses.agpl3Plus;
      platforms = builtins.attrNames herdrBinaryAssets;
      mainProgram = "herdr";
    };
  };
}
