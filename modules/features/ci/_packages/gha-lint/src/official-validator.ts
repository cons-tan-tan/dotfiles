import { realpath, readFile } from "node:fs/promises";
import { isAbsolute, relative, resolve, sep } from "node:path";
import { pathToFileURL } from "node:url";
import { FeatureFlags } from "@actions/expressions";
import { LogLevel, registerLogger, setLogLevel, validate } from "@actions/languageservice";
import type { FileProvider } from "@actions/workflow-parser/workflows/file-provider";
import { TextDocument } from "vscode-languageserver-textdocument";
import { DiagnosticSeverity } from "vscode-languageserver-types";
import { parse } from "yaml";
import type { LintDiagnostic } from "./diagnostics.ts";

const internalErrors: string[] = [];
registerLogger({
  error: message => internalErrors.push(message),
  warn: () => undefined,
  info: () => undefined,
  log: () => undefined
});
setLogLevel(LogLevel.Error);

const featureFlags = new FeatureFlags({ allowBackgroundSteps: true });

type JsonObject = Record<string, unknown>;
type RemoteCall = { with: JsonObject; secrets: JsonObject };

function object(value: unknown): JsonObject | undefined {
  return value && typeof value === "object" && !Array.isArray(value) ? (value as JsonObject) : undefined;
}

function reusableWorkflowReferences(source: string): Map<string, RemoteCall> {
  let value: unknown;
  try {
    value = parse(source);
  } catch {
    return new Map();
  }
  const jobs = object(object(value)?.jobs);
  if (!jobs) {
    return new Map();
  }
  const remoteCalls = new Map<string, RemoteCall>();
  for (const job of Object.values(jobs)) {
    const mapping = object(job);
    if (!mapping) {
      continue;
    }
    const uses = mapping.uses;
    if (typeof uses !== "string") {
      continue;
    }
    if (!uses.startsWith("./") && !uses.startsWith("$/")) {
      const existing = remoteCalls.get(uses);
      remoteCalls.set(uses, {
        with: { ...existing?.with, ...object(mapping.with) },
        secrets: { ...existing?.secrets, ...object(mapping.secrets) }
      });
    }
  }
  return remoteCalls;
}

function remoteWorkflowStub(call: RemoteCall = { with: {}, secrets: {} }): string {
  const inputs = Object.fromEntries(
    Object.entries(call.with).map(([name, value]) => [
      name,
      {
        required: false,
        type: typeof value === "boolean" ? "boolean" : typeof value === "number" ? "number" : "string"
      }
    ])
  );
  const secrets = Object.fromEntries(
    Object.keys(call.secrets).map(name => [name, { required: false }])
  );
  const workflowCall = {
    ...(Object.keys(inputs).length > 0 ? { inputs } : {}),
    ...(Object.keys(secrets).length > 0 ? { secrets } : {})
  };
  return JSON.stringify({
    on: { workflow_call: workflowCall },
    jobs: {
      gha_lint_remote: {
        "runs-on": "ubuntu-latest",
        steps: [{ run: "true" }]
      }
    }
  });
}

async function workflowFileProvider(
  repositoryRoot: string,
  remoteCalls: Map<string, RemoteCall>
): Promise<FileProvider> {
  const realRoot = await realpath(repositoryRoot);
  return {
    async getFileContent(reference) {
      if ("repository" in reference) {
        const identifier = `${reference.owner}/${reference.repository}/${reference.path}@${reference.version}`;
        return { name: identifier, content: remoteWorkflowStub(remoteCalls.get(identifier)) };
      }
      const absolutePath = resolve(realRoot, reference.path);
      const candidate = await realpath(absolutePath);
      const fromRoot = relative(realRoot, candidate);
      if (fromRoot === ".." || fromRoot.startsWith(`..${sep}`) || isAbsolute(fromRoot)) {
        throw new Error(`local reusable workflow escapes repository root: ${reference.path}`);
      }
      const content = await readFile(candidate, "utf8");
      const document = TextDocument.create(pathToFileURL(candidate).href, "yaml", 1, content);
      const diagnostics = await validate(document, { featureFlags });
      const hasErrors = diagnostics.some(
        diagnostic => diagnostic.severity === undefined || diagnostic.severity === DiagnosticSeverity.Error
      );
      if (hasErrors) {
        const kind = /action\.ya?ml$/i.test(reference.path) ? "action metadata" : "reusable workflow";
        throw new Error(`local ${kind} is invalid: ${reference.path}`);
      }
      return { name: reference.path, content };
    }
  };
}

function severity(value: DiagnosticSeverity | undefined): "error" | "warning" | "information" {
  if (value === DiagnosticSeverity.Warning) {
    return "warning";
  }
  if (value === DiagnosticSeverity.Information || value === DiagnosticSeverity.Hint) {
    return "information";
  }
  return "error";
}

export async function validateOfficial(
  repositoryRoot: string,
  absolutePath: string,
  displayPath: string,
  source: string
): Promise<LintDiagnostic[]> {
  internalErrors.length = 0;
  const document = TextDocument.create(pathToFileURL(absolutePath).href, "yaml", 1, source);
  const remoteCalls = reusableWorkflowReferences(source);
  const fileProvider = await workflowFileProvider(repositoryRoot, remoteCalls);
  const diagnostics = await validate(document, {
    featureFlags,
    fileProvider
  });

  if (internalErrors.length > 0) {
    throw new Error(`official validator failed for ${displayPath}: ${internalErrors.join("; ")}`);
  }

  return diagnostics.map(diagnostic => ({
    file: displayPath,
    source: "actions-language-service",
    severity: severity(diagnostic.severity),
    message: diagnostic.message,
    line: diagnostic.range.start.line + 1,
    column: diagnostic.range.start.character + 1,
    endLine: diagnostic.range.end.line + 1,
    endColumn: diagnostic.range.end.character + 1,
    ...(diagnostic.code === undefined ? {} : { code: String(diagnostic.code) })
  }));
}
