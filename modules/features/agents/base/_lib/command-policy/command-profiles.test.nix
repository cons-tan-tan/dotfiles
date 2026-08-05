# command profileがCLI固有のoption grammarをpolicy本文から分離できることを確認する。
{ lib }:
let
  profiles = import ./command-profiles.nix { inherit lib; };
  ambiguous = profiles.mkAbbreviatedLongOptionProfile {
    options = [
      "--force"
      "--format"
    ];
    valueTaking = [ "--force" ];
    conditions.force = [ { options = [ "--force" ]; } ];
  };
  canonicalPrefix = profiles.mkAbbreviatedLongOptionProfile {
    options = [
      "--foo"
      "--foobar"
    ];
    valueTaking = [ "--foo" ];
    conditions.foo = [ { options = [ "--foo" ]; } ];
  };
in
{
  testFdProfilePreservesOptionArityAndExecutionCondition = {
    expr = {
      valueTakingCount = builtins.length profiles.fd.optionSyntax.valueTaking;
      consumesExcludeValue = lib.elem "-E" profiles.fd.optionSyntax.valueTaking;
      consumesBaseDirectoryValue = lib.elem "--base-directory" profiles.fd.optionSyntax.valueTaking;
      execution = profiles.fd.conditions.execution;
    };
    expected = {
      valueTakingCount = 35;
      consumesExcludeValue = true;
      consumesBaseDirectoryValue = true;
      execution = [
        [
          "-x"
          "-X"
          "--exec"
          "--exec-batch"
        ]
      ];
    };
  };

  testRmProfileCoversGetoptLongAbbreviations = {
    expr = {
      recursive = builtins.elemAt profiles.rm.conditions.recursiveForce 0;
      force = builtins.elemAt profiles.rm.conditions.recursiveForce 1;
      optionalValues = profiles.rm.optionSyntax.optionalEquals;
    };
    expected = {
      recursive = [
        "-r"
        "-R"
        "--r"
        "--re"
        "--rec"
        "--recu"
        "--recur"
        "--recurs"
        "--recursi"
        "--recursiv"
        "--recursive"
      ];
      force = [
        "-f"
        "--f"
        "--fo"
        "--for"
        "--forc"
        "--force"
      ];
      optionalValues = [
        "--i"
        "--in"
        "--int"
        "--inte"
        "--inter"
        "--intera"
        "--interac"
        "--interact"
        "--interacti"
        "--interactiv"
        "--interactive"
        "--prese"
        "--preser"
        "--preserv"
        "--preserve"
        "--preserve-"
        "--preserve-r"
        "--preserve-ro"
        "--preserve-roo"
        "--preserve-root"
      ];
    };
  };

  testAbbreviatedLongOptionProfileGeneratesOnlyUniqueAbbreviations = {
    expr = {
      forceValueAliases = ambiguous.optionSyntax.valueTaking;
      forceConditionAliases = builtins.head ambiguous.conditions.force;
    };
    expected = {
      forceValueAliases = [
        "--forc"
        "--force"
      ];
      forceConditionAliases = [
        "--forc"
        "--force"
      ];
    };
  };

  testAbbreviatedLongOptionProfilePreservesCanonicalPrefix = {
    expr = {
      valueAliases = canonicalPrefix.optionSyntax.valueTaking;
      conditionAliases = builtins.head canonicalPrefix.conditions.foo;
    };
    expected = {
      valueAliases = [ "--foo" ];
      conditionAliases = [ "--foo" ];
    };
  };

  testTrashRestoreProfileGeneratesArgparseAliases = {
    expr = {
      valueTakingCount = builtins.length profiles.trashRestore.optionSyntax.valueTaking;
      valueTakingStarts = lib.take 4 profiles.trashRestore.optionSyntax.valueTaking;
      valueTakingCanonical =
        lib.all (option: lib.elem option profiles.trashRestore.optionSyntax.valueTaking)
          [
            "--print-completion"
            "--sort"
            "--trash-dir"
          ];
      overwrite = builtins.head profiles.trashRestore.conditions.overwrite;
    };
    expected = {
      valueTakingCount = 29;
      valueTakingStarts = [
        "--p"
        "--pr"
        "--pri"
        "--prin"
      ];
      valueTakingCanonical = true;
      overwrite = [
        "--o"
        "--ov"
        "--ove"
        "--over"
        "--overw"
        "--overwr"
        "--overwri"
        "--overwrit"
        "--overwrite"
      ];
    };
  };
}
