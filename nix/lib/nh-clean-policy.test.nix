let
  policy = import ./nh-clean-policy.nix;
in
{
  testCleanupPolicyLimits = {
    expr = {
      inherit (policy.growth)
        checkInterval
        cleanupTimeout
        maximumAgeSeconds
        retryIntervalSeconds
        thresholdBytes
        ;
    };
    expected = {
      checkInterval = "5m";
      cleanupTimeout = "2h";
      maximumAgeSeconds = 21600;
      retryIntervalSeconds = 1800;
      thresholdBytes = 34359738368;
    };
  };
}
