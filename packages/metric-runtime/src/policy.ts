/**
 * What a custom metric is allowed to do.
 *
 * Stated plainly, because the honest framing matters: this is a *containment*
 * boundary, not a security boundary. The plugin is code the user's own agent
 * put in the user's own home directory, and it runs with the user's own
 * privileges — exactly the trust level of a shell script they wrote.
 *
 * What the policy buys is containment of mistakes and of secrets: a metric
 * handed a Stripe key should not be able to POST it to a pastebin, and a metric
 * that loops should not pin a core forever. It does not and cannot defend
 * against a user who chooses to run hostile code.
 */
export const MAX_RESPONSE_BYTES = 4 * 1024 * 1024;
export const MAX_REDIRECTS = 3;
/** The parent SIGKILLs at timeoutMs + this; a `while(true)` ignores signals. */
export const KILL_GRACE_MS = 2_000;

const PRIVATE_HOST =
  /^(localhost|.*\.local|0\.0\.0\.0|127\.|10\.|192\.168\.|169\.254\.|172\.(1[6-9]|2\d|3[01])\.|\[?::1\]?|\[?f[cd])/i;

export type PolicyDenial = { allowed: false; reason: string };
export type PolicyVerdict = { allowed: true } | PolicyDenial;

/** Exact hostnames, or a single leading `*.` matching exactly one more label. */
export function checkHost(raw: string, allowedHosts: readonly string[]): PolicyVerdict {
  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    return { allowed: false, reason: `${raw} is not a URL` };
  }

  if (url.protocol !== "https:") {
    return { allowed: false, reason: `only https is allowed, got ${url.protocol}` };
  }

  // Blocked before the allowlist is consulted, so a manifest cannot list
  // `localhost` and reach the user's own services — or 169.254.169.254, which
  // on a cloud host is the instance metadata endpoint.
  if (PRIVATE_HOST.test(url.hostname)) {
    return { allowed: false, reason: `${url.hostname} is a private or loopback address` };
  }

  const host = url.hostname.toLowerCase();
  const ok = allowedHosts.some((pattern) => {
    const p = pattern.toLowerCase();
    if (p.startsWith("*.")) {
      const suffix = p.slice(1);
      // Exactly one label, so `*.example.com` does not admit `a.b.example.com`
      // — otherwise anybody who can create a nested subdomain is inside.
      return host.endsWith(suffix) && host.slice(0, -suffix.length).split(".").length === 1;
    }
    return host === p;
  });

  return ok ? { allowed: true } : { allowed: false, reason: `${host} is not in allowedHosts` };
}
