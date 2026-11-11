import assert from 'node:assert/strict';
import { test } from 'node:test';
import { rewriteReferences } from '../_packages/modern-web-guidance/rewrite-references.mjs';

test('rewrites guide links and bundled CLI messages without changing arguments', () => {
  assert.equal(
    rewriteReferences('Read `npx -y modern-web-guidance@latest retrieve "dialog"`.\nconst hint = `npx modern-web-guidance retrieve ${id}`;'),
    'Read `modern-web-guidance retrieve "dialog"`.\nconst hint = `modern-web-guidance retrieve ${id}`;',
  );
  assert.equal(rewriteReferences('pnpx modern-web-guidance@latest list'), 'modern-web-guidance list');
});

test('preserves unrelated tools and similarly named packages', () => {
  const text = 'npx -y another-tool\nnpx modern-web-guidance-extra list\nconst child = spawnSync("npx", args);';
  assert.equal(rewriteReferences(text), text);
});

test('rejects unknown runner syntax and newly versioned references', () => {
  for (const text of [
    'pnpm dlx modern-web-guidance@latest retrieve "dialog"',
    'npx --package modern-web-guidance modern-web-guidance list',
    'npx modern-web-guidance@next list',
  ]) {
    assert.throws(() => rewriteReferences(text), /unhandled package runner reference/);
  }
});
