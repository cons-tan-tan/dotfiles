import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const HERDR_SKILL_PATH = "@herdrSkillPath@";

export default function (pi: ExtensionAPI) {
  pi.on("resources_discover", async () => {
    if (process.env.HERDR_ENV !== "1") return;

    return {
      skillPaths: [HERDR_SKILL_PATH],
    };
  });
}
