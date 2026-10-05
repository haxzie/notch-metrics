import { describe, expect, it } from "vitest";
import { assertSafeId, metricDir } from "../src/store.ts";
import { checkHost } from "../src/policy.ts";
import { lintSource } from "../src/lint.ts";

describe("metric ids become directory names, so they are checked first", () => {
  it("accepts a slug", () => {
    expect(() => assertSafeId("github-stars")).not.toThrow();
  });

  it("rejects traversal, separators and absolute paths before any fs call", () => {
    // An agent supplies this id through an MCP tool call. Without the guard,
    // `../../.ssh` is a write anywhere in the user's home directory.
    for (const bad of [
      "../evil",
      "../../.ssh",
      "a/b",
      "a\\b",
      "/etc/passwd",
      ".hidden",
      "A-Upper",
      "",
    ]) {
      expect(() => assertSafeId(bad), bad).toThrow();
      expect(() => metricDir(bad), bad).toThrow();
    }
  });
});

describe("host policy", () => {
  it("allows an exact allowlisted host over https", () => {
    expect(checkHost("https://api.github.com/x", ["api.github.com"]).allowed).toBe(true);
  });

  it("refuses plain http even when the host is allowed", () => {
    expect(checkHost("http://api.github.com/x", ["api.github.com"]).allowed).toBe(false);
  });

  it("refuses loopback and link-local even when the manifest lists them", () => {
    // Checked before the allowlist, so a manifest cannot reach the user's own
    // services, or 169.254.169.254, which on a cloud host is instance metadata.
    for (const host of [
      "https://localhost/x",
      "https://127.0.0.1/x",
      "https://169.254.169.254/x",
      "https://printer.local/x",
    ]) {
      expect(
        checkHost(host, ["localhost", "127.0.0.1", "169.254.169.254", "printer.local"]).allowed,
        host,
      ).toBe(false);
    }
  });

  it("limits a wildcard to one label", () => {
    expect(checkHost("https://eu.example.com/x", ["*.example.com"]).allowed).toBe(true);
    expect(checkHost("https://a.b.example.com/x", ["*.example.com"]).allowed).toBe(false);
  });
});

describe("source lint", () => {
  const body = "export async function fetchMetric(ctx) { return { value: 1 }; }";

  it("passes a clean metric", () => {
    expect(lintSource(body).filter((f) => f.severity === "error")).toHaveLength(0);
  });

  it("refuses a pasted API key", () => {
    // The thing an agent will try first, and the reason this lint exists.
    const withKey = `const key = "sk_live_51H8xQwERTYuiopASDFghjklZXCVbnm123456";\n${body}`;
    const errors = lintSource(withKey).filter((f) => f.severity === "error");
    expect(errors.length).toBeGreaterThan(0);
    // Every finding has to carry the remediation, not just the complaint —
    // an agent that is told "no" without being told "do this instead" will
    // try the same thing again.
    for (const error of errors) expect(error.message).toMatch(/set_metric_secret/);
  });

  it("refuses a missing fetchMetric export", () => {
    expect(lintSource("export const x = 1;").some((f) => f.severity === "error")).toBe(true);
  });

  it("warns about process.env and bare fetch", () => {
    const warnings = lintSource(`${body}\nconst a = process.env.KEY; fetch("x");`).filter(
      (f) => f.severity === "warning",
    );
    expect(warnings).toHaveLength(2);
  });
});
