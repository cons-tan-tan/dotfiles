{
  caseName,
  nixpkgsPath,
  repoRoot,
}:
let
  pkgs = import nixpkgsPath { system = "x86_64-linux"; };
  inherit (pkgs) lib;
  appSet = import (repoRoot + "/modules/features/apps/_interface/app-set.nix") { inherit lib; };
  fixtureScript = pkgs.writeShellApplication {
    name = "fixture-app";
    text = "true";
  };
  customValidation = pkgs.writeText "custom-app-validation" "validated";
  customApp = {
    type = "app";
    meta.description = "Custom fixture application";
    program = "/bin/true";
  };
  fixture = appSet.mkAppSet {
    entries.fixture = {
      description = "Fixture application";
      script = fixtureScript;
    };
  };
  force = value: builtins.deepSeq value true;
  cases = {
    missingCustomValidation = {
      expression = force (
        (appSet.mkAppSet {
          entries.invalid.app = customApp;
        }).apps
      );
      expectedFragment = "custom app entry \"invalid\" must contain an app and exactly one validation derivation";
    };

    mixedShellAndCustomStrategies = {
      expression = force (
        (appSet.mkAppSet {
          entries.invalid = {
            app = customApp;
            description = "Ambiguous fixture";
            script = fixtureScript;
            validation = customValidation;
          };
        }).apps
      );
      expectedFragment = "shell app entry \"invalid\" must contain a non-empty description and script derivation only";
    };

    shellAppWithUnknownField = {
      expression = force (
        (appSet.mkAppSet {
          entries.invalid = {
            description = "Fixture application";
            script = fixtureScript;
            unexpected = true;
          };
        }).apps
      );
      expectedFragment = "shell app entry \"invalid\" must contain a non-empty description and script derivation only";
    };

    shellAppWithEmptyDescription = {
      expression = force (
        (appSet.mkAppSet {
          entries.invalid = {
            description = "";
            script = fixtureScript;
          };
        }).apps
      );
      expectedFragment = "shell app entry \"invalid\" must contain a non-empty description and script derivation only";
    };

    shellAppWithNonDerivationScript = {
      expression = force (
        (appSet.mkAppSet {
          entries.invalid = {
            description = "Fixture application";
            script = "/bin/true";
          };
        }).apps
      );
      expectedFragment = "shell app entry \"invalid\" must contain a non-empty description and script derivation only";
    };

    customAppWithUnknownField = {
      expression = force (
        (appSet.mkAppSet {
          entries.invalid = {
            app = customApp;
            validation = customValidation;
            unexpected = true;
          };
        }).apps
      );
      expectedFragment = "custom app entry \"invalid\" must contain an app and exactly one validation derivation";
    };

    customAppWithNonAttributeApp = {
      expression = force (
        (appSet.mkAppSet {
          entries.invalid = {
            app = "/bin/true";
            validation = customValidation;
          };
        }).apps
      );
      expectedFragment = "custom app entry \"invalid\" must contain an app and exactly one validation derivation";
    };

    customAppWithoutType = {
      expression = force (
        (appSet.mkAppSet {
          entries.invalid = {
            app = removeAttrs customApp [ "type" ];
            validation = customValidation;
          };
        }).apps
      );
      expectedFragment = "custom app entry \"invalid\" must contain an app and exactly one validation derivation";
    };

    customAppWithoutProgram = {
      expression = force (
        (appSet.mkAppSet {
          entries.invalid = {
            app = removeAttrs customApp [ "program" ];
            validation = customValidation;
          };
        }).apps
      );
      expectedFragment = "custom app entry \"invalid\" must contain an app and exactly one validation derivation";
    };

    customAppWithoutMeta = {
      expression = force (
        (appSet.mkAppSet {
          entries.invalid = {
            app = removeAttrs customApp [ "meta" ];
            validation = customValidation;
          };
        }).apps
      );
      expectedFragment = "custom app entry \"invalid\" must contain an app and exactly one validation derivation";
    };

    customAppWithNonDerivationValidation = {
      expression = force (
        (appSet.mkAppSet {
          entries.invalid = {
            app = customApp;
            validation = "/bin/true";
          };
        }).apps
      );
      expectedFragment = "custom app entry \"invalid\" must contain an app and exactly one validation derivation";
    };

    extraAppsBypass = {
      expression = force (
        (appSet.mkAppSet {
          entries = { };
          extraApps.extra = customApp;
        }).apps
      );
      expectedFragment = "mkAppSet expects exactly an entries attribute";
    };

    duplicateNamesAcrossAppSets = {
      expression = force (
        (appSet.mergeAppSets [
          fixture
          (appSet.mkAppSet {
            entries.fixture = {
              description = "Duplicate fixture application";
              script = fixtureScript;
            };
          })
        ]).apps
      );
      expectedFragment = "app and validation names must be unique across app sets";
    };

    malformedMergedAppSet = {
      expression = force (
        (appSet.mergeAppSets [
          fixture
          {
            apps.unvalidated = customApp;
            validationsByName = { };
          }
        ]).apps
      );
      expectedFragment = "merged input app set app and validation names must match exactly";
    };

    mergedAppSetWithoutApps = {
      expression = force (
        (appSet.mergeAppSets [
          {
            validationsByName = { };
          }
        ]).apps
      );
      expectedFragment = "merged app sets must contain apps and validationsByName";
    };

    mergedAppSetWithoutValidations = {
      expression = force (
        (appSet.mergeAppSets [
          {
            apps = { };
          }
        ]).apps
      );
      expectedFragment = "merged app sets must contain apps and validationsByName";
    };
  };
in
if caseName == null then cases else cases.${caseName}.expression
