{ original, ... }:
''

  > **Local override**: when running on WSL2, use `drawio` from `$PATH`
  > for exports. The managed Linux headless wrapper already injects
  > `--no-sandbox`, `--disable-gpu`, and starts Xvfb / D-Bus. In that
  > environment, do not add these flags or call `/mnt/c/.../draw.io.exe`;
  > the "Opening the result" instructions below still apply.
''
+ original
