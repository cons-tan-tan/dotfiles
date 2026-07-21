# pin ? fromJSON (readFile ...) の注入可能 default が誤って外れた時に検知する。
# 既存の herdr-package.test.nix は引数の存在だけを検査するため、default の
# 有無はここで全消費者と同じ契約として固定する。
let
  hasInjectablePin = fn: argName: (builtins.functionArgs (import fn)).${argName} or false;
in
{
  testAgentBrowserPinInjectable = {
    expr = hasInjectablePin ./agent-browser/default.nix "pin";
    expected = true;
  };

  testAgentSlackPinInjectable = {
    expr = hasInjectablePin ./agent-slack/default.nix "pin";
    expected = true;
  };

  testHcomFamilyPinInjectable = {
    expr = hasInjectablePin ./hcom/default.nix "hcomPin";
    expected = true;
  };

  testHcomPackagePinInjectable = {
    expr = hasInjectablePin ./hcom/package.nix "hcomPin";
    expected = true;
  };

  testHerdrFamilyPinInjectable = {
    expr = hasInjectablePin ./herdr/default.nix "herdrPin";
    expected = true;
  };

  testHerdrPackagePinInjectable = {
    expr = hasInjectablePin ./herdr/package.nix "herdrPin";
    expected = true;
  };

  testShellfirmPinInjectable = {
    expr = hasInjectablePin ./shellfirm/default.nix "pin";
    expected = true;
  };

  testDifitPinInjectable = {
    expr = hasInjectablePin ./difit/default.nix "difitPin";
    expected = true;
  };

  testWatchexecPinInjectable = {
    expr = hasInjectablePin ../overlays/watchexec.nix "pin";
    expected = true;
  };
}
