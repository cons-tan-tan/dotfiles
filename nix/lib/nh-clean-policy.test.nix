let
  policy = import ./nh-clean-policy.nix;
in
{
  testCleanupPolicyLimits = {
    expr = {
      inherit (policy.growth)
        checkInterval
        maximumAgeSeconds
        retryIntervalSeconds
        thresholdBytes
        ;
    };
    expected = {
      checkInterval = "5m";
      maximumAgeSeconds = 21600;
      retryIntervalSeconds = 1800;
      thresholdBytes = 34359738368;
    };
  };
}
