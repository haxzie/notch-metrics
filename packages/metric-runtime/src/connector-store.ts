import { existsSync } from "node:fs";
import { mkdir, readFile, readdir, rename, rm, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join, resolve } from "node:path";
import { LocalConnectorManifest } from "@notch/schemas";

/**
 * Where registered connectors live.
 *
 * Beside `metrics/`, not inside it: the app discovers the two separately and
 * a `PluginManifest` is not a `LocalConnectorManifest`. Mixing them would mean
 * every scan guessing which kind of thing it had found.
 */
export function connectorsRoot(): string {
  return (
    process.env.NOTCH_CONNECTORS_ROOT ??
    join(homedir(), "Library", "Application Support", "NotchMetrics", "connectors")
  );
}

/**
 * Validates an id before it is joined onto a path.
 *
 * The id becomes a directory name and comes from an agent, so `../../.ssh` is
 * a write anywhere in the user's home through a tool call nobody reviewed.
 */
const ID = /^[a-z0-9][a-z0-9-]{1,47}$/;

export function assertSafeConnectorId(id: string): void {
  if (!ID.test(id)) {
    throw new Error(
      `"${id}" is not a valid connector id. Use lowercase letters, digits and hyphens.`,
    );
  }
  const root = resolve(connectorsRoot());
  const target = resolve(join(root, id));
  if (!target.startsWith(`${root}/`)) {
    throw new Error(`"${id}" escapes the connectors directory`);
  }
}

export function connectorDir(id: string): string {
  assertSafeConnectorId(id);
  return join(connectorsRoot(), id);
}

function stagingDir(id: string): string {
  assertSafeConnectorId(id);
  return join(connectorsRoot(), ".staging", id);
}

/**
 * Writes a candidate into staging.
 *
 * Nothing reaches the live directory until it has verified and produced a
 * real number — the live copy stays byte-identical, so a bad edit cannot
 * blank a working set of tiles.
 */
export async function writeConnector(
  manifest: LocalConnectorManifest,
  source: string,
  options: { staging?: boolean } = {},
): Promise<string> {
  const dir = options.staging ? stagingDir(manifest.id) : connectorDir(manifest.id);
  await mkdir(dir, { recursive: true });
  await writeFile(join(dir, "manifest.json"), `${JSON.stringify(manifest, null, 2)}\n`, "utf8");
  await writeFile(join(dir, manifest.entry), source, "utf8");
  return dir;
}

/**
 * Makes the staged copy the live one, by directory swap.
 *
 * A swap rather than two `writeFile`s, which is what the metric path does and
 * is not atomic: a crash between the manifest and the entry leaves a manifest
 * describing code that is not there. With a connector that window is wider —
 * more metrics, more to write — and under the digest model the result does
 * not read as corruption but as "modified", which is a confusing way to
 * report a half-finished write.
 */
export async function promoteStagedConnector(id: string): Promise<string> {
  const staged = stagingDir(id);
  const live = connectorDir(id);
  const previous = `${live}.previous`;

  // Validate before touching the live copy. Promoting something unparseable
  // would replace a working connector with one the app refuses to load.
  LocalConnectorManifest.parse(JSON.parse(await readFile(join(staged, "manifest.json"), "utf8")));

  await mkdir(connectorsRoot(), { recursive: true });
  await rm(previous, { recursive: true, force: true });
  if (existsSync(live)) await rename(live, previous);
  try {
    await rename(staged, live);
  } catch (error) {
    // Put it back. A failed promote must not leave the user with nothing.
    if (existsSync(previous)) await rename(previous, live);
    throw error;
  }
  await rm(previous, { recursive: true, force: true });
  return live;
}

export async function readConnector(
  id: string,
): Promise<{ manifest: LocalConnectorManifest; source: string; dir: string }> {
  const dir = connectorDir(id);
  const manifest = LocalConnectorManifest.parse(
    JSON.parse(await readFile(join(dir, "manifest.json"), "utf8")),
  );
  const source = await readFile(join(dir, manifest.entry), "utf8");
  return { manifest, source, dir };
}

export async function listConnectors(): Promise<{
  ok: { manifest: LocalConnectorManifest; dir: string }[];
  broken: { id: string; dir: string; error: string }[];
}> {
  const root = connectorsRoot();
  if (!existsSync(root)) return { ok: [], broken: [] };

  const ok: { manifest: LocalConnectorManifest; dir: string }[] = [];
  const broken: { id: string; dir: string; error: string }[] = [];

  for (const id of await readdir(root)) {
    // `.staging` and `.previous` are scratch, not connectors.
    if (id.startsWith(".")) continue;
    const dir = join(root, id);
    try {
      const manifest = LocalConnectorManifest.parse(
        JSON.parse(await readFile(join(dir, "manifest.json"), "utf8")),
      );
      ok.push({ manifest, dir });
    } catch (error) {
      // Reported, not skipped. A connector that vanishes from the list is one
      // nobody can fix, because nothing says what is wrong with it.
      broken.push({ id, dir, error: error instanceof Error ? error.message : String(error) });
    }
  }

  return { ok, broken };
}

export async function removeConnector(id: string): Promise<void> {
  await rm(connectorDir(id), { recursive: true, force: true });
}
