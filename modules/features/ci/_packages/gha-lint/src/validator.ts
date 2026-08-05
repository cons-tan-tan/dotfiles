import { readFile } from "node:fs/promises";
import { isAbsolute, relative, resolve } from "node:path";
import { isActionMetadataPath } from "./discovery.ts";
import { sortAndDeduplicate, type LintDiagnostic } from "./diagnostics.ts";
import { validateOfficial } from "./official-validator.ts";
import { validateSchema } from "./schema-validator.ts";
import { validateShellScripts } from "./shellcheck.ts";
import { parseYaml } from "./yaml-document.ts";

export async function validateFile(repositoryRoot: string, file: string): Promise<LintDiagnostic[]> {
  const absolutePath = isAbsolute(file) ? file : resolve(repositoryRoot, file);
  const displayPath = isAbsolute(file) ? relative(repositoryRoot, file) || file : file;
  const source = await readFile(absolutePath, "utf8");
  const action = isActionMetadataPath(absolutePath);
  const parsed = parseYaml(source);

  const [official, schema, shell] = await Promise.all([
    validateOfficial(repositoryRoot, absolutePath, displayPath, source),
    validateSchema(displayPath, parsed, action),
    validateShellScripts(displayPath, source, parsed, action)
  ]);
  return sortAndDeduplicate([...official, ...schema, ...shell]);
}
