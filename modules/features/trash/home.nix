{
  features.trash.homeManager =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      trashDirectory = "${config.xdg.dataHome}/Trash";
    in
    {
      home.packages = [ pkgs.trash-cli ];

      # Codex sandbox grants only existing directories, so create the Freedesktop
      # Trash state at activation time without replacing user content.
      home.activation.trashDirectory = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run ${pkgs.coreutils}/bin/mkdir -p \
          ${lib.escapeShellArg "${trashDirectory}/files"} \
          ${lib.escapeShellArg "${trashDirectory}/info"}
        run ${pkgs.coreutils}/bin/chmod 0700 \
          ${lib.escapeShellArg trashDirectory} \
          ${lib.escapeShellArg "${trashDirectory}/files"} \
          ${lib.escapeShellArg "${trashDirectory}/info"}
      '';
    };
}
