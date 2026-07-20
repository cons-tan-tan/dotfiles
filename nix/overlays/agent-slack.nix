agentSlackSource: _final: prev: {
  agent-slack = prev.callPackage ../packages/agent-slack {
    inherit agentSlackSource;
  };
}
