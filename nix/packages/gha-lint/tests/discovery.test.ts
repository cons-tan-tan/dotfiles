import { afterEach, describe, expect, test } from "bun:test";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { discoverFiles, isActionMetadataPath, resolveInputFiles } from "../src/discovery.ts";

const roots: string[] = [];

afterEach(async () => {
  await Promise.all(roots.splice(0).map(root => rm(root, { recursive: true, force: true })));
});

async function fixture(paths: string[]): Promise<string> {
  const root = await mkdtemp(join(tmpdir(), "gha-lint-discovery-"));
  roots.push(root);
  for (const path of paths) {
    const absolute = join(root, path);
    await mkdir(dirname(absolute), { recursive: true });
    await writeFile(absolute, "name: fixture\n");
  }
  return root;
}

describe("default file discovery", () => {
  test("checks direct workflows and action metadata at depth zero through three", async () => {
    const root = await fixture([
      ".github/workflows/ci.yaml",
      ".github/workflows/lint.yml",
      ".github/workflows/nested/ignored.yaml",
      ".github/actions/example/action.yml",
      "action.yml",
      "one/action.yaml",
      "one/two/action.yml",
      "one/two/three/action.yaml",
      "one/two/three/four/action.yml"
    ]);

    expect(await discoverFiles(root)).toEqual([
      ".github/actions/example/action.yml",
      ".github/workflows/ci.yaml",
      ".github/workflows/lint.yml",
      "action.yml",
      "one/action.yaml",
      "one/two/action.yml",
      "one/two/three/action.yaml"
    ]);
  });

  test("does not include other YAML files", async () => {
    const root = await fixture([".github/dependabot.yml", "workflow.yaml", "actions/test.yaml"]);
    expect(await discoverFiles(root)).toEqual([]);
  });

  test("explicit files replace default discovery", async () => {
    const root = await fixture([".github/workflows/ci.yaml", "custom/workflow.yaml"]);
    expect(await resolveInputFiles(root, ["custom/workflow.yaml"])).toEqual(["custom/workflow.yaml"]);
  });

  test("matches the language service document type for workflows-lab", async () => {
    expect(isActionMetadataPath(".github/workflows-lab/action.yml")).toBe(false);
  });
});
