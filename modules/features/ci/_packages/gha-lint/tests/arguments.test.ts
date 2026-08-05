import { describe, expect, spyOn, test } from "bun:test";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { parseArguments, run } from "../src/main.ts";

describe("argument parsing", () => {
  test("uses text output by default", () => {
    expect(parseArguments(["workflow.yaml"])).toEqual({
      format: "text",
      files: ["workflow.yaml"],
      help: false,
      version: false
    });
  });

  test("accepts JSON output and positional separator", () => {
    const parsed = parseArguments(["--format", "json", "--", "-workflow.yaml"]);
    expect(parsed.format).toBe("json");
    expect(parsed.files).toEqual(["-workflow.yaml"]);
  });

  test("rejects unknown options", () => {
    expect(() => parseArguments(["--wat"])).toThrow("unknown option");
  });
});

describe("CLI contract", () => {
  test("returns zero for clean input", async () => {
    const root = await mkdtemp(join(tmpdir(), "gha-lint-cli-clean-"));
    const workflowDirectory = join(root, ".github", "workflows");
    await mkdir(workflowDirectory, { recursive: true });
    await writeFile(
      join(workflowDirectory, "clean.yaml"),
      "on: push\njobs:\n  build:\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo ok\n"
    );
    const log = spyOn(console, "log").mockImplementation(() => undefined);
    try {
      expect(await run([], root)).toBe(0);
      expect(log).not.toHaveBeenCalled();
    } finally {
      log.mockRestore();
      await rm(root, { recursive: true, force: true });
    }
  });

  test("returns one and emits machine-readable diagnostics", async () => {
    const root = await mkdtemp(join(tmpdir(), "gha-lint-cli-diagnostic-"));
    const workflow = join(root, "invalid.yaml");
    await writeFile(workflow, "on: push\nunknown-key: true\njobs: {}\n");
    const log = spyOn(console, "log").mockImplementation(() => undefined);
    try {
      expect(await run(["--format", "json", workflow], root)).toBe(1);
      const output = String(log.mock.calls.at(-1)?.[0]);
      const diagnostics = JSON.parse(output) as unknown[];
      expect(diagnostics.length).toBeGreaterThan(0);
    } finally {
      log.mockRestore();
      await rm(root, { recursive: true, force: true });
    }
  });

  test("returns two for an input or internal failure", async () => {
    const root = await mkdtemp(join(tmpdir(), "gha-lint-cli-error-"));
    const error = spyOn(console, "error").mockImplementation(() => undefined);
    try {
      expect(await run(["missing.yaml"], root)).toBe(2);
      expect(String(error.mock.calls.at(-1)?.[0])).toContain("does not exist");
    } finally {
      error.mockRestore();
      await rm(root, { recursive: true, force: true });
    }
  });
});
