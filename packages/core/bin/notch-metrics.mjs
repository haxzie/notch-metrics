#!/usr/bin/env node
// The connector author's one command: `notch-metrics build`.
//
// Kept to a single verb on purpose. The only thing a connector needs that it
// cannot do by editing a file is turning its own code into the manifest the
// Mac app reads, and a CLI that grows a scaffolder and a test runner is a
// CLI somebody has to learn.
import { buildManifest } from "../dist/build.js";

const [verb, entry = "connector.mjs"] = process.argv.slice(2);

if (verb !== "build") {
  console.error(
    "Usage: notch-metrics build [entry]\n\nWrites manifest.json from the entry's default export.",
  );
  process.exit(1);
}

try {
  const { manifestPath, metricIds } = await buildManifest(entry);
  console.log(`Wrote ${manifestPath}`);
  console.log(
    `${metricIds.length} metric${metricIds.length === 1 ? "" : "s"}: ${metricIds.join(", ")}`,
  );
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
}
