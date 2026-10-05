/**
 * Scrubs anything that looks like a credential out of a string before it is
 * logged.
 *
 * A thrown provider error often quotes the request that failed, and a Worker's
 * `console.error` goes to a log sink that outlives the request. This is the
 * last line of defence rather than the first: nothing should be putting a key
 * into an error message in the first place.
 */
const PATTERNS: RegExp[] = [
  /\b(sk|rk|pk)_(live|test)_[A-Za-z0-9]{4,}/g,
  /\bwhsec_[A-Za-z0-9+/=]{4,}/g,
  /\b(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{4,}/g,
  /\bAKIA[0-9A-Z]{8,}/g,
  /\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}/g,
  /\bBearer\s+[A-Za-z0-9._-]{12,}/gi,
];

export function redact(value: string): string {
  return PATTERNS.reduce((acc, pattern) => acc.replace(pattern, "[redacted]"), value);
}

export function logError(scope: string, error: unknown): void {
  const message = error instanceof Error ? (error.stack ?? error.message) : String(error);
  console.error(`[${scope}] ${redact(message)}`);
}
