import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, openSync, closeSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const [binary, skillRoot, version] = process.argv.slice(2);
const work = mkdtempSync(join(tmpdir(), 'modern-web-guidance-check-'));
const env = { ...process.env, PATH: '/no-package-runners', DISABLE_TELEMETRY: '1' };
function run(args) {
  const result = spawnSync(binary, args, { cwd: work, env, encoding: 'utf8', timeout: 30000 });
  assert.ifError(result.error);
  assert.equal(result.status, 0, result.stderr);
  return result.stdout;
}

assert.equal(run(['--version']).trim(), version);
const results = JSON.parse(run(['search', 'confirmation modal dialog']));
assert.ok(results.length > 0);
const catalog = JSON.parse(readFileSync(join(skillRoot, 'gen/guides.json'), 'utf8'));
assert.ok(results.every(result => catalog.some(guide => guide.id === result.id)));
// Search ranking can change without breaking the package. Choose a separate
// guide with a cross-reference to exercise retrieval independently of ranking.
const linked = catalog.find(guide =>
  !guide.originTrials?.length && !guide.volatileFeatures?.length &&
  readFileSync(join(skillRoot, 'guides', guide.category, `${guide.id}.md`), 'utf8').includes('modern-web-guidance retrieve'),
);
assert.ok(linked, 'Expected a retrievable guide with a cross-reference');
const outputPath = join(work, 'retrieved.md');
const output = openSync(outputPath, 'w');
const retrieved = spawnSync(binary, ['retrieve', linked.id], {
  cwd: work, env, encoding: 'utf8', stdio: ['ignore', output, 'pipe'], timeout: 30000,
});
closeSync(output);
assert.ifError(retrieved.error);
assert.equal(retrieved.status, 0, retrieved.stderr);
const guide = readFileSync(outputPath, 'utf8');
assert.ok(guide.includes(`--- Guide for ${linked.id} ---`));
assert.ok(guide.includes('modern-web-guidance retrieve'));
assert.ok(!guide.includes('npx'));

mkdirSync(join(work, 'scan-target'));
writeFileSync(join(work, 'scan-target/index.html'), '<!doctype html><html lang="en"><title>Test</title><body><p>Test</p></body></html>');
const scan = JSON.parse(run(['legacy-scan', join(work, 'scan-target'), '--json']));
assert.ok(scan && typeof scan === 'object');

const gated = catalog.find(guide => guide.originTrials?.length || guide.volatileFeatures?.length);
assert.ok(gated, 'Expected a guide that exercises the opt-in error path');
const denied = spawnSync(binary, ['retrieve', gated.id], { cwd: work, env, encoding: 'utf8', timeout: 30000 });
assert.ifError(denied.error);
assert.equal(denied.status, 1);
assert.ok(denied.stderr.includes('modern-web-guidance set-allow-'));
assert.ok(!denied.stderr.includes('npx'));
console.log('Search, retrieval, scanning, and opt-in guidance work without package runners.');
