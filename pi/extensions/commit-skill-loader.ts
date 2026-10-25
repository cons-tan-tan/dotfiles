import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const SELECTOR = "@commitProfileSelector@";
const ARTIFACTS = "@commitProfileArtifacts@";

export default function (pi: ExtensionAPI) {
  pi.on("resources_discover", async (_event, ctx) => {
    const result = await pi.exec(SELECTOR, ["--cwd", ctx.cwd]);
    const profile = result.stdout.trim();
    if (
      result.code !== 0 ||
      (profile !== "standard" && profile !== "fine-grained")
    ) {
      throw new Error(
        `Cannot select commit skill: ${result.stderr || result.stdout}`,
      );
    }
    return { skillPaths: [`${ARTIFACTS}/${profile}/.claude/skills/commit`] };
  });
}
