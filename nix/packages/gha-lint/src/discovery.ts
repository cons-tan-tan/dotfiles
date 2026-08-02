import { stat } from "node:fs/promises";
import { isAbsolute, relative, resolve } from "node:path";

const defaultPatterns = [
  ".github/workflows/*.yml",
  ".github/workflows/*.yaml",
  "action.yml",
  "action.yaml",
  "*/action.yml",
  "*/action.yaml",
  "*/*/action.yml",
  "*/*/action.yaml",
  "*/*/*/action.yml",
  "*/*/*/action.yaml"
] as const;

export async function discoverFiles(repositoryRoot: string): Promise<string[]> {
  const found = new Set<string>();
  for (const pattern of defaultPatterns) {
    const glob = new Bun.Glob(pattern);
    for await (const path of glob.scan({
      cwd: repositoryRoot,
      absolute: false,
      dot: true,
      followSymlinks: false,
      onlyFiles: true
    })) {
      if (path.split("/").some(component => component === ".git" || component === "node_modules")) {
        continue;
      }
      found.add(path);
    }
  }
  return [...found].toSorted();
}

export async function resolveInputFiles(repositoryRoot: string, files: string[]): Promise<string[]> {
  if (files.length === 0) {
    return discoverFiles(repositoryRoot);
  }

  const resolved: string[] = [];
  for (const file of files) {
    const absolutePath = resolve(repositoryRoot, file);
    let status;
    try {
      status = await stat(absolutePath);
    } catch {
      throw new Error(`input file does not exist: ${file}`);
    }
    if (!status.isFile()) {
      throw new Error(`input path is not a regular file: ${file}`);
    }
    resolved.push(isAbsolute(file) ? absolutePath : relative(repositoryRoot, absolutePath));
  }
  return [...new Set(resolved)].toSorted();
}

export function isActionMetadataPath(path: string): boolean {
  const normalized = path.replaceAll("\\", "/");
  if (/\.github\/workflows(-lab)?\/[^/]+\.ya?ml$/i.test(normalized)) {
    return false;
  }
  return /(^|\/)action\.ya?ml$/i.test(normalized);
}
