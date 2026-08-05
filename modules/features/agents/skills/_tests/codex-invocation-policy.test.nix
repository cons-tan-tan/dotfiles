# codex-invocation-policy.nix の純関数の契約テスト。
{ lib }:
let
  fm = import ../_lib/codex-invocation-policy.nix { inherit lib; };
in
{
  testCodexPolicyCreatedWhenMissingFile = {
    expr = fm.disableCodexImplicitInvocation "";
    expected = ''
      policy:
        allow_implicit_invocation: false
    '';
  };

  testCodexPolicyAppendedWithoutDroppingInterface = {
    expr = fm.disableCodexImplicitInvocation ''
      interface:
        display_name: 'Difit'
        default_prompt: 'Use $difit.'
    '';
    expected = ''
      interface:
        display_name: 'Difit'
        default_prompt: 'Use $difit.'

      policy:
        allow_implicit_invocation: false
    '';
  };

  testCodexPolicyInsertedIntoExistingPolicy = {
    expr = fm.disableCodexImplicitInvocation ''
      interface:
        display_name: 'Demo'
      policy:
        other: true
    '';
    expected = ''
      interface:
        display_name: 'Demo'
      policy:
        allow_implicit_invocation: false
        other: true
    '';
  };

  testCodexPolicyReplacesExistingValue = {
    expr = fm.disableCodexImplicitInvocation ''
      policy:
        allow_implicit_invocation: true
        other: true
    '';
    expected = ''
      policy:
        allow_implicit_invocation: false
        other: true
    '';
  };
}
