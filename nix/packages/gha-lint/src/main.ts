#!/usr/bin/env bun
import { resolve } from "node:path";
import packageJson from "../package.json";
import { formatText, sortAndDeduplicate, type LintDiagnostic } from "./diagnostics.ts";
import { resolveInputFiles } from "./discovery.ts";
import { validateFile } from "./validator.ts";

type Options = {
  format: "text" | "json";
  files: string[];
  help: boolean;
  version: boolean;
};

const usage = `Usage: gha-lint [--format text|json] [FILE ...]

Validate GitHub Actions workflows and action metadata.

When FILE is omitted, gha-lint checks workflows directly under
.github/workflows and action.yml/action.yaml at repository depth 0 through 3.

Options:
  --format text|json  Diagnostic output format (default: text)
  --help              Show this help
  --version           Show the version`;

export function parseArguments(arguments_: string[]): Options {
  const options: Options = { format: "text", files: [], help: false, version: false };
  let positionalOnly = false;
  for (let index = 0; index < arguments_.length; index += 1) {
    const argument = arguments_[index];
    if (argument === undefined) {
      continue;
    }
    if (positionalOnly) {
      options.files.push(argument);
    } else if (argument === "--") {
      positionalOnly = true;
    } else if (argument === "--help" || argument === "-h") {
      options.help = true;
    } else if (argument === "--version" || argument === "-V") {
      options.version = true;
    } else if (argument === "--format") {
      const format = arguments_[index + 1];
      if (format !== "text" && format !== "json") {
        throw new Error("--format must be either text or json");
      }
      options.format = format;
      index += 1;
    } else if (argument.startsWith("-")) {
      throw new Error(`unknown option: ${argument}`);
    } else {
      options.files.push(argument);
    }
  }
  return options;
}

export async function run(arguments_: string[], repositoryRoot = process.cwd()): Promise<number> {
  let options: Options;
  try {
    options = parseArguments(arguments_);
  } catch (error) {
    console.error(`gha-lint: ${error instanceof Error ? error.message : String(error)}`);
    return 2;
  }

  if (options.help) {
    console.log(usage);
    return 0;
  }
  if (options.version) {
    console.log(packageJson.version);
    return 0;
  }

  try {
    const root = resolve(repositoryRoot);
    const files = await resolveInputFiles(root, options.files);
    const diagnostics: LintDiagnostic[] = [];
    for (const file of files) {
      diagnostics.push(...(await validateFile(root, file)));
    }
    const result = sortAndDeduplicate(diagnostics);
    if (options.format === "json") {
      console.log(JSON.stringify(result, null, 2));
    } else {
      result.forEach(diagnostic => console.log(formatText(diagnostic)));
    }
    return result.length === 0 ? 0 : 1;
  } catch (error) {
    console.error(`gha-lint: ${error instanceof Error ? error.message : String(error)}`);
    return 2;
  }
}

if (import.meta.main) {
  void run(Bun.argv.slice(2)).then(exitCode => {
    process.exitCode = exitCode;
  });
}
