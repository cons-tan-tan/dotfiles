{ ... }:
{
  features.cloud-aws = {
    name = "feature/cloud/aws";
    homeManager = import ./_lib/aws.nix;
  };
}
