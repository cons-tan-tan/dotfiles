{
  mkAppSet = import ./app-set.nix;
  mkCandidatePackage = import ../_lib/candidate-package.nix;
  registry = import ./registry.nix;
}
