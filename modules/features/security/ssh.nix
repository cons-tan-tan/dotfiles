{
  features.security-ssh = {
    name = "feature/security/ssh";
    homeManager = {
      # Secrets remain a runtime concern of the apply-secrets app. The store
      # only owns the Include stub and the non-secret common fragment.
      home.file.".ssh/config".text = ''
        Include ~/.ssh/config.d/*.conf
      '';
      home.file.".ssh/config.d/10-common.conf".text = ''
        # Managed by Nix (feature/security/ssh) - do not edit directly

        Host github.com
            HostName github.com
            User git

        Host *
            ServerAliveInterval 60
            TCPKeepAlive yes
      '';
    };
  };
}
