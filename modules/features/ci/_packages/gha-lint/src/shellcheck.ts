import { isScalar, type Node, type Scalar } from "yaml";
import type { LintDiagnostic } from "./diagnostics.ts";
import type { ParsedYaml } from "./yaml-document.ts";
import { nodeAt } from "./yaml-document.ts";

const shellcheckFromNix = "@shellcheck@";
const shellcheckPath = shellcheckFromNix.startsWith("@")
  ? (process.env.GHA_LINT_SHELLCHECK ?? "shellcheck")
  : shellcheckFromNix;

type JsonValue = null | boolean | number | string | JsonValue[] | { [key: string]: JsonValue };
type ObjectValue = { [key: string]: JsonValue };

type Script = {
  path: (string | number)[];
  source: string;
  shell: "bash" | "sh";
};

type ShellCheckComment = {
  line: number;
  endLine: number;
  column: number;
  endColumn: number;
  level: string;
  code: number;
  message: string;
};

function object(value: JsonValue | undefined): ObjectValue | undefined {
  return value && typeof value === "object" && !Array.isArray(value) ? value : undefined;
}

function staticShell(value: JsonValue | undefined): "bash" | "sh" | "skip" | undefined {
  if (value === undefined) {
    return undefined;
  }
  if (typeof value !== "string" || value.includes("${{")) {
    return "skip";
  }
  const command = value.trim().split(/\s+/, 1)[0]?.split("/").at(-1);
  if (command === "bash" || command === "sh") {
    return command;
  }
  return "skip";
}

function defaultShell(runsOn: JsonValue | undefined): "bash" | "skip" {
  const mapping = object(runsOn);
  const candidate = mapping ? mapping.labels : runsOn;
  const labels = typeof candidate === "string" ? [candidate] : Array.isArray(candidate) ? candidate : [];
  if (labels.length === 0) {
    return "skip";
  }
  if (labels.some(label => typeof label === "string" && /windows/i.test(label))) {
    return "skip";
  }
  if (labels.some(label => typeof label === "string" && label.includes("${{"))) {
    return "skip";
  }
  return labels.some(
    label => typeof label === "string" && /(?:^|[-_])(ubuntu|linux|macos)(?:$|[-_])/i.test(label)
  )
    ? "bash"
    : "skip";
}

function collectStep(
  scripts: Script[],
  step: JsonValue,
  path: (string | number)[],
  inheritedShell: "bash" | "sh" | "skip"
) {
  const mapping = object(step);
  if (!mapping) {
    return;
  }
  if (typeof mapping.run === "string") {
    const shell = staticShell(mapping.shell) ?? inheritedShell;
    if (shell !== "skip") {
      scripts.push({ path: [...path, "run"], source: mapping.run, shell });
    }
  }
  if (Array.isArray(mapping.parallel)) {
    mapping.parallel.forEach((nested, index) => collectStep(scripts, nested, [...path, "parallel", index], inheritedShell));
  }
}

function collectScripts(value: JsonValue, action: boolean): Script[] {
  const scripts: Script[] = [];
  const root = object(value);
  if (!root) {
    return scripts;
  }

  if (action) {
    const runs = object(root.runs);
    if (runs?.using !== "composite" || !Array.isArray(runs.steps)) {
      return scripts;
    }
    runs.steps.forEach((step, index) => collectStep(scripts, step, ["runs", "steps", index], "skip"));
    return scripts;
  }

  const workflowDefault = staticShell(object(object(root.defaults)?.run)?.shell);
  const jobs = object(root.jobs);
  for (const [jobName, jobValue] of Object.entries(jobs ?? {})) {
    const job = object(jobValue);
    if (!job || !Array.isArray(job.steps)) {
      continue;
    }
    const jobDefault = staticShell(object(object(job.defaults)?.run)?.shell);
    const inherited = jobDefault ?? workflowDefault ?? defaultShell(job["runs-on"]);
    job.steps.forEach((step, index) => collectStep(scripts, step, ["jobs", jobName, "steps", index], inherited));
  }
  return scripts;
}

