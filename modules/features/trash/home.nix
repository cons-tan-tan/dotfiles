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
      prepareTrashDirectory = pkgs.writeShellApplication {
        name = "prepare-trash-directory";
        runtimeInputs = [ pkgs.coreutils ];
        text = builtins.readFile ./_scripts/prepare-trash-directory.sh;
      };
    in
    {
      home.packages = [ pkgs.trash-cli ];

      # Codex sandbox grants only existing directories, so create the Freedesktop
      # Trash state at activation time without replacing user content.
      home.activation.trashDirectory = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run ${pkgs.coreutils}/bin/env \
          TRASH_DIRECTORY=${lib.escapeShellArg trashDirectory} \
          ${lib.getExe prepareTrashDirectory}
      '';
    };
}
