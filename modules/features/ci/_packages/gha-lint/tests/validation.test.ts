import { afterEach, describe, expect, test } from "bun:test";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { validateFile } from "../src/validator.ts";

const roots: string[] = [];

afterEach(async () => {
  await Promise.all(roots.splice(0).map(root => rm(root, { recursive: true, force: true })));
});

async function repository(files: Record<string, string>): Promise<string> {
  const root = await mkdtemp(join(tmpdir(), "gha-lint-validation-"));
  roots.push(root);
  for (const [path, content] of Object.entries(files)) {
    const absolute = join(root, path);
    await mkdir(dirname(absolute), { recursive: true });
    await writeFile(absolute, content);
  }
  return root;
}

const parallelWorkflow = `on: push
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - parallel:
          - run: echo one
          - run: echo two
      - id: server
        run: echo server
        background: true
      - wait: server
      - wait-all:
      - cancel: server
`;

describe("validation stack", () => {
  test("accepts parallel and background workflow syntax", async () => {
    const root = await repository({ ".github/workflows/parallel.yaml": parallelWorkflow });
    expect(await validateFile(root, ".github/workflows/parallel.yaml")).toEqual([]);
  });

  test("routes standalone action metadata to the action validators", async () => {
    const root = await repository({
      "actions/example/action.yml": `name: Example
description: Example action
runs:
  using: composite
  steps:
    - run: echo ok
      shell: bash
`
    });
    expect(await validateFile(root, "actions/example/action.yml")).toEqual([]);
  });

  test("rejects invalid action metadata", async () => {
    const root = await repository({
      "action.yml": `name: Missing description
runs:
  using: node24
  main: index.js
`
    });
    const diagnostics = await validateFile(root, "action.yml");
    expect(diagnostics.some(diagnostic => diagnostic.message.includes("description"))).toBe(true);
  });

  test("validates needs and matrix expression context", async () => {
    const root = await repository({
      ".github/workflows/context.yaml": `on: push
jobs:
  build:
    needs: missing
    strategy:
      matrix:
        os: [ubuntu-latest]
    runs-on: \${{ matrix.os }}
    steps:
      - run: echo ok
`
    });
    const diagnostics = await validateFile(root, ".github/workflows/context.yaml");
    expect(diagnostics.some(diagnostic => diagnostic.message.includes("missing"))).toBe(true);
    expect(diagnostics.some(diagnostic => diagnostic.message.includes("matrix.os"))).toBe(false);
  });

  test("reports SchemaStore and official diagnostics with source positions", async () => {
    const root = await repository({
      ".github/workflows/invalid.yaml": `on: push
unknown-key: true
jobs:
  build:
    runs-on: ubuntu-latest
`
    });
    const diagnostics = await validateFile(root, ".github/workflows/invalid.yaml");
    expect(diagnostics.some(diagnostic => diagnostic.source === "actions-language-service")).toBe(true);
    expect(diagnostics.some(diagnostic => diagnostic.source === "schemastore")).toBe(true);
    expect(diagnostics.every(diagnostic => diagnostic.line > 0 && diagnostic.column > 0)).toBe(true);
  });

  test("checks self-repository reusable workflow required inputs", async () => {
    const root = await repository({
      ".github/workflows/caller.yaml": `on: push
jobs:
  call:
    uses: $/.github/workflows/callee.yaml
`,
      ".github/workflows/callee.yaml": `on:
  workflow_call:
    inputs:
      name:
        required: true
        type: string
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - run: echo ok
`
    });
    const diagnostics = await validateFile(root, ".github/workflows/caller.yaml");
    expect(diagnostics.some(diagnostic => diagnostic.message.includes("Input name is required"))).toBe(true);
  });

  test("keeps local reusable input checks when the callee has warnings", async () => {
    const root = await repository({
      ".github/workflows/caller.yaml": `on: push
jobs:
  call:
    uses: ./.github/workflows/callee.yaml
`,
      ".github/workflows/callee.yaml": `on:
  workflow_call:
    inputs:
      name:
        required: true
        type: string
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: owner/action@abcdef0
`
    });
    const diagnostics = await validateFile(root, ".github/workflows/caller.yaml");
    expect(diagnostics.some(diagnostic => diagnostic.message.includes("Input name is required"))).toBe(true);
  });

  test("does not fetch or reject remote reusable workflow metadata", async () => {
    const root = await repository({
      ".github/workflows/remote.yaml": `on: push
jobs:
  call:
    uses: owner/repository/.github/workflows/build.yaml@main
    with:
      arbitrary-input: value
`
    });
    const diagnostics = await validateFile(root, ".github/workflows/remote.yaml");
    expect(diagnostics.some(diagnostic => diagnostic.message.includes("Unable to find reusable workflow"))).toBe(false);
  });

  test("keeps local reusable input checks when remote calls are present", async () => {
    const root = await repository({
      ".github/workflows/caller.yaml": `on: push
jobs:
  local:
    uses: ./.github/workflows/callee.yaml
  remote:
    uses: owner/repository/.github/workflows/build.yaml@main
    with:
      arbitrary-input: value
`,
      ".github/workflows/callee.yaml": `on:
  workflow_call:
    inputs:
      name:
        required: true
        type: string
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - run: echo ok
`
    });
    const diagnostics = await validateFile(root, ".github/workflows/caller.yaml");
    expect(diagnostics.some(diagnostic => diagnostic.message.includes("Input name is required"))).toBe(true);
    expect(diagnostics.some(diagnostic => diagnostic.message.includes("Unable to find reusable workflow"))).toBe(false);
  });

  test("does not attribute an invalid local callee to its caller", async () => {
    const root = await repository({
      ".github/workflows/caller.yaml": `on: push
jobs:
  call:
    uses: ./.github/workflows/callee.yaml
`,
      ".github/workflows/callee.yaml": "on: [\njobs: {}\n"
    });
    const diagnostics = await validateFile(root, ".github/workflows/caller.yaml");
    expect(diagnostics.some(diagnostic => diagnostic.message.includes("Unable to find reusable workflow"))).toBe(
      true
    );
    expect(diagnostics.some(diagnostic => diagnostic.line > 5)).toBe(false);
  });

  test("resolves self-repository actions without a reusable workflow job", async () => {
    const root = await repository({
      ".github/workflows/self-action.yaml": `on: push
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: $/.github/actions/missing
`
    });
    const diagnostics = await validateFile(root, ".github/workflows/self-action.yaml");
    expect(diagnostics.some(diagnostic => diagnostic.message.includes("Unable to resolve action"))).toBe(true);
  });

  test("validates inputs for self-repository actions", async () => {
    const root = await repository({
      ".github/workflows/self-action.yaml": `on: push
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: $/.github/actions/example
`,
      ".github/actions/example/action.yml": `name: Example
description: Example action
inputs:
  required-input:
    description: Required input
    required: true
runs:
  using: composite
  steps:
    - shell: bash
      run: echo ok
`
    });
    const diagnostics = await validateFile(root, ".github/workflows/self-action.yaml");
    expect(diagnostics.some(diagnostic => diagnostic.message.includes("Missing required input"))).toBe(true);
    expect(diagnostics.some(diagnostic => diagnostic.message.includes("Unable to resolve action"))).toBe(false);
  });

  test("reports malformed self-repository actions as lint diagnostics", async () => {
    const root = await repository({
      ".github/workflows/self-action.yaml": `on: push
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: $/.github/actions/example
`,
      ".github/actions/example/action.yml": "name: [\nruns: {}\n"
    });
    const diagnostics = await validateFile(root, ".github/workflows/self-action.yaml");
    expect(diagnostics.some(diagnostic => diagnostic.message.includes("Unable to resolve action"))).toBe(true);
  });

  test("runs ShellCheck for literal workflow scripts", async () => {
    const root = await repository({
      ".github/workflows/shell.yaml": `on: push
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - run: |
          value="hello world"
          echo $value
`
    });
    const diagnostics = await validateFile(root, ".github/workflows/shell.yaml");
    const finding = diagnostics.find(diagnostic => diagnostic.code === "SC2086");
    expect(finding?.source).toBe("shellcheck");
    expect(finding?.line).toBe(8);
  });

  test("runs ShellCheck inside parallel steps", async () => {
    const root = await repository({
      ".github/workflows/parallel-shell.yaml": `on: push
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - parallel:
          - run: |
              value="hello world"
              echo $value
`
    });
    const diagnostics = await validateFile(root, ".github/workflows/parallel-shell.yaml");
    expect(diagnostics.some(diagnostic => diagnostic.code === "SC2086")).toBe(true);
  });

  test("runs ShellCheck inside composite actions", async () => {
    const root = await repository({
      "action.yaml": `name: Shell fixture
description: Shell fixture
runs:
  using: composite
  steps:
    - shell: sh
      run: |
        value="hello world"
        echo $value
`
    });
    const diagnostics = await validateFile(root, "action.yaml");
    expect(diagnostics.some(diagnostic => diagnostic.code === "SC2086")).toBe(true);
  });

  test("reports YAML parser positions", async () => {
    const root = await repository({
      ".github/workflows/yaml.yaml": "on: push\njobs: [\n"
    });
    const diagnostics = await validateFile(root, ".github/workflows/yaml.yaml");
    expect(diagnostics.some(diagnostic => diagnostic.source === "yaml" && diagnostic.line > 0)).toBe(true);
  });

  test("skips the default shell on Windows runners", async () => {
    const root = await repository({
      ".github/workflows/windows.yaml": `on: push
jobs:
  build:
    runs-on: windows-latest
    steps:
      - run: Write-Output $env:PATH
`
    });
    const diagnostics = await validateFile(root, ".github/workflows/windows.yaml");
    expect(diagnostics.some(diagnostic => diagnostic.source === "shellcheck")).toBe(false);
  });

  test("skips the default shell when self-hosted labels do not identify an OS", async () => {
    const root = await repository({
      ".github/workflows/self-hosted.yaml": `on: push
jobs:
  build:
    runs-on: self-hosted
    steps:
      - run: Write-Output $env:PATH
`
    });
    const diagnostics = await validateFile(root, ".github/workflows/self-hosted.yaml");
    expect(diagnostics.some(diagnostic => diagnostic.source === "shellcheck")).toBe(false);
  });

  test("skips dynamic and custom shells instead of inheriting Bash", async () => {
    const root = await repository({
      ".github/workflows/dynamic-shell.yaml": `on: push
defaults:
  run:
    shell: \${{ inputs.shell }}
jobs:
  build:
    strategy:
      matrix:
        shell: [pwsh]
    runs-on: ubuntu-latest
    steps:
      - shell: \${{ matrix.shell }}
        run: Write-Output $env:PATH
      - shell: python
        run: print(undefined_name)
`
    });
    const diagnostics = await validateFile(root, ".github/workflows/dynamic-shell.yaml");
    expect(diagnostics.some(diagnostic => diagnostic.source === "shellcheck")).toBe(false);
  });

  test("reads static labels from mapping-form runs-on", async () => {
    const root = await repository({
      ".github/workflows/windows-group.yaml": `on: push
jobs:
  build:
    runs-on:
      group: managed
      labels: windows-latest
    steps:
      - run: Write-Output $env:PATH
`
    });
    const diagnostics = await validateFile(root, ".github/workflows/windows-group.yaml");
    expect(diagnostics.some(diagnostic => diagnostic.source === "shellcheck")).toBe(false);
  });

  test("keeps ShellCheck positions across GitHub expressions", async () => {
    const root = await repository({
      ".github/workflows/expression-shell.yaml": `on: push
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - run: |
          value="hello world \${{ github.ref }}"
          echo $value
`
    });
    const diagnostics = await validateFile(root, ".github/workflows/expression-shell.yaml");
    const finding = diagnostics.find(diagnostic => diagnostic.code === "SC2086");
    expect(finding?.line).toBe(8);
  });

  test("does not follow sourced files from inline scripts", async () => {
    const root = await repository({
      ".github/workflows/source.yaml": `on: push
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - run: source scripts/helper.sh
`,
      "scripts/helper.sh": "value='hello world'\necho $value\n"
    });
    const diagnostics = await validateFile(root, ".github/workflows/source.yaml");
    expect(diagnostics.some(diagnostic => diagnostic.code === "SC2086")).toBe(false);
  });

  test("keeps schema diagnostics near an aliased mapping", async () => {
    const root = await repository({
      ".github/workflows/alias.yaml": `on: push
jobs:
  template: &template
    runs-on: ubuntu-latest
    unknown-job-key: true
  build: *template
`
    });
    const diagnostics = await validateFile(root, ".github/workflows/alias.yaml");
    const finding = diagnostics.find(
      diagnostic => diagnostic.source === "schemastore" && diagnostic.message.includes("unknown-job-key")
    );
    expect(finding?.line).not.toBe(1);
  });
});
