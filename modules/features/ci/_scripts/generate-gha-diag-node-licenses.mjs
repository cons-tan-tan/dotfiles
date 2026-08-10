import { createHash } from "node:crypto";
import { builtinModules } from "node:module";
import { constants } from "node:fs";
import {
  access,
  lstat,
  readFile,
  readdir,
  realpath,
  rename,
  rm,
  writeFile,
} from "node:fs/promises";
import path from "node:path";
import process from "node:process";

const MAX_LICENSE_BYTES = 1024 * 1024;
const MAX_OUTPUT_BYTES = 16 * 1024 * 1024;
const ALLOWED_LICENSES = new Set(["Apache-2.0", "ISC", "MIT"]);
const PACKAGE_NAME = /^(?:@[a-z0-9][a-z0-9._-]*\/)?[a-z0-9][a-z0-9._-]*$/;
const VERSION = /^[0-9A-Za-z][0-9A-Za-z.+_-]*$/;
const LICENSE_FILE =
  /^(?:(?:license|licence|copying|notice)(?:[.-].*)?|third[-_.]?party[-_.]?notices?(?:[.-].*)?)$/i;
const INTERNAL_WORKSPACES = new Map([
  ["expressions", "@actions/expressions"],
  ["languageserver", "@actions/languageserver"],
  ["languageservice", "@actions/languageservice"],
  ["workflow-parser", "@actions/workflow-parser"],
]);
const NODE_BUILTINS = new Set(
  builtinModules.map((module) => module.replace(/^node:/, "")),
);

function usage() {
  throw new Error(
    "usage: generate-gha-diag-node-licenses.mjs SOURCE_ROOT PUBLISHED_BUNDLE REBUILT_BUNDLE METAFILE NOTICE INVENTORY",
  );
}

function isInside(root, candidate) {
  const relative = path.relative(root, candidate);
  return relative === "" || (!relative.startsWith("..") && !path.isAbsolute(relative));
}

function compareAscii(left, right) {
  return left < right ? -1 : left > right ? 1 : 0;
}

function sha256(contents) {
  return createHash("sha256").update(contents).digest("hex");
}

async function readJson(file) {
  const raw = await readFile(file, "utf8");
  return JSON.parse(raw);
}

async function licenseFiles(sourceRoot, packageRoot) {
  const entries = await readdir(packageRoot, { withFileTypes: true });
  let files = entries
    .filter((entry) => entry.isFile() && LICENSE_FILE.test(entry.name))
    .map((entry) => path.join(packageRoot, entry.name))
    .sort(compareAscii);

  const relativeRoot = path.relative(sourceRoot, packageRoot);
  const workspacePackage = !relativeRoot.split(path.sep).includes("node_modules");
  if (files.length === 0 && workspacePackage) {
    const repositoryLicense = path.join(sourceRoot, "LICENSE");
    await access(repositoryLicense, constants.R_OK);
    files = [repositoryLicense];
  }

  if (files.length === 0) {
    throw new Error(`package has no LICENSE, COPYING, or NOTICE file: ${packageRoot}`);
  }

  const result = [];
  for (const file of files) {
    const stats = await lstat(file);
    if (!stats.isFile() || stats.size === 0 || stats.size > MAX_LICENSE_BYTES) {
      throw new Error(`invalid license file size: ${file}`);
    }
    const text = await readFile(file, "utf8");
    if (text.includes("\0")) {
      throw new Error(`license file contains NUL: ${file}`);
    }
    result.push({
      name: path.basename(file),
      sha256: sha256(text),
      text: text.trimEnd(),
    });
  }
  return result;
}

function packagePathFromSourcePath(sourcePath) {
  const segments = sourcePath.split("/");
  const packageBoundary = segments.lastIndexOf("node_modules");
  const firstNameSegment = segments[packageBoundary + 1];
  const scoped = firstNameSegment?.startsWith("@");
  const packageEnd = packageBoundary + (scoped ? 3 : 2);
  if (
    packageBoundary < 0 ||
    packageEnd >= segments.length ||
    segments
      .slice(0, packageEnd)
      .some((segment) => !segment || segment === "." || segment === "..")
  ) {
    throw new Error(`invalid package source path: ${sourcePath}`);
  }
  const name = scoped
    ? `${firstNameSegment}/${segments[packageBoundary + 2]}`
    : firstNameSegment;
  if (!PACKAGE_NAME.test(name)) {
    throw new Error(`invalid package path in bundle: ${name}`);
  }
  return {
    name,
    packagePath: segments.slice(0, packageEnd).join("/"),
  };
}

