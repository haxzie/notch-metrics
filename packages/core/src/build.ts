import { writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { LocalConnectorManifest } from "./connector.ts";
import { assertValid } from "./validate.ts";
import type { App } from "./define.ts";

/**
 * `notch-metrics build`: writes `manifest.json` from the connector's own code.
 *
 * The manifest used to be hand-written beside the code, which meant every
 * metric existed twice: once as JSON and once as a branch in `fetchMetric`.
 * An id spelled two ways was a tile that never filled, and the JSON was
 * always the copy that went stale.
 *
 * So the code is the source and this emits the file. Note *where* it runs:
 * on the author's machine, before the app is ever loaded. The Mac app still
 * finds a `manifest.json` on disk and still reads an app's grants without
 * executing a line of it, which is the property that lets you see what an
 * app wants before you approve it. Deriving the manifest at install time
 * instead would mean running the app to find out what it wanted.
 *
 * Importing the entry does execute it, which is why `createApp` is the only
 * thing that should happen at module scope. A connector that opens a socket
 * on import is a connector that opens a socket during its own build.
 */
export interface BuildResult {
  manifestPath: string;
  manifest: LocalConnectorManifest;
  metricIds: string[];
}

export async function buildManifest(entryPath: string): Promise<BuildResult> {
  const absolute = resolve(entryPath);
  // Cache-busted so a second build in one process sees the edit, which is
  // what a watch mode would otherwise miss.
  const module = (await import(`${pathToFileURL(absolute).href}?t=${Date.now()}`)) as {
    default?: App;
  };

  const app = module.default;
  if (!app || typeof app !== "object" || !("manifest" in app)) {
    throw new Error(
      `${entryPath} must default-export createApp({ ... }). Found ${app === undefined ? "no default export" : typeof app}.`,
    );
  }

  // Validated again rather than trusted. `createApp` checks what it was
  // given, but the file imported here is whatever is on disk, and a build
  // output somebody has hand-edited is exactly the case this catches.
  const manifest = assertValid(
    LocalConnectorManifest,
    app.manifest,
    `The manifest built from ${entryPath}`,
  );

  // Timestamps are set here, not in `createApp`. A manifest that embedded
  // `new Date()` at module scope would differ on every build, so a rebuild
  // with no source change would show up as a diff.
  const now = new Date().toISOString();
  const existing = manifest.createdAt === new Date(0).toISOString() ? now : manifest.createdAt;
  const emitted: LocalConnectorManifest = {
    ...manifest,
    createdAt: existing,
    updatedAt: now,
  };

  const manifestPath = join(dirname(absolute), "manifest.json");
  writeFileSync(manifestPath, `${JSON.stringify(emitted, null, 2)}\n`);

  return {
    manifestPath,
    manifest: emitted,
    metricIds: emitted.metrics.map((metric) => metric.id),
  };
}
