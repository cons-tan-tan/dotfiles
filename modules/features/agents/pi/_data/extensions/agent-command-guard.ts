import { spawnSync } from "node:child_process";
import {
  isToolCallEventType,
  type ExtensionAPI,
} from "@earendil-works/pi-coding-agent";

const GUARD_BIN = "@guardBin@";
const GUARD_POLICY = "@guardPolicy@";

interface GuardResponse {
  hookSpecificOutput?: {
    additionalContext?: string;
    permissionDecision?: string;
    permissionDecisionReason?: string;
  };
}

function parseResponse(stdout: string): GuardResponse {
  const response: unknown = JSON.parse(stdout);
  if (typeof response !== "object" || response === null || Array.isArray(response)) {
    throw new Error("agent-command-guard returned a non-object response");
  }

  const record = response as Record<string, unknown>;
  if (!("hookSpecificOutput" in record)) {
    if (Object.keys(record).length === 0) return {};
    throw new Error("agent-command-guard returned an unknown response shape");
  }

  const rawOutput = record.hookSpecificOutput;
  if (typeof rawOutput !== "object" || rawOutput === null || Array.isArray(rawOutput)) {
    throw new Error("agent-command-guard returned invalid hook output");
  }
  const output = rawOutput as Record<string, unknown>;
  if (output.permissionDecision === "deny") {
    if (
      typeof output.permissionDecisionReason !== "string" ||
      output.permissionDecisionReason.length === 0
    ) {
      throw new Error("agent-command-guard deny response has no reason");
    }
    return {
      hookSpecificOutput: {
        permissionDecision: "deny",
        permissionDecisionReason: output.permissionDecisionReason,
      },
    };
  }
  if (
    !("permissionDecision" in output) &&
    typeof output.additionalContext === "string" &&
    output.additionalContext.length > 0
  ) {
    return {
      hookSpecificOutput: { additionalContext: output.additionalContext },
    };
  }
  throw new Error("agent-command-guard returned an unknown permission decision");
}

function assess(command: string, cwd: string): GuardResponse {
  const result = spawnSync(GUARD_BIN, ["--policy", GUARD_POLICY], {
    encoding: "utf8",
    input: JSON.stringify({
      cwd,
      hook_event_name: "PreToolUse",
      tool_name: "Bash",
      tool_input: { command },
    }),
    maxBuffer: 1024 * 1024,
    timeout: 10_000,
  });

  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(`agent-command-guard exited with status ${result.status}`);
  }
  return parseResponse(result.stdout);
}

export default function (pi: ExtensionAPI) {
  pi.on("tool_call", (event, ctx) => {
    if (!isToolCallEventType("bash", event)) return;

    let response: GuardResponse;
    try {
      response = assess(event.input.command, ctx.cwd);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      return {
        block: true,
        reason: `Shared command guard failed closed: ${message}`,
      };
    }

    const output = response.hookSpecificOutput;
    if (output?.permissionDecision === "deny") {
      return {
        block: true,
        reason: output.permissionDecisionReason ?? "Blocked by the shared command policy.",
      };
    }
    if (output?.additionalContext) {
      pi.sendMessage(
        {
          customType: "agent-command-policy",
          content: output.additionalContext,
          display: true,
        },
        { deliverAs: "steer" },
      );
    }
  });
}