function bundledCommentPackages(bundle) {
  const packages = new Map();
  const pattern = /^\/\/ ((?:\.\.\/)?node_modules\/[^\s]+)$/gm;
  for (const match of bundle.matchAll(pattern)) {
    const fromRepositoryRoot = match[1].startsWith("../");
    const relativeSource = fromRepositoryRoot ? match[1].slice(3) : match[1];
    const { name, packagePath } = packagePathFromSourcePath(relativeSource);
    const lockPath = fromRepositoryRoot
      ? packagePath
      : `languageserver/${packagePath}`;
    packages.set(lockPath, name);
  }
  return packages;
}

function internalOwner(sourceRoot, input) {
  for (const [workspace, name] of INTERNAL_WORKSPACES) {
    const directory = path.join(
      sourceRoot,
      workspace,
      workspace === "languageserver" ? "src" : "dist",
    );
    if (isInside(directory, input)) {
      return { name, workspace };
    }
  }
  return null;
}

async function externalOwner(sourceRoot, input) {
  const relative = path.relative(sourceRoot, input);
  if (relative.startsWith("..") || path.isAbsolute(relative)) {
    throw new Error(`bundle input resolves outside source tree: ${input}`);
  }
  const { name, packagePath } = packagePathFromSourcePath(
    relative.split(path.sep).join("/"),
  );
  const packageRoot = await realpath(path.join(sourceRoot, packagePath));
  if (!isInside(sourceRoot, packageRoot) || !isInside(packageRoot, input)) {
    throw new Error(`package input resolves outside package root: ${relative}`);
  }
  return { name, lockPath: packagePath, packageRoot };
}

async function validateInternalPackages(sourceRoot, lock) {
  for (const [workspace, expectedName] of INTERNAL_WORKSPACES) {
    const manifest = await readJson(path.join(sourceRoot, workspace, "package.json"));
    const locked = lock.packages[workspace];
    if (
      manifest.name !== expectedName ||
      locked?.name !== expectedName ||
      locked.version !== manifest.version ||
      manifest.license !== "MIT" ||
      locked.license !== "MIT" ||
      manifest.engines?.node !== ">= 20" ||
      locked.engines?.node !== ">= 20"
    ) {
      throw new Error(`workspace metadata mismatch for ${expectedName}`);
    }
    if (workspace !== "languageserver") {
      const link = lock.packages[`node_modules/${expectedName}`];
      if (!link?.link || link.resolved !== workspace) {
        throw new Error(`workspace lock link mismatch for ${expectedName}`);
      }
    }
  }
}

