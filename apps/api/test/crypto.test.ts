import { env } from "cloudflare:test";
import { beforeAll, describe, expect, it } from "vitest";
import {
  activeKeyVersion,
  credentialHint,
  fingerprint,
  openCredentials,
  rewrap,
  sealCredentials,
} from "../src/lib/crypto.ts";
import { migrate } from "./helpers.ts";

const scope = { userId: "usr_alice", integrationId: "int_1", provider: "stripe" };
const creds = { secret_key: "rk_live_abcdefghijklmnop4f2a" };

beforeAll(migrate);

describe("envelope encryption", () => {
  it("round-trips", async () => {
    const sealed = await sealCredentials(env, scope, creds);
    expect(await openCredentials(env, scope, sealed)).toEqual(creds);
  });

  it("never stores the plaintext anywhere in the sealed record", async () => {
    const sealed = await sealCredentials(env, scope, creds);
    const serialised = JSON.stringify(sealed);
    expect(serialised).not.toContain(creds.secret_key);
    expect(serialised).not.toContain("abcdefghijklmnop");
  });

  it("refuses to decrypt a row moved to another user", async () => {
    // The single most important property in this file. The AAD binds the
    // ciphertext to (user, integration, provider, key version), so a row copied
    // between users — by a bad WHERE clause, say — fails outright instead of
    // decrypting perfectly and handing one customer another's Stripe key.
    const sealed = await sealCredentials(env, scope, creds);
    await expect(
      openCredentials(env, { ...scope, userId: "usr_mallory" }, sealed),
    ).rejects.toThrow();
  });

  it("refuses to decrypt a row moved to another integration or provider", async () => {
    const sealed = await sealCredentials(env, scope, creds);
    await expect(
      openCredentials(env, { ...scope, integrationId: "int_2" }, sealed),
    ).rejects.toThrow();
    await expect(
      openCredentials(env, { ...scope, provider: "lemonsqueezy" }, sealed),
    ).rejects.toThrow();
  });

  it("uses a fresh nonce every time", async () => {
    // GCM nonce reuse under one key leaks the authentication key, not just the
    // one message, and does so silently. Two seals of identical input must
    // differ in both the IV and the ciphertext.
    const a = await sealCredentials(env, scope, creds);
    const b = await sealCredentials(env, scope, creds);
    expect(a.iv).not.toBe(b.iv);
    expect(a.ciphertext).not.toBe(b.ciphertext);
  });

  it("keeps reading v1 rows after the active version moves to v2", async () => {
    // Rotation is not atomic across rows. Code that assumed the active version
    // could decrypt everything would start throwing on every pre-rotation row
    // the moment INTEGRATION_KEK_ACTIVE was bumped.
    const sealed = await sealCredentials(env, scope, creds);
    expect(sealed.keyVersion).toBe(1);

    const rotated = { ...env, INTEGRATION_KEK_ACTIVE: "2" };
    expect(activeKeyVersion(rotated)).toBe(2);
    expect(await openCredentials(rotated, scope, sealed)).toEqual(creds);

    const rewrapped = await rewrap(rotated, scope, sealed);
    expect(rewrapped.keyVersion).toBe(2);
    expect(await openCredentials(rotated, scope, rewrapped)).toEqual(creds);
  });

  it("throws a message naming the version when a KEK a row needs is gone", async () => {
    const sealed = await sealCredentials(env, scope, creds);
    const without = { ...env, INTEGRATION_KEK_V1: undefined };
    await expect(openCredentials(without, scope, sealed)).rejects.toThrow(/INTEGRATION_KEK_V1/);
  });
});

describe("fingerprint and hint", () => {
  it("fingerprints identically regardless of key order", async () => {
    const a = await fingerprint({ a: "1", b: "2" });
    const b = await fingerprint({ b: "2", a: "1" });
    expect(a).toBe(b);
  });

  it("differs for different credentials", async () => {
    expect(await fingerprint({ a: "1" })).not.toBe(await fingerprint({ a: "2" }));
  });

  it("hints with the ends and never the middle", () => {
    const hint = credentialHint(creds);
    expect(hint).toBe("rk_live_…4f2a");
    expect(hint).not.toContain("abcdefghijklmnop");
  });
});
