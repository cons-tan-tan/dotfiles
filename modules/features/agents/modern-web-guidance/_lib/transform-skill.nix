{ lib, original, ... }:
let
  sections = lib.splitString "\n## " original;
  isRunnerSection =
    section:
    builtins.elem (builtins.head (lib.splitString "\n" section)) [
      "Using npx"
      "Using npx / pnpx"
    ];
  runnerSections = builtins.filter isRunnerSection sections;
  localRuntime = ''
    Local runtime

    Run `modern-web-guidance` directly. The CLI, guides, and this skill are
    managed together by Nix. Update their Nix package pin together. Keep the
    supplied --skill-version argument. Do not use this CLI's install, update,
    or uninstall commands to manage this skill.
  '';
  withRuntime = lib.concatStringsSep "\n## " (
    map (section: if isRunnerSection section then localRuntime else section) sections
  );
  rendered =
    builtins.replaceStrings
      [
        "npx -y modern-web-guidance@latest"
        "pnpx modern-web-guidance@latest"
        " with `npx`"
      ]
      [ "modern-web-guidance" "modern-web-guidance" "" ]
      withRuntime;
in
# Match semantic anchors rather than surrounding prose or invocation counts.
# A changed runner contract must fail the update instead of falling back to npm.
assert lib.assertMsg (
  builtins.length runnerSections == 1
) "modern-web-guidance: review changed upstream runner section";
assert lib.assertMsg (lib.hasInfix "npx -y modern-web-guidance@latest" original)
  "modern-web-guidance: review changed upstream invocation";
assert lib.assertMsg (
  !lib.any (text: lib.hasInfix text rendered) [
    "npx"
    "pnpx"
    "pnpm dlx"
    "npm exec"
    "modern-web-guidance@"
  ]
) "modern-web-guidance: unhandled package runner remains";
rendered
