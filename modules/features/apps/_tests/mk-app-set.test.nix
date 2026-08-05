{ lib, pkgs }:
let
  appSet = import ../_interface/app-set.nix { inherit lib; };
  fixtureScript = pkgs.writeShellApplication {
    name = "fixture-app";
    text = "true";
  };
  secondFixtureScript = pkgs.writeShellApplication {
    name = "second-fixture-app";
    text = "true";
  };
  customValidation = pkgs.writeText "custom-app-validation" "validated";
  customApp = {
    type = "app";
    meta.description = "Custom fixture application";
    program = "/bin/true";
  };
  fixture = appSet.mkAppSet {
    entries = {
      custom = {
        app = customApp;
        validation = customValidation;
      };
      fixture = {
        description = "Fixture application";
        script = fixtureScript;
      };
      second = {
        description = "Second fixture application";
        script = secondFixtureScript;
      };
    };
  };
  otherFixture = appSet.mkAppSet {
    entries.other = {
      description = "Other fixture application";
      script = secondFixtureScript;
    };
  };
  mergedFixture = appSet.mergeAppSets [
    fixture
    otherFixture
  ];
  evaluationSucceeds = value: (builtins.tryEval value).success;
in
{
  testAppsAndValidationsHaveExactNames = {
    expr = builtins.attrNames fixture.apps == builtins.attrNames fixture.validationsByName;
    expected = true;
  };

  testShellAppDerivesProgramAndDefaultValidation = {
    expr = {
      inherit (fixture.apps.fixture) type;
      inherit (fixture.apps.fixture.meta) description;
      program = lib.hasSuffix "/bin/fixture-app" fixture.apps.fixture.program;
      validation = fixture.validationsByName.fixture.drvPath;
    };
    expected = {
      type = "app";
      description = "Fixture application";
      program = true;
      validation = fixtureScript.drvPath;
    };
  };

  testCustomAppAndValidationRemainPaired = {
    expr = {
      app = fixture.apps.custom;
      validation = fixture.validationsByName.custom.drvPath;
    };
    expected = {
      app = customApp;
      validation = customValidation.drvPath;
    };
  };

  testMissingCustomValidationIsRejected = {
    expr = evaluationSucceeds (
      (appSet.mkAppSet {
        entries.invalid.app = customApp;
      }).apps
    );
    expected = false;
  };

  testMixedShellAndCustomStrategiesAreRejected = {
    expr = evaluationSucceeds (
      (appSet.mkAppSet {
        entries.invalid = {
          app = customApp;
          description = "Ambiguous fixture";
          script = fixtureScript;
          validation = customValidation;
        };
      }).apps
    );
    expected = false;
  };

  testShellAppWithUnknownFieldIsRejected = {
    expr = evaluationSucceeds (
      (appSet.mkAppSet {
        entries.invalid = {
          description = "Fixture application";
          script = fixtureScript;
          unexpected = true;
        };
      }).apps
    );
    expected = false;
  };

  testCustomAppWithUnknownFieldIsRejected = {
    expr = evaluationSucceeds (
      (appSet.mkAppSet {
        entries.invalid = {
          app = customApp;
          validation = customValidation;
          unexpected = true;
        };
      }).apps
    );
    expected = false;
  };

  testExtraAppsBypassIsRejected = {
    expr = evaluationSucceeds (
      (appSet.mkAppSet {
        entries = { };
        extraApps.extra = customApp;
      }).apps
    );
    expected = false;
  };

  testAppSetsMergeExactAppsAndValidations = {
    expr = {
      appNames = builtins.attrNames mergedFixture.apps;
      exact = builtins.attrNames mergedFixture.apps == builtins.attrNames mergedFixture.validationsByName;
    };
    expected = {
      appNames = [
        "custom"
        "fixture"
        "other"
        "second"
      ];
      exact = true;
    };
  };

  testDuplicateNamesAcrossAppSetsAreRejected = {
    expr = evaluationSucceeds (
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
    expected = false;
  };

  testMalformedMergedAppSetIsRejected = {
    expr = evaluationSucceeds (
      (appSet.mergeAppSets [
        fixture
        {
          apps.unvalidated = customApp;
          validationsByName = { };
        }
      ]).apps
    );
    expected = false;
  };
}
