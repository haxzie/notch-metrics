import { existsSync } from "node:fs";
import { mkdir, readFile, readdir, rm, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join, resolve } from "node:path";
import { PluginManifest } from "@notch/schemas";

/** Where the Swift app looks, and where the MCP server writes. One constant. */
export function metricsRoot(): string {
  return (
    process.env.NOTCH_METRICS_ROOT ??
    join(homedir(), "Library", "Application Support", "NotchMetrics", "metrics")
  );
}

/**
 * Validates an id *before* it is ever joined onto a path.
 *
 * The id becomes a directory name, and the MCP server that supplies it is
 * driven by an agent. `../../.ssh` would otherwise be a write to anywhere in
 * the user's home directory, reached through a tool call nobody reviewed.
 */
const ID = /^[a-z0-9][a-z0-9-]{1,47}$/;

export function assertSafeId(id: string): void {
  if (!ID.test(id)) {
    throw new Error(`"${id}" is not a valid metric id. Use lowercase letters, digits and hyphens.`);
  }
  // Belt and braces: even if the regex were loosened, resolve() must stay put.
  const root = resolve(metricsRoot());
  const target = resolve(join(root, id));
  if (!target.startsWith(`${root}/`)) {
    throw new Error(`"${id}" escapes the metrics directory`);
  }
}

export function metricDir(id: string): string {
  assertSafeId(id);
  return join(metricsRoot(), id);
}

export interface StoredMetric {
  id: string;
  dir: string;
  manifest: PluginManifest;
  source: string;
}

export interface BrokenMetric {
  id: string;
  dir: string;
  error: string;
}

export async function readMetric(id: string): Promise<StoredMetric> {
  const dir = metricDir(id);
  const raw: unknown = JSON.parse(await readFile(join(dir, "manifest.json"), "utf8"));
  const manifest = PluginManifest.parse(raw);
  const source = await readFile(join(dir, manifest.entry), "utf8");
  return { id, dir, manifest, source };
}

/**
 * Lists every metric, and every *broken* metric with the reason.
 *
 * Silently skipping an unparseable manifest is how a user ends up staring at a
 * settings pane that does not list the metric their agent just wrote, with
 * nothing anywhere saying why.
 */
export async function listMetrics(): Promise<{ ok: StoredMetric[]; broken: BrokenMetric[] }> {
  const root = metricsRoot();
  if (!existsSync(root)) return { ok: [], broken: [] };

  const entries = await readdir(root, { withFileTypes: true });
  const ok: StoredMetric[] = [];
  const broken: BrokenMetric[] = [];

  for (const entry of entries) {
    if (!entry.isDirectory() || entry.name.startsWith(".")) continue;
    try {
      ok.push(await readMetric(entry.name));
    } catch (error) {
      broken.push({
        id: entry.name,
        dir: join(root, entry.name),
        error: error instanceof Error ? error.message : String(error),
      });
    }
  }

  return { ok, broken };
}

export async function writeMetric(
  manifest: PluginManifest,
  source: string,
  options: { staging?: boolean } = {},
): Promise<string> {
  assertSafeId(manifest.id);
  // Staging is why a bad edit cannot blank a working widget: the live directory
  // stays byte-identical until the new version has produced a real number.
  const dir = options.staging
    ? join(metricsRoot(), ".staging", manifest.id)
    : metricDir(manifest.id);

  await mkdir(dir, { recursive: true });
  await writeFile(join(dir, "manifest.json"), `${JSON.stringify(manifest, null, 2)}\n`, "utf8");
  await writeFile(join(dir, manifest.entry), source, "utf8");
  return dir;
}

export async function promoteStaged(id: string): Promise<string> {
  const staged = join(metricsRoot(), ".staging", id);
  const live = metricDir(id);
  const manifest = PluginManifest.parse(
    JSON.parse(await readFile(join(staged, "manifest.json"), "utf8")),
  );
  const source = await readFile(join(staged, manifest.entry), "utf8");

  await mkdir(live, { recursive: true });
  await writeFile(join(live, "manifest.json"), `${JSON.stringify(manifest, null, 2)}\n`, "utf8");
  await writeFile(join(live, manifest.entry), source, "utf8");
  await rm(staged, { recursive: true, force: true });
  return live;
}

export async function removeMetric(id: string): Promise<void> {
  await rm(metricDir(id), { recursive: true, force: true });
}
