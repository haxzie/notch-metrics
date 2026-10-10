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