async function collect(sourceRoot, bundle, metafile) {
  const lockRaw = await readFile(path.join(sourceRoot, "package-lock.json"));
  const lock = JSON.parse(lockRaw.toString("utf8"));
  if (!lock.packages || typeof lock.packages !== "object") {
    throw new Error("upstream package-lock.json has no packages map");
  }
  await validateInternalPackages(sourceRoot, lock);

  const outputEntries = Object.entries(metafile.outputs ?? {});
  if (outputEntries.length !== 1) {
    throw new Error("esbuild metafile must contain exactly one output");
  }
  const [outputPath, output] = outputEntries[0];
  if (output.entryPoint !== "src/index.ts" || !output.inputs) {
    throw new Error(`unexpected esbuild output metadata: ${outputPath}`);
  }
  for (const imported of output.imports ?? []) {
    const specifier = imported.path?.replace(/^node:/, "");
    if (!imported.external || !NODE_BUILTINS.has(specifier)) {
      throw new Error(`unexpected external import in bundle: ${imported.path}`);
    }
  }

  const languageServerRoot = await realpath(path.join(sourceRoot, "languageserver"));
  const sourcePackages = new Map();
  const internalInputs = new Set();
  for (const [inputPath, inputMetadata] of Object.entries(output.inputs)) {
    const bytesInOutput = inputMetadata.bytesInOutput;
    if (!Number.isSafeInteger(bytesInOutput) || bytesInOutput < 0) {
      throw new Error(`invalid bytesInOutput for ${inputPath}`);
    }
    if (bytesInOutput === 0) {
      continue;
    }
    const input = await realpath(path.resolve(languageServerRoot, inputPath));
    if (!isInside(sourceRoot, input)) {
      throw new Error(`bundle input resolves outside source tree: ${inputPath}`);
    }
    const internal = internalOwner(sourceRoot, input);
    if (internal) {
      internalInputs.add(internal.name);
      continue;
    }

    const owner = await externalOwner(sourceRoot, input);
    const existing = sourcePackages.get(owner.lockPath);
    if (existing && existing.name !== owner.name) {
      throw new Error(`inconsistent owner for ${owner.lockPath}`);
    }
    sourcePackages.set(owner.lockPath, {
      ...owner,
      bytesInOutput: (existing?.bytesInOutput ?? 0) + bytesInOutput,
      inputCount: (existing?.inputCount ?? 0) + 1,
    });
  }
  if (!internalInputs.has("@actions/languageserver")) {
    throw new Error("metafile does not include the language server entrypoint");
  }
  if (sourcePackages.size === 0) {
    throw new Error("metafile contains no auditable third-party package inputs");
  }

  const comments = bundledCommentPackages(bundle);
  const metafilePaths = [...sourcePackages.keys()].sort(compareAscii);
  const commentPaths = [...comments.keys()].sort(compareAscii);
  if (JSON.stringify(metafilePaths) !== JSON.stringify(commentPaths)) {
    throw new Error("esbuild metafile and bundled source comments disagree");
  }
  for (const [lockPath, owner] of sourcePackages) {
    if (comments.get(lockPath) !== owner.name) {
      throw new Error(`bundle comment owner mismatch for ${lockPath}`);
    }
  }

  const packages = new Map();
  for (const owner of [...sourcePackages.values()].sort((left, right) =>
    compareAscii(left.lockPath, right.lockPath),
  )) {
    const manifest = await readJson(path.join(owner.packageRoot, "package.json"));
    if (manifest.name !== owner.name || !PACKAGE_NAME.test(manifest.name ?? "")) {
      throw new Error(`package identity mismatch for ${owner.lockPath}`);
    }
    if (!VERSION.test(manifest.version ?? "")) {
      throw new Error(`invalid package version for ${manifest.name}`);
    }
    if (!ALLOWED_LICENSES.has(manifest.license)) {
      throw new Error(
        `unreviewed license for ${manifest.name}@${manifest.version}: ${manifest.license ?? "missing"}`,
      );
    }

    const locked = lock.packages[owner.lockPath];
    if (!locked || locked.version !== manifest.version) {
      throw new Error(`package-lock version mismatch for ${owner.lockPath}`);
    }
    const hasResolved = typeof locked.resolved === "string";
    const hasIntegrity = typeof locked.integrity === "string";
    if (
      hasResolved !== hasIntegrity ||
      (hasResolved && !locked.resolved.startsWith("https://registry.npmjs.org/")) ||
      (hasIntegrity && !locked.integrity.startsWith("sha512-"))
    ) {
      throw new Error(`untrusted lock source for ${owner.lockPath}`);
    }

    const key = `${manifest.name}@${manifest.version}`;
    const item = {
      name: manifest.name,
      version: manifest.version,
      license: manifest.license,
      lockPath: owner.lockPath,
      resolved: locked.resolved ?? null,
      integrity: locked.integrity ?? null,
      bytesInOutput: owner.bytesInOutput,
      inputCount: owner.inputCount,
      files: await licenseFiles(sourceRoot, owner.packageRoot),
    };
    const previous = packages.get(key);
    if (previous && JSON.stringify(previous) !== JSON.stringify(item)) {
      throw new Error(`inconsistent duplicate package metadata: ${key}`);
    }
    packages.set(key, item);
  }

  const esbuild = lock.packages["node_modules/esbuild"];
  if (!VERSION.test(esbuild?.version ?? "") || !esbuild.integrity?.startsWith("sha512-")) {
    throw new Error("package-lock has no auditable esbuild version");
  }
  return {
    packages: [...packages.values()].sort(
      (left, right) =>
        compareAscii(left.name, right.name) || compareAscii(left.version, right.version),
    ),
    packageLockSha256: sha256(lockRaw),
    esbuildVersion: esbuild.version,
    internalPackages: [...internalInputs].sort(compareAscii),
  };
}

