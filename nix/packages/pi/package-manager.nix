{
  coreutils,
  nodejs,
  pnpm,
  writeShellApplication,
}:
# Pi-managed packages stay in Pi-specific directories. This wrapper isolates
# pnpm's cache and config without shadowing the user's interactive pnpm.
writeShellApplication {
  # Pi selects pnpm-specific install flags from the package-manager basename.
  name = "pnpm";
  runtimeInputs = [ coreutils ];
  text = ''
    NODE_BIN=${nodejs}/bin
    PNPM_BIN=${pnpm}/bin/pnpm
    ${builtins.readFile ./package-manager.sh}
  '';
}
