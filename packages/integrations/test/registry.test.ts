import { existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { ProviderManifest } from "@notch/schemas";
import { REGISTRY, manifests } from "../src/registry.ts";
import { hostAllowed } from "../src/http.ts";

describe("registry", () => {
  it("every manifest parses", () => {
    for (const manifest of manifests()) {
      expect(() => ProviderManifest.parse(manifest), manifest.id).not.toThrow();
    }
  });

  it("every adapter's id matches its registry key", () => {
    for (const [key, adapter] of Object.entries(REGISTRY)) {
      expect(adapter.manifest.id).toBe(key);
    }
  });

  it("every iconPath points at the path the website actually serves", () => {
    // These lived at `/providers/<id>.svg` for eighteen connectors and the
    // website has only ever served `/connectors/`. Nothing read the field,
    // so nothing noticed.
    for (const manifest of manifests()) {
      expect(manifest.iconPath, manifest.id).toBe(`/connectors/${manifest.id}.svg`);
    }
  });

  /**
   * Connectors whose `iconPath` has no file behind it.
   *
   * Amplitude is in neither simple-icons nor `overrides/`, so the sync script
   * writes nothing for it and says nothing — it has been serving a 404 since
   * it shipped. Listed rather than silently tolerated, and the test below
   * fails if an entry here turns out to have a mark after all, so fixing one
   * cannot leave a stale exemption behind.
   */
  const MARK_MISSING = new Set(["amplitude"]);

  const webMarks = join(
    dirname(fileURLToPath(import.meta.url)),
    "../../../apps/web/public/connectors",
  );

  it("every iconPath points at a file that exists", () => {
    // The shape check above passes happily for a connector whose mark was
    // never generated, which is how a 404 ships unnoticed: nothing in the
    // app reads the field until a user opens the integrations page.
    for (const manifest of manifests()) {
      if (MARK_MISSING.has(manifest.id)) continue;
      expect(
        existsSync(join(webMarks, `${manifest.id}.svg`)),
        `${manifest.id}: no mark at apps/web/public/connectors/${manifest.id}.svg — ` +
          `add packages/ui/assets/connectors/overrides/${manifest.id}.svg ` +
          `or a BRANDS entry, then run scripts/sync-connector-icons.mjs`,
      ).toBe(true);
    }
  });

  it("the missing-mark list has nothing stale in it", () => {
    for (const id of MARK_MISSING) {
      expect(
        existsSync(join(webMarks, `${id}.svg`)),
        `${id} has a mark now — drop it from MARK_MISSING`,
      ).toBe(false);
    }
  });

  it("no manifest allows a bare wildcard host", () => {
    for (const manifest of manifests()) {
      expect(manifest.allowedHosts, manifest.id).not.toContain("*");
    }
  });
});

describe("hostAllowed", () => {
  it("matches an exact host", () => {
    expect(hostAllowed("api.stripe.com", ["api.stripe.com"])).toBe(true);
    expect(hostAllowed("evil.com", ["api.stripe.com"])).toBe(false);
  });

  it("matches exactly one label under a wildcard", () => {
    expect(hostAllowed("eu.example.com", ["*.example.com"])).toBe(true);
    // Otherwise `*.example.com` would admit `a.b.example.com`, and anyone who
    // can create a subdomain two levels deep gets inside the allowlist.
    expect(hostAllowed("a.b.example.com", ["*.example.com"])).toBe(false);
  });

  it("does not let a suffix masquerade as the host", () => {
    expect(hostAllowed("notapi.stripe.com.evil.io", ["api.stripe.com"])).toBe(false);
  });
});
