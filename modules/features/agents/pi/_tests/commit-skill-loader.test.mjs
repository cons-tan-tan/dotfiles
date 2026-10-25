import assert from "node:assert/strict";
import { existsSync } from "node:fs";
import { pathToFileURL } from "node:url";

const { default: register } = await import(pathToFileURL(process.argv[2]).href);
let discover;
let response;
const cwd = "/workspace with spaces/project";
register({
  on(event, handler) {
    assert.equal(event, "resources_discover");
    discover = handler;
  },
  async exec(command, args) {
    assert.equal(command, process.argv[3]);
    assert.deepEqual(args, ["--cwd", cwd]);
    return response;
  },
});

for (const profile of ["standard", "fine-grained", "standard"]) {
  response = { code: 0, stdout: `${profile}\n`, stderr: "" };
  const resources = await discover({}, { cwd });
  assert.equal(resources.skillPaths.length, 1);
  assert.ok(resources.skillPaths[0].endsWith(`/${profile}/.claude/skills/commit`));
  assert.ok(existsSync(`${resources.skillPaths[0]}/SKILL.md`));
}
for (const failure of [
  { code: 1, stdout: "", stderr: "selector failed" },
  { code: 0, stdout: "unexpected-profile", stderr: "" },
]) {
  response = failure;
  await assert.rejects(discover({}, { cwd }), /Cannot select commit skill/);
}
