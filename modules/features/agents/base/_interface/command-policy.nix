{
  aggregate = import ../_lib/command-policy/aggregate.nix;
  compiler = import ../_lib/command-policy/compiler.nix;
  guarded = lib: (import ../_lib/command-policy/rule-dsl.nix { inherit lib; }).guarded;
  mkAbbreviatedLongOptionProfile =
    lib: (import ../_lib/command-policy/profile.nix { inherit lib; }).mkAbbreviatedLongOptionProfile;
  mkGuard = import ../_lib/command-policy/mk-guard.nix;
  options = ./command-policy-options.nix;
}
