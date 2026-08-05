import { readFile } from "node:fs/promises";
import Ajv, { type ErrorObject, type ValidateFunction } from "ajv";
import { isMap, isSeq, type Node, type Pair, type Scalar, type YAMLMap } from "yaml";
import type { LintDiagnostic } from "./diagnostics.ts";
import type { ParsedYaml } from "./yaml-document.ts";
import { nodeAt } from "./yaml-document.ts";

type JsonSchema = Record<string, unknown>;
type SchemaKind = "workflow" | "action";

const schemaSources = {
  workflow: {
    environment: "GHA_LINT_WORKFLOW_SCHEMA",
    url: "https://www.schemastore.org/github-workflow.json"
  },
  action: {
    environment: "GHA_LINT_ACTION_SCHEMA",
    url: "https://www.schemastore.org/github-action.json"
  }
} as const;

const validatorPromises: Partial<Record<SchemaKind, Promise<ValidateFunction>>> = {};

async function loadSchema(kind: SchemaKind): Promise<JsonSchema> {
  const source = schemaSources[kind];
  const override = process.env[source.environment];
  let text: string;
  if (override) {
    text = await readFile(override, "utf8");
  } else {
    const response = await fetch(source.url, {
      headers: { accept: "application/schema+json, application/json" },
      signal: AbortSignal.timeout(30_000)
    });
    if (!response.ok) {
      throw new Error(`SchemaStore ${kind} schema request failed with HTTP ${response.status}`);
    }
    text = await response.text();
  }

  let schema: unknown;
  try {
    schema = JSON.parse(text);
  } catch {
    throw new Error(`SchemaStore ${kind} schema is not valid JSON`);
  }
  if (!schema || typeof schema !== "object" || Array.isArray(schema)) {
    throw new Error(`SchemaStore ${kind} schema is not a JSON object`);
  }
  return schema as JsonSchema;
}

function validatorFor(kind: SchemaKind): Promise<ValidateFunction> {
  const cached = validatorPromises[kind];
  if (cached) {
    return cached;
  }
  const promise = loadSchema(kind).then(schema => {
    const ajv = new Ajv({
      allErrors: true,
      allowUnionTypes: true,
      strict: false,
      validateFormats: false
    });
    return ajv.compile(schema);
  });
  validatorPromises[kind] = promise;
  return promise;
}

function decodePointer(pointer: string): string[] {
  if (!pointer) {
    return [];
  }
  return pointer
    .slice(1)
    .split("/")
    .map(segment => segment.replaceAll("~1", "/").replaceAll("~0", "~"));
}

function resolvePath(parsed: ParsedYaml, error: ErrorObject): { path: (string | number)[]; node: Node | null } {
  const path: (string | number)[] = [];
  let current = parsed.document.contents as Node | null;
  for (const segment of decodePointer(error.instancePath)) {
    const value: string | number = isSeq(current) && /^\d+$/.test(segment) ? Number(segment) : segment;
    const candidatePath = [...path, value];
    const candidate = nodeAt(parsed.document, candidatePath);
    if (!candidate) {
      break;
    }
    path.push(value);
    current = candidate;
  }
  return { path, node: current };
}

function findMappingKey(mapping: YAMLMap, key: string): Scalar | null {
  const pair = mapping.items.find(item => String((item as Pair).key) === key) as Pair | undefined;
  return pair?.key && typeof pair.key === "object" ? (pair.key as Scalar) : null;
}

function positionForError(parsed: ParsedYaml, error: ErrorObject) {
  const resolved = resolvePath(parsed, error);
  let node = resolved.node ?? parsed.document.contents;

  if (error.keyword === "additionalProperties" || error.keyword === "propertyNames") {
    const key = String(
      error.keyword === "additionalProperties"
        ? (error.params as { additionalProperty?: unknown }).additionalProperty
        : (error.params as { propertyName?: unknown }).propertyName
    );
    if (isMap(node)) {
      node = findMappingKey(node, key) ?? node;
    }
  }

  const offset = node?.range?.[0] ?? 0;
  const endOffset = node?.range?.[1] ?? offset;
  const start = parsed.lineCounter.linePos(offset);
  const end = parsed.lineCounter.linePos(endOffset);
  return { start, end };
}

export function yamlParseDiagnostics(file: string, parsed: ParsedYaml): LintDiagnostic[] {
  return parsed.document.errors.map(error => {
    const position = parsed.lineCounter.linePos(error.pos[0]);
    return {
      file,
      source: "yaml",
      severity: "error",
      message: error.message,
      line: position.line,
      column: position.col,
      endLine: position.line,
      endColumn: position.col + 1
    };
  });
}

export async function validateSchema(
  file: string,
  parsed: ParsedYaml,
  action: boolean
): Promise<LintDiagnostic[]> {
  if (parsed.document.errors.length > 0) {
    return yamlParseDiagnostics(file, parsed);
  }

  const validate = await validatorFor(action ? "action" : "workflow");
  if (validate(parsed.value)) {
    return [];
  }

  return (validate.errors ?? []).map(error => {
    const { start, end } = positionForError(parsed, error);
    return {
      file,
      source: "schemastore",
      severity: "error",
      message: `${error.instancePath || "/"} ${error.message ?? error.keyword}`,
      line: start.line,
      column: start.col,
      endLine: end.line,
      endColumn: end.col,
      code: error.keyword
    };
  });
}
