{
  arguments,
  lib,
  original,
  ...
}:
let
  introduction = "Create small, independently revertible Conventional Commits.";
  granularity = "2. Review relevant history and split the changes into the smallest independently revertible units. Briefly explain non-obvious commit boundaries. Keep unrelated changes out of the commit. For moves or extractions, include both sides and update references.";
  granularityStep = lib.concatStringsSep "\n" (
    lib.imap0 (
      index: line:
      if index == 0 then
        "2. ${line}"
      else if line == "" then
        ""
      else
        "   ${line}"
    ) (lib.splitString "\n" (lib.removeSuffix "\n" arguments.granularity))
  );
  replaceOnce =
    from: to: text:
    assert lib.assertMsg (
      builtins.length (lib.splitString from text) == 2
    ) "commit profile: expected exactly one granularity anchor; review the base skill change";
    builtins.replaceStrings [ from ] [ to ] text;
in
replaceOnce granularity granularityStep (
  replaceOnce introduction
    "Create small Conventional Commits for meaningful, reviewable stages of a completed change series."
    original
)
