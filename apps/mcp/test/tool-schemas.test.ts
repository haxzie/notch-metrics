import { describe, expect, it } from "vitest";
import { PluginManifest } from "@notch/schemas";
import { manifestInput } from "../src/tool-schemas.ts";

/**
 * The tool shapes are declared in zod 3 for the MCP SDK while the
 * authoritative schema is zod 4. That duplication is deliberate and small,
 * and this is the test that stops it drifting: anything the tool accepts must
 * still parse as a real manifest once the server fills in the rest.
 */
function fill(input: Record<string, unknown>) {
  const now = new Date().toISOString();
  return { ...input, schemaVersion: 1, entry: "metric.mjs", createdAt: now, updatedAt: now };
}

const minimal = {
  id: "github-stars",
  name: "GitHub stars",
  shortLabel: "Stars",
  description: "Stargazers on a repository.",
  unit: "count",
  allowedHosts: ["api.github.com"],
};

describe("the tool input shape agrees with the real manifest schema", () => {
  it("a minimal manifest round-trips through both", () => {
    const accepted = manifestInput.parse(minimal);
    expect(() => PluginManifest.parse(fill(accepted))).not.toThrow();
  });

  it("a fully specified manifest round-trips through both", () => {
    const full = {
      ...minimal,
      unit: "currency",
      currency: "USD",
      format: { decimals: 2, compact: false, prefix: "", suffix: "" },
      granularities: ["day", "week"],
      supportsSeries: true,
      refreshIntervalSeconds: 900,
      secrets: [{ key: "GITHUB_TOKEN", label: "Token", required: true }],
      timeoutMs: 5000,
      author: "claude-code",
    };
    const accepted = manifestInput.parse(full);
    const parsed = PluginManifest.parse(fill(accepted));
    expect(parsed.secrets[0]?.key).toBe("GITHUB_TOKEN");
    expect(parsed.granularities).toEqual(["day", "week"]);
  });
});

describe("ids become directory names, so the tool rejects them first", () => {
  it("refuses traversal and separators", () => {
    for (const id of ["../evil", "a/b", "a\\b", "/etc/passwd", ".hidden", "Upper"]) {
      expect(manifestInput.safeParse({ ...minimal, id }).success, id).toBe(false);
    }
  });

  it("accepts a slug", () => {
    expect(manifestInput.safeParse({ ...minimal, id: "github-stars" }).success).toBe(true);
  });
});

describe("secrets are names, never values", () => {
  it("requires SCREAMING_SNAKE keys", () => {
    const bad = { ...minimal, secrets: [{ key: "github token", label: "Token" }] };
    expect(manifestInput.safeParse(bad).success).toBe(false);
  });

  it("has nowhere to put a value", () => {
    const declaration = manifestInput.parse({
      ...minimal,
      secrets: [{ key: "GITHUB_TOKEN", label: "Token" }],
    }).secrets?.[0];
    // The whole design rests on this: a manifest that could carry a value
    // would be a secret sitting in a plain-text file inside a directory any
    // agent can read.
    expect(declaration).not.toHaveProperty("value");
    expect(Object.keys(declaration ?? {})).not.toContain("value");
  });
});

describe("allowedHosts", () => {
  it("is required and non-empty", () => {
    expect(manifestInput.safeParse({ ...minimal, allowedHosts: [] }).success).toBe(false);
    const { allowedHosts: _omitted, ...without } = minimal;
    expect(manifestInput.safeParse(without).success).toBe(false);
  });

  it("rejects a bare wildcard once the real schema sees it", () => {
    // A metric that may call anywhere can post every other secret it was
    // handed to a pastebin.
    const accepted = manifestInput.parse({ ...minimal, allowedHosts: ["*"] });
    expect(() => PluginManifest.parse(fill(accepted))).toThrow();
  });
});
