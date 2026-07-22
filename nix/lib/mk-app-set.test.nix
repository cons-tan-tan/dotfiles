{ lib, pkgs }:
let
  appSet = import ./mk-app-set.nix { inherit lib; };
  fixtureScript = pkgs.writeShellApplication {
    name = "fixture-app";
    text = "true";
  };
  secondFixtureScript = pkgs.writeShellApplication {
    name = "second-fixture-app";
    text = "true";
  };
  fixture = appSet.mkAppSet {
    entries = {
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
  fixtureExtraApp = {
    type = "app";
    program = "/bin/true";
  };
  fixtureWithExtra = appSet.mkAppSet {
    entries.fixture = {
      description = "Fixture application";
      script = fixtureScript;
    };
    extraApps.extra = fixtureExtraApp;
  };
  otherFixture = appSet.mkAppSet {
    entries.other = {
      description = "Other fixture application";
      script = secondFixtureScript;
    };
  };
  mergedFixture = appSet.mergeAppSets [
    fixtureWithExtra
    otherFixture
  ];
in
{
  testAppsDeriveFromEntries = {
    expr = {
      inherit (fixture.apps.fixture) type;
      inherit (fixture.apps.fixture.meta) description;
    };
    expected = {
      type = "app";
      description = "Fixture application";
    };
  };

  testProgramPointsAtScript = {
    expr = lib.hasSuffix "/bin/fixture-app" fixture.apps.fixture.program;
    expected = true;
  };

  testScriptsMatchEntries = {
    expr = map lib.getName fixture.scripts;
    expected = [
      "fixture-app"
      "second-fixture-app"
    ];
  };

  testExtraAppsMergedButNotInScripts = {
    expr = {
      appNames = builtins.attrNames fixtureWithExtra.apps;
      extraApp = fixtureWithExtra.apps.extra;
      scriptCount = builtins.length fixtureWithExtra.scripts;
    };
    expected = {
      appNames = [
        "extra"
        "fixture"
      ];
      extraApp = fixtureExtraApp;
      scriptCount = 1;
    };
  };

  testDuplicateAppNamesRejected = {
    expr =
      (builtins.tryEval (
        appSet.mkAppSet {
          entries.fixture = {
            description = "Fixture application";
            script = fixtureScript;
          };
          extraApps.fixture = fixtureExtraApp;
        }
      )).success;
    expected = false;
  };

  testAppSetsMergeAppsAndScripts = {
    expr = {
      appNames = builtins.attrNames mergedFixture.apps;
      scriptNames = map lib.getName mergedFixture.scripts;
    };
    expected = {
      appNames = [
        "extra"
        "fixture"
        "other"
      ];
      scriptNames = [
        "fixture-app"
        "second-fixture-app"
      ];
    };
  };

  testDuplicateNamesAcrossAppSetsRejected = {
    expr =
      (builtins.tryEval (
        appSet.mergeAppSets [
          fixture
          (appSet.mkAppSet {
            entries.fixture = {
              description = "Duplicate fixture application";
              script = fixtureScript;
            };
          })
        ]
      )).success;
    expected = false;
  };
}
