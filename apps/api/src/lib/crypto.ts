import type { Env } from "../env.ts";

/**
 * Envelope encryption for user-supplied provider credentials.
 *
 * A random 256-bit DEK per integration encrypts the credentials with AES-GCM;
 * the DEK is then wrapped with AES-KW by a KEK held as a Worker secret. The
 * shape is chosen so that rotation re-wraps `wrappedDek` — a few hundred bytes
 * — and never has to decrypt and re-encrypt the payload itself.
 *
 * AES-KW rather than a second AES-GCM pass for the wrap: key wrapping is what
 * AES-KW is for, and it needs no IV, which removes a second nonce to get wrong.
 */

export interface SealedCredentials {
  ciphertext: string;
  iv: string;
  wrappedDek: string;
  keyVersion: number;
  hint: string;
  fingerprint: string;
}

export interface CredentialScope {
  userId: string;
  integrationId: string;
  provider: string;
}

const encoder = new TextEncoder();
const decoder = new TextDecoder();

function b64encode(bytes: ArrayBuffer | Uint8Array): string {
  const view = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  let binary = "";
  for (const byte of view) binary += String.fromCharCode(byte);
  return btoa(binary);
}

function b64decode(value: string): Uint8Array {
  const binary = atob(value);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function kekSecret(env: Env, version: number): string {
  const value = env[`INTEGRATION_KEK_V${version}` as keyof Env];
  if (typeof value !== "string" || value === "") {
    // Never silently fall back to another version. A row names the KEK that
    // wrapped it; if that KEK is gone the row is unreadable, and pretending
    // otherwise produces a decryption failure that reads as data corruption.
    throw new Error(`INTEGRATION_KEK_V${version} is not set but a row still names it`);
  }
  return value;
}

export function activeKeyVersion(env: Env): number {
  const version = Number(env.INTEGRATION_KEK_ACTIVE);
  if (!Number.isInteger(version) || version < 1) {
    throw new Error("INTEGRATION_KEK_ACTIVE must be a positive integer");
  }
  return version;
}

async function importKek(env: Env, version: number): Promise<CryptoKey> {
  const raw = b64decode(kekSecret(env, version));
  if (raw.byteLength !== 32) {
    throw new Error(`INTEGRATION_KEK_V${version} must be 32 bytes, base64-encoded`);
  }
  return crypto.subtle.importKey("raw", raw, "AES-KW", false, ["wrapKey", "unwrapKey"]);
}

/**
 * Additional authenticated data, and the most important line in this file.
 *
 * Without it, a ciphertext row copied from one user to another decrypts
 * perfectly — the bytes carry no claim about whose they are. With it, the copy
 * fails outright, so a bug that mixes up a `userId` in a WHERE clause surfaces
 * as a decryption error rather than as one customer reading another's Stripe
 * key.
 */
function aad(scope: CredentialScope, keyVersion: number): Uint8Array {
  return encoder.encode(`${scope.userId}|${scope.integrationId}|${scope.provider}|v${keyVersion}`);
}

/** Stable across key ordering, so the same credentials always fingerprint alike. */
function canonical(credentials: Record<string, string>): string {
  const sorted = Object.keys(credentials).sort();
  return JSON.stringify(sorted.map((k) => [k, credentials[k]]));
}

export async function fingerprint(credentials: Record<string, string>): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", encoder.encode(canonical(credentials)));
  return b64encode(digest);
}

/** First eight and last four. Enough to tell two keys apart, not enough to be one. */
export function credentialHint(credentials: Record<string, string>): string {
  const longest = Object.values(credentials).sort((a, b) => b.length - a.length)[0] ?? "";
  if (longest.length <= 14) return "…";
  return `${longest.slice(0, 8)}…${longest.slice(-4)}`;
}

export async function sealCredentials(
  env: Env,
  scope: CredentialScope,
  credentials: Record<string, string>,
): Promise<SealedCredentials> {
  const keyVersion = activeKeyVersion(env);
  const kek = await importKek(env, keyVersion);

  // `generateKey` is typed as `CryptoKey | CryptoKeyPair`; AES-GCM is
  // symmetric, so the pair arm is unreachable.
  const dek = (await crypto.subtle.generateKey({ name: "AES-GCM", length: 256 }, true, [
    "encrypt",
    "decrypt",
  ])) as CryptoKey;

  // A fresh 12-byte nonce every time, from the CSPRNG. GCM nonce reuse under
  // one key is a catastrophic *silent* break — it leaks the authentication key,
  // not just the one message — so this must never be derived from the row id.
  const iv = crypto.getRandomValues(new Uint8Array(12));

  const ciphertext = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv, additionalData: aad(scope, keyVersion) },
    dek,
    encoder.encode(JSON.stringify(credentials)),
  );

  const wrappedDek = await crypto.subtle.wrapKey("raw", dek, kek, "AES-KW");

  return {
    ciphertext: b64encode(ciphertext),
    iv: b64encode(iv),
    wrappedDek: b64encode(wrappedDek),
    keyVersion,
    hint: credentialHint(credentials),
    fingerprint: await fingerprint(credentials),
  };
}

export async function openCredentials(
  env: Env,
  scope: CredentialScope,
  sealed: Pick<SealedCredentials, "ciphertext" | "iv" | "wrappedDek" | "keyVersion">,
): Promise<Record<string, string>> {
  const kek = await importKek(env, sealed.keyVersion);

  const dek = await crypto.subtle.unwrapKey(
    "raw",
    b64decode(sealed.wrappedDek),
    kek,
    "AES-KW",
    { name: "AES-GCM" },
    false,
    ["decrypt"],
  );

  const plaintext = await crypto.subtle.decrypt(
    {
      name: "AES-GCM",
      iv: b64decode(sealed.iv),
      additionalData: aad(scope, sealed.keyVersion),
    },
    dek,
    b64decode(sealed.ciphertext),
  );

  return JSON.parse(decoder.decode(plaintext)) as Record<string, string>;
}

/**
 * Re-wraps a row's DEK under the active KEK. Used by `scripts/rotate-kek.ts`.
 *
 * Note that the AAD includes the key version, so rotation genuinely has to
 * decrypt and re-encrypt the payload rather than only re-wrapping. That is a
 * deliberate trade: binding the version into the AAD means a row cannot be
 * replayed under a retired key, and rotation is a rare, offline, resumable job.
 */
export async function rewrap(
  env: Env,
  scope: CredentialScope,
  sealed: Pick<SealedCredentials, "ciphertext" | "iv" | "wrappedDek" | "keyVersion">,
): Promise<SealedCredentials> {
  const credentials = await openCredentials(env, scope, sealed);
  return sealCredentials(env, scope, credentials);
}

/** Adapts a drizzle `integration` row to the sealed-credential shape. */
export function sealedFromRow(row: {
  credentialCiphertext: string;
  credentialIv: string;
  credentialWrappedDek: string;
  keyVersion: number;
}): Pick<SealedCredentials, "ciphertext" | "iv" | "wrappedDek" | "keyVersion"> {
  return {
    ciphertext: row.credentialCiphertext,
    iv: row.credentialIv,
    wrappedDek: row.credentialWrappedDek,
    keyVersion: row.keyVersion,
  };
}
