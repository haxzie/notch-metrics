import { mkdtempSync, readFileSync, writeFileSync, mkdirSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { beforeEach, describe, expect, it } from "vitest";
import { LocalConnectorManifest } from "@notch/schemas";
import {
  assertSafeConnectorId,
  connectorDir,
  listConnectors,
  promoteStagedConnector,
  readConnector,
  writeConnector,
} from "../src/connector-store.ts";

const manifest = LocalConnectorManifest.parse({
  schemaVersion: 1,
  id: "linear",
  name: "Linear",
  description: "d",
  auth: [{ key: "api_key", label: "API key", type: "secret" }],
  allowedHosts: ["api.linear.app"],
  metrics: [
    {
      id: "open_issues",
      label: "Open issues",
      shortLabel: "Issues",
      unit: "count",
      shape: { kind: "scalar" },
      methodology: "m",
    },
  ],
  entry: "connector.mjs",
  createdAt: "2026-10-24T12:00:00.000Z",
  updatedAt: "2026-10-24T12:00:00.000Z",
});

const source = "export async function verify() { return {} }";

beforeEach(() => {
  process.env.NOTCH_CONNECTORS_ROOT = mkdtempSync(join(tmpdir(), "connectors-"));
});

describe("connector ids", () => {
  it("refuses anything that would escape the directory", () => {
    // The id comes from an agent and becomes a path. These are the ones that
    // matter, not hypotheticals.
    for (const id of [
      "../evil",
      "../../.ssh",
      "a/b",
      "a\\b",
      "/etc/passwd",
      ".hidden",
      "A-Upper",
    ]) {
      expect(() => assertSafeConnectorId(id), id).toThrow();
    }
  });

  it("accepts an ordinary one", () => {
    expect(() => assertSafeConnectorId("linear")).not.toThrow();
    expect(connectorDir("linear").endsWith("/linear")).toBe(true);
  });
});

describe("registering", () => {
  it("stages without touching the live copy", async () => {
    await writeConnector(manifest, source, { staging: true });
    // The whole point of staging: a bad candidate cannot blank working tiles.
    expect(existsSync(connectorDir("linear"))).toBe(false);
  });

  it("promotes staged into live", async () => {
    await writeConnector(manifest, source, { staging: true });
    await promoteStagedConnector("linear");

    const read = await readConnector("linear");
    expect(read.manifest.name).toBe("Linear");
    expect(read.source).toBe(source);
  });

  it("replaces a previous registration wholesale", async () => {
    await writeConnector(manifest, source, { staging: true });
    await promoteStagedConnector("linear");

    const updated = { ...manifest, name: "Linear (v2)" };
    await writeConnector(updated, "export async function verify() { return { ok: 1 } }", {
      staging: true,
    });
    await promoteStagedConnector("linear");

    const read = await readConnector("linear");
    expect(read.manifest.name).toBe("Linear (v2)");
    expect(read.source).toContain("ok: 1");
  });

  it("leaves no scratch directories behind", async () => {
    await writeConnector(manifest, source, { staging: true });
    await promoteStagedConnector("linear");
    const root = process.env.NOTCH_CONNECTORS_ROOT!;
    // `.previous` is the rollback copy and must not survive a success — it is
    // a whole second copy of every connector if it does.
    expect(existsSync(join(root, "linear.previous"))).toBe(false);
    expect(existsSync(join(root, ".staging", "linear"))).toBe(false);
  });

  it("refuses to promote something unparseable, keeping the live copy", async () => {
    await writeConnector(manifest, source, { staging: true });
    await promoteStagedConnector("linear");

    // Corrupt the staged manifest, as a half-finished write would.
    const staged = join(process.env.NOTCH_CONNECTORS_ROOT!, ".staging", "linear");
    mkdirSync(staged, { recursive: true });
    writeFileSync(join(staged, "manifest.json"), "{ not json", "utf8");
    writeFileSync(join(staged, "connector.mjs"), "", "utf8");

    await expect(promoteStagedConnector("linear")).rejects.toThrow();

    // Still the good one. Validating before the swap is what makes this true.
    const read = await readConnector("linear");
    expect(read.manifest.name).toBe("Linear");
  });
});

describe("listing", () => {
  it("is empty before anything is registered", async () => {
    expect((await listConnectors()).ok).toHaveLength(0);
  });

  it("reports a broken connector rather than hiding it", async () => {
    const root = process.env.NOTCH_CONNECTORS_ROOT!;
    mkdirSync(join(root, "broken"), { recursive: true });
    writeFileSync(join(root, "broken", "manifest.json"), '{"schemaVersion":1}', "utf8");

    const { ok, broken } = await listConnectors();
    expect(ok).toHaveLength(0);
    // A connector that silently vanishes is one nobody can fix.
    expect(broken[0]?.id).toBe("broken");
    expect(broken[0]?.error).toBeTruthy();
  });

  it("skips the scratch directories", async () => {
    await writeConnector(manifest, source, { staging: true });
    const { ok, broken } = await listConnectors();
    expect(ok).toHaveLength(0);
    expect(broken).toHaveLength(0);
  });
});

describe("the written manifest", () => {
  it("round-trips through the schema", async () => {
    await writeConnector(manifest, source, { staging: true });
    await promoteStagedConnector("linear");
    const raw = readFileSync(join(connectorDir("linear"), "manifest.json"), "utf8");
    expect(() => LocalConnectorManifest.parse(JSON.parse(raw))).not.toThrow();
  });
});
