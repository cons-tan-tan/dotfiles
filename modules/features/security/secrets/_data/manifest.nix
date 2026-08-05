[
  {
    src = "secrets/ssh-private.yaml";
    dst = ".ssh/config.d/50-private.conf";
    format = "ssh-config-yaml";
    mode = "600";
    dirMode = "700";
  }
]