function render(packages, sourceRevision) {
  const sections = [
    "Third-party license notices for packages embedded in the @actions/languageserver bundle.",
    "",
    `Upstream source revision: ${sourceRevision}`,
    "This file is generated from a verified esbuild metafile and the upstream package-lock.json.",
    "Do not edit it manually.",
  ];

  for (const item of packages) {
    sections.push(
      "",
      "================================================================================",
      `Package: ${item.name}@${item.version}`,
      `Declared license: ${item.license}`,
    );
    for (const file of item.files) {
      sections.push("", `--- ${file.name} ---`, "", file.text);
    }
  }
  sections.push("");
  return sections.join("\n");
}

async function atomicWrite(output, contents) {
  const temporary = `${output}.tmp-${process.pid}`;
  try {
    await writeFile(temporary, contents, { encoding: "utf8", mode: 0o644 });
    await rename(temporary, output);
  } finally {
    await rm(temporary, { force: true });
  }
}

async function main() {
  if (process.argv.length !== 8) {
    usage();
  }
  const sourceRoot = await realpath(process.argv[2]);
  const publishedBundlePath = path.resolve(process.argv[3]);
  const rebuiltBundlePath = path.resolve(process.argv[4]);
  const metafilePath = path.resolve(process.argv[5]);
  const noticeOutput = path.resolve(process.argv[6]);
  const inventoryOutput = path.resolve(process.argv[7]);
  const revision = (await readFile(path.join(sourceRoot, ".git", "HEAD"), "utf8")).trim();
  if (!/^[0-9a-f]{40}$/.test(revision)) {
    throw new Error("source checkout must have a detached 40-character git HEAD");
  }

  const publishedBundle = await readFile(publishedBundlePath);
  const rebuiltBundle = await readFile(rebuiltBundlePath);
  if (
    publishedBundle.length === 0 ||
    publishedBundle.length > MAX_OUTPUT_BYTES ||
    !publishedBundle.equals(rebuiltBundle)
  ) {
    throw new Error("rebuilt bundle does not byte-for-byte match the published bundle");
  }
  const metafileRaw = await readFile(metafilePath);
  if (metafileRaw.length === 0 || metafileRaw.length > MAX_OUTPUT_BYTES) {
    throw new Error("invalid esbuild metafile size");
  }
  const metafile = JSON.parse(metafileRaw.toString("utf8"));
  const evidence = await collect(sourceRoot, rebuiltBundle.toString("utf8"), metafile);
  if (evidence.packages.length === 0) {
    throw new Error("no production dependencies were discovered");
  }
  const rendered = render(evidence.packages, revision);
  if (Buffer.byteLength(rendered) > MAX_OUTPUT_BYTES) {
    throw new Error(`generated notice exceeds ${MAX_OUTPUT_BYTES} bytes`);
  }
  const inventory = `${JSON.stringify(
    {
      schemaVersion: "gha-diag-node-licenses-v2",
      upstreamRevision: revision,
      packageLockSha256: evidence.packageLockSha256,
      bundleSha256: sha256(publishedBundle),
      reproduction: {
        byteForByte: true,
        esbuildVersion: evidence.esbuildVersion,
        metafileSha256: sha256(metafileRaw),
      },
      internalPackages: evidence.internalPackages,
      packages: evidence.packages.map((item) => ({
        name: item.name,
        version: item.version,
        license: item.license,
        lockPath: item.lockPath,
        resolved: item.resolved,
        integrity: item.integrity,
        bytesInOutput: item.bytesInOutput,
        inputCount: item.inputCount,
        files: item.files.map(({ name, sha256: digest }) => ({
          name,
          sha256: digest,
        })),
      })),
    },
    null,
    2,
  )}\n`;

  await atomicWrite(noticeOutput, rendered);
  await atomicWrite(inventoryOutput, inventory);
}

main().catch((error) => {
  process.stderr.write(`gha-diag license generator: ${error.message}\n`);
  process.exitCode = 1;
});
