{
  advisoryDb,
  advisoryDbLastModified,
  ciCheck,
  lib,
  modulesRoot,
  pkgs,
  repoRoot,
}:
let
  rustCatalog = import ../rust-projects.nix {
    inherit ciCheck lib pkgs;
  };
  rustProjects = rustCatalog.projects;
  rustSubjectSets = map (project: project.subjects or { }) rustProjects;
  rustSubjectNames = lib.concatMap builtins.attrNames rustSubjectSets;
  duplicateRustSubjectNames = rustCatalog.duplicates rustSubjectNames;
  rustSubjectValidation =
    if duplicateRustSubjectNames == [ ] then
      null
    else
      throw "Rust subjects have multiple owners: ${builtins.toJSON duplicateRustSubjectNames}";
  subjects = builtins.seq rustSubjectValidation (
    lib.foldl' (accumulator: subjectSet: accumulator // subjectSet) { } rustSubjectSets
  );
  applicableRustProjects = builtins.filter (
    project: project.platformPredicate pkgs.stdenv.hostPlatform
  ) rustProjects;
  rustBuildVariants = lib.concatMap (
    project: map (variant: variant // { inherit (project) ciTargets; }) project.buildVariants
  ) applicableRustProjects;
  rustClippyVariants = lib.concatMap (project: project.clippyVariants) applicableRustProjects;
  rustPath = path: repoRoot + "/${path}";
  rustSourceFiles = lib.filesystem.listFilesRecursive modulesRoot;
  relativePath = path: lib.removePrefix "${toString repoRoot}/" (toString path);
  discoveredRustManifests = map relativePath (
    builtins.filter (path: baseNameOf path == "Cargo.toml") rustSourceFiles
  );
  discoveredRustLockfiles = map relativePath (
    builtins.filter (path: baseNameOf path == "Cargo.lock") rustSourceFiles
  );
  rustInventory = rustCatalog.inventory {
    discoveredManifests = discoveredRustManifests;
    discoveredLockfiles = discoveredRustLockfiles;
  };
  emptyRustInventory = {
    manifests = {
      missing = [ ];
      stale = [ ];
      duplicate = [ ];
    };
    lockfiles = {
      missing = [ ];
      stale = [ ];
      duplicate = [ ];
    };
  };
  rustInventoryValidation =
    if rustInventory == emptyRustInventory then
      null
    else
      throw "rust project inventory mismatch: ${builtins.toJSON rustInventory}";
  rustLockfiles = map (project: project.lock // { path = rustPath project.lock.path; }) rustProjects;

  mkRustClippyCheck =
    {
      name,
      package,
      flags,
    }:
    pkgs.rustPlatform.buildRustPackage {
      pname = "${name}-clippy";
      inherit (package) cargoDeps src version;
      UPDATE_PINS_REGISTRY_ROOT = package.UPDATE_PINS_REGISTRY_ROOT or null;

      nativeBuildInputs = [ pkgs.clippy ];
      auditable = false;
      doCheck = false;

      buildPhase = ''
        runHook preBuild
        cargo clippy --offline --locked ${lib.escapeShellArgs flags} -- -D warnings
        runHook postBuild
      '';

      installPhase = ''
        runHook preInstall
        touch "$out"
        runHook postInstall
      '';
    };

  rustBuildEntries = map (
    variant: lib.nameValuePair variant.checkName (ciCheck.buildEntry variant.ciTargets variant.package)
  ) rustBuildVariants;
  rustTests = pkgs.linkFarm "rust-tests" (
    map (variant: {
      name = variant.checkName;
      path = variant.package;
    }) rustBuildVariants
  );
  rustClippyChecks = lib.listToAttrs (
    map (
      variant:
      lib.nameValuePair variant.checkName (mkRustClippyCheck {
        name = variant.checkName;
        package = variant.package;
        flags = variant.clippyFlags;
      })
    ) rustClippyVariants
  );
  rustClippy = pkgs.linkFarm "rust-clippy" (
    lib.mapAttrsToList (name: path: { inherit name path; }) rustClippyChecks
  );

  ignoredRustAdvisories = lib.concatMap (
    lock: map (advisory: advisory // { inherit (lock) owner; }) lock.ignoredAdvisories
  ) rustLockfiles;
  rustAdvisoryLabel = advisory: "${advisory.owner}:${advisory.id} (reviewed ${advisory.reviewedAt})";
  expiredRustAdvisoriesAt =
    timestamp:
    map rustAdvisoryLabel (
      builtins.filter (advisory: timestamp >= advisory.expiresAt) ignoredRustAdvisories
    );
  rustAdvisoryExpiryContractValidation =
    if
      builtins.all (
        advisory:
        !(builtins.elem (rustAdvisoryLabel advisory) (expiredRustAdvisoriesAt (advisory.expiresAt - 1)))
        && builtins.elem (rustAdvisoryLabel advisory) (expiredRustAdvisoriesAt advisory.expiresAt)
      ) ignoredRustAdvisories
    then
      null
    else
      throw "rust advisory expiry boundary validation failed";
  rustAdvisoryExpiryValidation =
    let
      expired = expiredRustAdvisoriesAt advisoryDbLastModified;
    in
    if expired == [ ] then
      null
    else
      throw "rust advisory exceptions expired for pinned DB: ${builtins.toJSON expired}";
  rustAdvisories = builtins.seq rustAdvisoryExpiryContractValidation (
    builtins.seq rustAdvisoryExpiryValidation (
      pkgs.runCommand "rust-advisories"
        {
          nativeBuildInputs = [ pkgs.cargo-audit ];
        }
        ''
          export CARGO_HOME="$TMPDIR/cargo-home"
          export CARGO_NET_OFFLINE=true
          mkdir -p "$CARGO_HOME"

          ${lib.concatMapStringsSep "\n" (
            lock:
            # Yanked status requires a crates.io registry index, which is not
            # pinned here, so this reproducible gate excludes it. RustSec
            # vulnerabilities and unsound warnings fail. Unmaintained warnings
            # remain visible without being denied.
            ''
              echo "Auditing ${lock.owner}: ${lock.path}"
              cargo-audit audit \
                --color never \
                --db ${advisoryDb} \
                --deny unsound \
                --no-fetch \
                --no-yanked \
                ${
                  lib.concatMapStringsSep " " (
                    advisory: "--ignore ${lib.escapeShellArg advisory.id}"
                  ) lock.ignoredAdvisories
                } \
                --file ${lock.path}
            '') rustLockfiles}

          touch "$out"
        ''
    )
  );
  aggregateEntries = [
    (lib.nameValuePair "rust-clippy" (
      ciCheck.buildEntry (ciCheck.targets.both "rust-and-bats") rustClippy
    ))
    # The advisory database and lockfiles are platform-independent, so a second
    # Darwin build would only duplicate the same source-level decision.
    (lib.nameValuePair "rust-advisories" (
      ciCheck.buildEntry (ciCheck.targets.linux "rust-and-bats") rustAdvisories
    ))
    (lib.nameValuePair "rust-tests" (
      ciCheck.buildEntry (ciCheck.targets.both "rust-and-bats") rustTests
    ))
  ];
  checkEntries = rustBuildEntries ++ aggregateEntries;
  duplicateCheckNames = rustCatalog.duplicates (map (entry: entry.name) checkEntries);
  checkNameValidation =
    if duplicateCheckNames == [ ] then
      null
    else
      throw "Rust check names collide with reserved aggregates: ${builtins.toJSON duplicateCheckNames}";
in
{
  inherit subjects;
  producer = ciCheck.mkBuildProducer {
    owner = "Rust checks";
    entries = builtins.seq rustInventoryValidation (
      builtins.seq rustSubjectValidation (builtins.seq checkNameValidation (lib.listToAttrs checkEntries))
    );
  };
}
