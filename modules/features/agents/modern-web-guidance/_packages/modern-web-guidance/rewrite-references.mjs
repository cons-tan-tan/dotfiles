import assert from 'node:assert/strict';
import { readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

// Only this package's invocation is adapted; other npm examples remain intact.
const invocation = /\b(?:npx(?:\.cmd)?(?:[ \t]+(?:-y|--yes))?|pnpx)[ \t]+modern-web-guidance(?:@latest)?(?=$|[\s`"'\\])/g;
const unhandled = /\b(?:npx(?:\.cmd)?|pnpx|pnpm[ \t]+dlx|npm[ \t]+exec)[ \t]+[^\r\n`]*\bmodern-web-guidance(?:@[^\s`"'\\]*)?(?=$|[\s`"'\\])/;

export function rewriteReferences(text) {
  const rewritten = text.replace(invocation, 'modern-web-guidance');
  assert.ok(!unhandled.test(rewritten), 'modern-web-guidance: unhandled package runner reference');
  return rewritten;
}

function rewriteTree(root) {
  let changedFiles = 0;
  for (const entry of readdirSync(root, { withFileTypes: true })) {
    const path = join(root, entry.name);
    if (entry.isDirectory()) changedFiles += rewriteTree(path);
    // SKILL.md is rendered separately through the shared skill consumer.
    if (!entry.isFile() || entry.name === 'SKILL.md' || !/\.(md|mjs)$/.test(entry.name)) continue;
    const original = readFileSync(path, 'utf8');
    const rewritten = rewriteReferences(original);
    if (rewritten !== original) {
      writeFileSync(path, rewritten);
      changedFiles++;
    }
  }
  return changedFiles;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const count = rewriteTree(process.argv[2]);
  assert.ok(count > 0, 'modern-web-guidance: upstream reference format changed; review the adapter');
  console.log(`Adapted local CLI references in ${count} files.`);
}
