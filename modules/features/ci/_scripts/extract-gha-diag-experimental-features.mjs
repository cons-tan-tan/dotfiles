import { pathToFileURL } from "node:url";

const [modulePath] = process.argv.slice(2);
if (!modulePath) {
  throw new Error("usage: extract-gha-diag-experimental-features.mjs MODULE");
}

const imported = await import(pathToFileURL(modulePath).href);
if (typeof imported.FeatureFlags !== "function") {
  throw new Error("@actions/expressions does not export FeatureFlags");
}

const features = new imported.FeatureFlags({ all: true }).getEnabledFeatures();
if (
  !Array.isArray(features) ||
  features.some(
    (feature) =>
      typeof feature !== "string" ||
      !/^[A-Za-z][A-Za-z0-9._-]{0,127}$/.test(feature),
  )
) {
  throw new Error("@actions/expressions returned invalid experimental feature names");
}

const unique = [...new Set(features)].sort();
if (unique.length !== features.length) {
  throw new Error("@actions/expressions returned duplicate experimental feature names");
}

for (const feature of unique) {
  const enabledWithOverride = new imported.FeatureFlags({
    all: true,
    [feature]: false,
  }).getEnabledFeatures();
  if (
    !Array.isArray(enabledWithOverride) ||
    enabledWithOverride.includes(feature)
  ) {
    throw new Error(
      `@actions/expressions experimental feature cannot be disabled: ${feature}`,
    );
  }
}

process.stdout.write(`${JSON.stringify(unique)}\n`);
