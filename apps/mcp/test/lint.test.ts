import { describe, expect, it } from "vitest";
import { lintSource } from "@notch/metric-runtime";

/**
 * The server refuses a source containing anything key-shaped. This is the
 * highest-leverage check in the custom-metric design, because pasting the key
 * straight into the file is the natural thing for an agent to do with one.
 */
const body = `export async function fetchMetric(ctx) {
  const r = await ctx.http("https://api.github.com/x");
  return { value: (await r.json()).count, unit: "count" };
}`;

const errors = (source: string) =>
  lintSource(source).filter((finding) => finding.severity === "error");

describe("pasted credentials", () => {
  const pasted: [string, string][] = [
    ["a Stripe secret key", 'const k = "sk_live_51H8xQwERTYuiopASDFghjklZXCVbnm";'],
    ["a GitHub token", 'const k = "ghp_abcdefghijklmnopqrstuvwxyz0123456789";'],
    ["an AWS key id", 'const k = "AKIAIOSFODNN7EXAMPLE";'],
    ["a webhook signing key", 'const k = "whsec_dGVzdHNlY3JldGZvcnNpZ25pbmd0ZXN0cw==";'],
    ["a Slack token", 'const k = "xoxb-123456789012-abcdefghijklmnop";'],
  ];

  for (const [what, line] of pasted) {
    it(`refuses ${what}`, () => {
      const found = errors(`${line}\n${body}`);
      expect(found.length).toBeGreaterThan(0);
      // Every finding carries the remedy. An agent told "no" without being
      // told what to do instead tries the same thing again.
      for (const finding of found) expect(finding.message).toMatch(/set_metric_secret/);
    });
  }

  it("accepts a clean source", () => {
    expect(errors(body)).toHaveLength(0);
  });

  it("does not fire on an ordinary long string", () => {
    const prose = `const label = "Monthly recurring revenue across every active plan";\n${body}`;
    expect(errors(prose)).toHaveLength(0);
  });
});

describe("shape", () => {
  it("requires a fetchMetric export", () => {
    expect(errors("export const value = 1;").length).toBeGreaterThan(0);
  });

  it("refuses subprocesses", () => {
    expect(errors(`import { exec } from "node:child_process";\n${body}`).length).toBeGreaterThan(0);
  });

  it("warns rather than fails on process.env", () => {
    const findings = lintSource(`const k = process.env.TOKEN;\n${body}`);
    expect(findings.some((f) => f.severity === "warning")).toBe(true);
    expect(findings.filter((f) => f.severity === "error")).toHaveLength(0);
  });
});
