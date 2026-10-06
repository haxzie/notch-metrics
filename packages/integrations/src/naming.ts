import type { ProviderManifest } from "@notch/schemas";

/**
 * The name a connection gets when nobody typed one.
 *
 * Every connection has a name, always. A list of five rows all saying
 * "Stripe" is unusable the moment somebody connects a second account, and
 * asking for a name up front is a field people skip.
 *
 * The shape is `Provider — detail`, where the detail is whatever `verify()`
 * learned about the account: a business name, a store, an environment. The
 * em dash is deliberate — a hyphen reads as part of the account name when the
 * account name itself contains one.
 */
export function connectionName(options: {
  manifest: ProviderManifest;
  /** From `VerifyResult.accountLabel`. The distinguishing part only. */
  accountLabel?: string | null;
  /** Names already taken by this user's other connections. */
  taken?: Iterable<string>;
}): string {
  const base = baseName(options.manifest, options.accountLabel);
  return disambiguate(base, new Set(options.taken ?? []));
}

function baseName(manifest: ProviderManifest, accountLabel?: string | null): string {
  const detail = accountLabel?.trim();
  if (!detail) return manifest.name;

  // A provider whose `verify()` already returns its own name — or an account
  // literally named after it — must not become "Stripe — Stripe".
  if (detail.toLowerCase() === manifest.name.toLowerCase()) return manifest.name;

  // Nor "Stripe — Stripe (test)", which is what happens when an adapter
  // helpfully prefixes the detail itself.
  if (detail.toLowerCase().startsWith(`${manifest.name.toLowerCase()} `)) return detail;

  return `${manifest.name} — ${detail}`;
}

/**
 * Two Stripe accounts with no business name set would otherwise both be
 * "Stripe", and the list could not tell them apart.
 */
function disambiguate(base: string, taken: Set<string>): string {
  if (!taken.has(base)) return base;
  for (let n = 2; n < 100; n++) {
    const candidate = `${base} (${n})`;
    if (!taken.has(candidate)) return candidate;
  }
  return base;
}
