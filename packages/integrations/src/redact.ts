/**
 * Scrubs anything that looks like a credential out of a string.
 *
 * It lives in this package rather than in `apps/api` because this is where
 * untrusted text first enters the system: `errorForResponse` quotes a
 * provider's own explanation into an error a *user* reads, and a provider is
 * free to echo the key we just sent it back at us. Stripe does, partially.
 *
 * `apps/api` imports this same function for its log sink instead of keeping a
 * second list. Two lists is how one of them ends up not knowing about the
 * prefix a provider added last month.
 */
/**
 * The minimums here are deliberately short — three characters after a known
 * prefix, not twelve.
 *
 * A provider that echoes a key usually echoes a *truncated* key:
 * "Incorrect API key provided: sk-abc". A pattern tuned to the length of a
 * real key sails straight past that and prints the fragment, which is still
 * the first characters of somebody's live credential. Nothing legitimate in
 * an error message begins `sk-` or `shpat_`, so a loose minimum costs us
 * nothing and a tight one costs a leak.
 */
const PATTERNS: RegExp[] = [
  /\b(sk|rk|pk)_(live|test)_[A-Za-z0-9]{3,}/g,
  /\bwhsec_[A-Za-z0-9+/=]{3,}/g,
  /\b(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{3,}/g,
  /\bAKIA[0-9A-Z]{8,}/g,
  /\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}/g,
  /\bBearer\s+[A-Za-z0-9._-]{12,}/gi,
  // Provider-specific prefixes, added because a message naming the key is
  // exactly the kind a provider thinks is helpful to return.
  /\bphc_[A-Za-z0-9]{3,}/g,
  /\bphx_[A-Za-z0-9]{3,}/g,
  /\bshpat_[A-Za-z0-9]{3,}/g,
  /\bsk-(proj-|ant-)?[A-Za-z0-9_-]{3,}/g,
  /\bpolar_[A-Za-z0-9_-]{3,}/g,
  // Trailing-asterisk truncation, which is how most providers show a key
  // back: `sk_live_abc***`. The prefix patterns above already catch the
  // alphanumerics, and this clears the stars they leave behind.
  /\[redacted\]\*+/g,
];

export function redactCredentials(value: string): string {
  return PATTERNS.reduce((acc, pattern) => acc.replace(pattern, "[redacted]"), value);
}
