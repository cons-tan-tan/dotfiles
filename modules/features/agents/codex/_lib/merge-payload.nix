# Preserve runtime-owned config fields while replacing managed hook trust state.
{ codexHome, settings }:
settings
// {
  __delete_prefixes = [
    {
      path = [
        "hooks"
        "state"
      ];
      prefix = "${codexHome}/hooks.json:";
    }
  ];

  __delete = [
    [
      "plugins"
      "herdr@herdr"
    ]
    [
      "marketplaces"
      "herdr"
    ]
    [
      "features"
      "network_proxy"
    ]
    [
      "permissions"
      "local-dev"
      "network"
    ]
  ];

}
