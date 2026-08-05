let
  pin = builtins.fromJSON (builtins.readFile ../../_packages/shellfirm/pin.json);
  manifest = fromTOML (builtins.readFile ../../_packages/command-guard/Cargo.toml);
  lock = fromTOML (builtins.readFile ../../_packages/command-guard/Cargo.lock);
  shellfirmPackages = builtins.filter (
    package:
    package.name == "shellfirm"
    && (package.source or null) == "registry+https://github.com/rust-lang/crates.io-index"
  ) lock.package;
  guardRoots = builtins.filter (
    package: package.name == "agent-command-guard" && !(package ? source)
  ) lock.package;
in
{
  testShellfirmPinManifestAndGuardLockStaySynchronized = {
    expr =
      manifest.dependencies.shellfirm.version == "=${pin.version}"
      && manifest.dependencies.shellfirm.default-features == false
      && builtins.length shellfirmPackages == 1
      && (builtins.head shellfirmPackages).version == pin.version
      && (builtins.head shellfirmPackages).checksum != ""
      && builtins.length guardRoots == 1
      && builtins.elem "shellfirm" (builtins.head guardRoots).dependencies;
    expected = true;
  };
}
