{ inputs, ... }:
{
  flake-file.inputs.imozuru = {
    url = "github:MaryCache/imozuru";
    flake = false;
  };

  flake.modules.homeManager.agent-imozuru = {
    key = "modules/features/agents/imozuru.nix#homeManager.agent-imozuru";
    imports = [
      (
        { pkgs, ... }:
        {
          # The stdlib-only scripts run through uv per the agent Python rule.
          # They probe these tools as optional PDF, OCR, and subtitle backends.
          home.packages = [
            pkgs.poppler-utils
            # The default tessdata bundles every language; keep only those the
            # OCR fallback selects.
            (pkgs.tesseract.override {
              enableLanguages = [
                "eng"
                "jpn"
                "jpn_vert"
              ];
            })
            pkgs.yt-dlp
          ];
        }
      )
    ];
    dotfiles.agentSkillContributions = [
      {
        name = "imozuru";
        provenance = "external";
        definition.root = inputs.imozuru.outPath + "/skills/imozuru";
      }
    ];
  };
}
