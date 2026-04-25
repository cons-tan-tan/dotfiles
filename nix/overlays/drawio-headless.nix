final: prev: {
  drawio-headless = prev.writeShellApplication {
    name = "drawio";

    runtimeInputs = [
      prev.coreutils
      prev.dbus
      prev.gnugrep
      prev.xvfb-run
      prev.drawio
    ];

    text = ''
      tmpdir=$(mktemp -d)
      trap 'rm -rf "$tmpdir"' EXIT

      XDG_CONFIG_HOME="$tmpdir" \
        dbus-run-session --config-file=${prev.dbus}/share/dbus-1/session.conf -- \
          xvfb-run \
            --auto-display \
            --server-args="-screen 0 1024x768x24 -nolisten unix -nolisten tcp" \
            drawio --no-sandbox "$@" --disable-gpu \
        2> >(grep --line-buffered -E -v '^dbus-daemon\[[0-9]+\]:' >&2 || true)
    '';

    meta = {
      description = "WSL2-compatible xvfb wrapper around drawio";
      longDescription = ''
        Replacement for nixpkgs drawio-headless that works under WSLg with
        clean stderr.

        Adjustments over the upstream wrapper:
          1. dbus-run-session provides a session bus, eliminating the
             "Failed to connect to /run/user/UID/bus" error flood. The
             config file is passed explicitly because /etc/dbus-1/ on
             non-NixOS hosts (e.g. Ubuntu-WSL) lacks session.conf.
          2. Xvfb is started with -nolisten unix because WSLg mounts
             /tmp/.X11-unix as a read-only tmpfs (Xvfb cannot create its
             socket there).
          3. drawio is invoked with --no-sandbox; the Nix Electron build
             does not include the SUID sandbox helper.
          4. --disable-gpu is appended after user args so it is honored by
             Electron (suppresses GLX/EGL errors) but lands in
             program.args after the input file, where drawio-desktop's
             argv parser ignores it.
          5. dbus-daemon's own informational lines (a11y bus activation)
             are filtered from stderr.
      '';
      mainProgram = "drawio";
    };
  };
}
