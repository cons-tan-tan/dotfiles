let
  localPackagesOverlay = import ./local-packages.nix {
    inputs = { };
    registry =
      { pkgs, ... }:
      {
        selectedPackageSet = pkgs.marker;
      };
  };
  localPackagesResult = localPackagesOverlay { marker = "final"; } {
    marker = "prev";
    lib = { };
    stdenv.hostPlatform = { };
  };

  llmAgentsOverlay = import ./llm-agents.nix {
    packages = {
      "test-system" = {
        ccusage = "selected-ccusage";
        claude-code = "selected-claude-code";
        codex = "selected-codex";
        ignored = "selected-ignored";
        opencode = "selected-opencode";
        pi = "selected-pi";
      };
      "other-system" = {
        ccusage = "other-ccusage";
        claude-code = "other-claude-code";
        codex = "other-codex";
        opencode = "other-opencode";
        pi = "other-pi";
      };
    };
  };
  llmAgentsResult = llmAgentsOverlay { marker = "final"; } {
    stdenv.hostPlatform.system = "test-system";
  };

  mozukuOverlay = import ./mozuku-lsp.nix {
    inputs.mozuku.packages = {
      "test-system".default = "selected-mozuku";
      "other-system".default = "other-mozuku";
    };
  };
  mozukuResult = mozukuOverlay { marker = "final"; } {
    stdenv.hostPlatform.system = "test-system";
  };

  watchexecOverlay = import ./watchexec.nix {
    pin = {
      version = "1.2.3";
      assets.aarch64-darwin = {
        target = "aarch64-apple-darwin";
        hash = "sha256-test";
      };
    };
  };
  watchexecResult = watchexecOverlay { marker = "final"; } {
    lib = {
      optionalAttrs = condition: attrs: if condition then attrs else { };
      sourceTypes.binaryNativeCode = "binary";
    };
    stdenv.hostPlatform = {
      system = "aarch64-darwin";
      isDarwin = true;
    };
    stdenvNoCC.mkDerivation = attrs: attrs;
    fetchurl = attrs: attrs;
    watchexec.meta.origin = "prev";
  };
in
{
  testLocalPackagesOnlyExposeNamespace = {
    expr = builtins.attrNames localPackagesResult;
    expected = [ "dotfilesPackages" ];
  };

  testLocalPackagesUseFinalPackageSet = {
    expr = localPackagesResult.dotfilesPackages.selectedPackageSet;
    expected = "final";
  };

  testLlmAgentsOnlyExposeBridgedPackages = {
    expr = builtins.attrNames llmAgentsResult;
    expected = [
      "ccusage"
      "claude-code"
      "codex"
      "opencode"
      "pi"
    ];
  };

  testLlmAgentsUseHostSystemPackages = {
    expr = llmAgentsResult;
    expected = {
      ccusage = "selected-ccusage";
      claude-code = "selected-claude-code";
      codex = "selected-codex";
      opencode = "selected-opencode";
      pi = "selected-pi";
    };
  };

  testMozukuOnlyExposesLspPackage = {
    expr = builtins.attrNames mozukuResult;
    expected = [ "mozuku-lsp" ];
  };

  testMozukuUsesHostSystemPackage = {
    expr = mozukuResult.mozuku-lsp;
    expected = "selected-mozuku";
  };

  testWatchexecDerivesMetadataFromPreviousPackage = {
    expr = watchexecResult.watchexec.meta.origin;
    expected = "prev";
  };

  testWatchexecUsesPinnedReleaseAsset = {
    expr = watchexecResult.watchexec.src.url;
    expected = "https://github.com/watchexec/watchexec/releases/download/v1.2.3/watchexec-1.2.3-aarch64-apple-darwin.tar.xz";
  };
}