function replaceExpressions(source: string): string {
  return source.replace(/\$\{\{[\s\S]*?\}\}/g, expression => expression.replace(/[^\r\n]/g, "_"));
}

function isBlockLiteral(node: Node | null): node is Scalar {
  return isScalar(node) && node.type === "BLOCK_LITERAL";
}

function mapPosition(
  parsed: ParsedYaml,
  source: string,
  node: Node | null,
  comment: ShellCheckComment
): { line: number; column: number; endLine: number; endColumn: number; suffix: string } {
  const offset = node?.range?.[0] ?? 0;
  const start = parsed.lineCounter.linePos(offset);
  if (isBlockLiteral(node)) {
    const lines = source.split(/\r?\n/);
    const line = start.line + comment.line;
    const endLine = start.line + comment.endLine;
    const indentation = lines[line - 1]?.match(/^\s*/)?.[0].length ?? 0;
    const endIndentation = lines[endLine - 1]?.match(/^\s*/)?.[0].length ?? indentation;
    return {
      line,
      column: indentation + comment.column,
      endLine,
      endColumn: endIndentation + comment.endColumn,
      suffix: ""
    };
  }

  if (isScalar(node) && node.type === "PLAIN") {
    return {
      line: start.line,
      column: start.col + comment.column - 1,
      endLine: start.line,
      endColumn: start.col + comment.endColumn - 1,
      suffix: ""
    };
  }

  return {
    line: start.line,
    column: start.col,
    endLine: start.line,
    endColumn: start.col + 1,
    suffix: ` (script ${comment.line}:${comment.column})`
  };
}

async function runShellCheck(script: Script): Promise<ShellCheckComment[]> {
  const process = Bun.spawn(
    [
      shellcheckPath,
      "--norc",
      "--format=json1",
      `--shell=${script.shell}`,
      "--exclude=SC1091,SC2194,SC2050,SC2153,SC2154,SC2157,SC2043",
      "-"
    ],
    { stdin: "pipe", stdout: "pipe", stderr: "pipe" }
  );
  process.stdin.write(replaceExpressions(script.source));
  process.stdin.end();

  const [stdout, stderr, exitCode] = await Promise.all([
    new Response(process.stdout).text(),
    new Response(process.stderr).text(),
    process.exited
  ]);
  if (exitCode > 1) {
    throw new Error(`ShellCheck failed with exit ${exitCode}: ${stderr.trim() || stdout.trim()}`);
  }

  let result: unknown;
  try {
    result = JSON.parse(stdout);
  } catch {
    throw new Error(`ShellCheck returned invalid JSON: ${stdout.trim() || stderr.trim()}`);
  }
  if (!result || typeof result !== "object" || !Array.isArray((result as { comments?: unknown }).comments)) {
    throw new Error("ShellCheck JSON output has no comments array");
  }
  return (result as { comments: ShellCheckComment[] }).comments;
}

export async function validateShellScripts(
  file: string,
  source: string,
  parsed: ParsedYaml,
  action: boolean
): Promise<LintDiagnostic[]> {
  if (parsed.document.errors.length > 0) {
    return [];
  }
  const diagnostics: LintDiagnostic[] = [];
  for (const script of collectScripts(parsed.value as JsonValue, action)) {
    const node = nodeAt(parsed.document, script.path);
    for (const comment of await runShellCheck(script)) {
      const position = mapPosition(parsed, source, node, comment);
      diagnostics.push({
        file,
        source: "shellcheck",
        severity: comment.level === "error" ? "error" : "warning",
        message: `${comment.message}${position.suffix}`,
        line: position.line,
        column: position.column,
        endLine: position.endLine,
        endColumn: position.endColumn,
        code: `SC${comment.code}`
      });
    }
  }
  return diagnostics;
}
