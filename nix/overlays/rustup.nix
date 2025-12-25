final: prev: {
  # https://github.com/NixOS/nixpkgs/issues/470496
  # Fixed in upstream: https://github.com/rust-lang/rustup/pull/4372
  rustup = prev.rustup.overrideAttrs (oldAttrs: {
    checkFlags = (oldAttrs.checkFlags or [ ]) ++ [
      "--skip=download::tests::reqwest::socks_proxy_request"
    ];
  });
}
