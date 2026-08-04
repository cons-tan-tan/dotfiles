{
  advisoryDb,
  advisoryDbLastModified,
  ciCheck,
  lib,
  nixRoot,
  pkgs,
}:
let
  rustCatalog = import ../rust-projects.nix {
    inherit ciCheck lib pkgs;
  };
  rustProjects = rustCatalog.projects;
  rustProjectsByName = lib.listToAttrs (
    map (project: lib.nameValuePair project.name project) rustProjects
  );
  rustProject = name: rustProjectsByName.${name};
  applicableRustProjects = builtins.filter (
    project: project.platformPredicate pkgs.stdenv.hostPlatform
  ) rustProjects;
  rustBuildVariants = lib.concatMap (
    project: map (variant: variant // { inherit (project) ciTargets; }) project.buildVariants
  ) applicableRustProjects;
  rustClippyVariants = lib.concatMap (project: project.clippyVariants) applicableRustProjects;
  rustPath = path: nixRoot + "/${path}";
  discoveredRustManifests = map (path: lib.removePrefix "${toString nixRoot}/" (toString path)) (
    builtins.filter (path: baseNameOf path == "Cargo.toml") (lib.filesystem.listFilesRecursive nixRoot)
  );
  discoveredRustLockfiles = map (path: lib.removePrefix "${toString nixRoot}/" (toString path)) (
    builtins.filter (path: baseNameOf path == "Cargo.lock") (lib.filesystem.listFilesRecursive nixRoot)
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

  subjects = {
    updatePinsCore = (rustProject "update-pins").packages.default;
    applySecretsCore = (rustProject "apply-secrets").packages.default;
    applyNixSettingsCore = (rustProject "apply-nix-settings").packages.default;
    agentCommandGuard = (rustProject "agent-command-guard").packages.default;
    awsConfigHelper = (rustProject "aws-config-helper").packages.default;
    safeFetch = (rustProject "safe-fetch").packages;
  };

  mkRustClippyCheck =
    {
      name,
      package,
      flags,
    }:
    pkgs.rustPlatform.buildRustPackage {
      pname = "${name}-clippy";
      inherit (package) version src cargoDeps;

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
    variant: lib.nameValuePair variant.checkName (ciCheck.annotate variant.ciTargets variant.package)
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
      ciCheck.annotate (ciCheck.targets.both "rust-and-bats") rustClippy
    ))
    # The advisory database and lockfiles are platform-independent, so a second
    # Darwin build would only duplicate the same source-level decision.
    (lib.nameValuePair "rust-advisories" (
      ciCheck.annotate (ciCheck.targets.linux "rust-and-bats") rustAdvisories
    ))
    (lib.nameValuePair "rust-tests" (ciCheck.annotate (ciCheck.targets.both "rust-and-bats") rustTests))
  ];
in
{
  inherit subjects;
  producer = {
    owner = "Rust checks";
    checks = builtins.seq rustInventoryValidation (
      lib.listToAttrs (rustBuildEntries ++ aggregateEntries)
    );
  };
}
