{
  den,
  lib,
  ...
}:
let
  forwardAgentCommandPolicy =
    { class, aspect-chain }:
    den.batteries.forward {
      each = lib.singleton class;
      fromClass = _: "agentCommandPolicy";
      intoClass = _: "homeManager";
      intoPath = _: [
        "dotfiles"
        "agentCommandPolicy"
      ];
      fromAspect = _: lib.head aspect-chain;
    };
in
{
  den.classes.agentCommandPolicy.description = "Agent command policy fragments forwarded into Home Manager";

  den.aspects.agent-command-policy-forward = {
    name = "class/agent-command-policy";
    includes = [ forwardAgentCommandPolicy ];
  };
}
