import { EXPIRES_AT_FIELD, OAuthReauthRequiredError, type OAuthConfig } from "../../oauth.ts";
import { ProviderError } from "../../types.ts";
import type { GitHubCredentials } from "./define.ts";

interface TokenResponse {
  access_token?: string;
  refresh_token?: string;
  /** Seconds. Present only when the app issues expiring tokens. */
  expires_in?: number;
  error?: string;
  error_description?: string;
}

function hasToken(body: TokenResponse): body is TokenResponse & { access_token: string } {
  return typeof body.access_token === "string" && body.access_token.length > 0;
}

/**
 * The token fields of a credential blob, from either the code exchange or a
 * refresh — the two responses have the same shape.
 */
function tokens(body: TokenResponse & { access_token: string }): {
  access_token: string;
  refresh_token?: string;
  expires_at?: string;
} {
  return {
    access_token: body.access_token,
    ...(body.refresh_token ? { refresh_token: body.refresh_token } : {}),
    ...(typeof body.expires_in === "number" && body.expires_in > 0
      ? { [EXPIRES_AT_FIELD]: String(Date.now() + body.expires_in * 1000) }
      : {}),
  };
}

/**
 * GitHub's OAuth leg.
 *
 * `exchangeCode` and the repository list call `fetch` directly rather than
 * `ctx.http`: both happen before any adapter context exists, and the hosts
 * they reach are fixed strings in this file rather than anything a provider
 * response can steer. The allowlist exists to stop a *redirect* carrying the
 * user's token somewhere else, which is why `redirect: "manual"` is still set
 * on both.
 */
export const oauth: OAuthConfig<GitHubCredentials> = {
  // `repo`, and it grants more than this connector uses.
  //
  // An OAuth App has no read-only scope for private repositories. GitHub's
  // repo-related scopes are `repo`, `repo:status`, `repo_deployment`,
  // `public_repo`, `repo:invite` and `security_events`; none of them is
  // "read private repositories". `repo` is the only one that reaches a
  // private repo at all, and it carries read *and write* on code for every
  // repository the user can see, plus org projects, invitations and
  // webhooks.
  //
  // So this is a deliberate trade, not an oversight: private repositories
  // were worth more than the narrower token. What it costs is real and
  // should not be quietly forgotten — the consent screen says "Full control
  // of private repositories", and a compromise of this server would mean
  // push access to every connected account rather than a leaked star count.
  // Nothing here ever issues a write; the AAD-bound envelope in
  // `lib/crypto.ts` is what keeps one user's token from decrypting for
  // another.
  //
  // A GitHub App is the way to take this back: per-repository installation
  // with `Actions: Read-only` and `Metadata: Read-only`, narrower than even
  // `public_repo` is today. It is a different credential shape — installation
  // tokens minted from a signed JWT, no refresh token — so it is its own
  // piece of work rather than a scope swap.
  scopes: ["repo", "read:user"],
  // Honest about the grant rather than about our intent. GitHub will show
  // "Full control of private repositories" on the next screen, and a summary
  // that said "read" would read as a contradiction of it.
  scopeSummary: [
    "Read your repositories, public and private",
    "GitHub grants this as full repository access. Notch Metrics only reads.",
    "Read your name and avatar",
  ],

  authorizationUrl({ clientId, redirectUri, state }) {
    const url = new URL("https://github.com/login/oauth/authorize");
    url.searchParams.set("client_id", clientId);
    url.searchParams.set("redirect_uri", redirectUri);
    url.searchParams.set("scope", this.scopes.join(" "));
    url.searchParams.set("state", state);
    return url.toString();
  },

  async exchangeCode({ code, redirectUri, clientId, clientSecret }) {
    const response = await fetch("https://github.com/login/oauth/access_token", {
      method: "POST",
      redirect: "manual",
      headers: { "content-type": "application/json", accept: "application/json" },
      body: JSON.stringify({
        client_id: clientId,
        client_secret: clientSecret,
        code,
        redirect_uri: redirectUri,
      }),
    });

    // GitHub answers 200 with `{ error }` for a bad or reused code rather
    // than a 4xx, so the status alone proves nothing.
    const body = (await response.json()) as TokenResponse;
    if (!response.ok || !hasToken(body)) {
      throw new ProviderError(
        "auth_failed",
        body.error_description ?? "GitHub would not complete the sign-in.",
      );
    }

    // Nothing else to fill in: the grant is the whole connection, and which
    // repository a number comes from is settled per widget.
    return tokens(body);
  },

  // Eight hours is the token's whole life when expiry is on. An hour of lead
  // is generous on purpose: the cron is five-minutely and a Worker tick can
  // be skipped, and a refresh an hour early costs nothing — the old token
  // keeps working until the new one is issued. The floor keeps a bug from
  // looping on the token endpoint.
  refresh: { leadTimeMs: 60 * 60 * 1000, minIntervalMs: 5 * 60 * 1000 },

  /**
   * Trades the refresh token for a new pair.
   *
   * A connection made before expiry was switched on has no refresh token and
   * a token that never expires; null says there is nothing to do. Once a
   * refresh token has been used it is dead, which is why the new one is
   * stored in the same write as the new access token.
   */
  async refreshCredentials({ credentials, clientId, clientSecret }) {
    if (!credentials.refresh_token) return null;

    const response = await fetch("https://github.com/login/oauth/access_token", {
      method: "POST",
      redirect: "manual",
      headers: { "content-type": "application/json", accept: "application/json" },
      body: JSON.stringify({
        client_id: clientId,
        client_secret: clientSecret,
        grant_type: "refresh_token",
        refresh_token: credentials.refresh_token,
      }),
    });
    const body = (await response.json().catch(() => ({}))) as TokenResponse;

    // `bad_refresh_token` is GitHub's one unambiguous "start over": the
    // refresh token expired through six months of disuse, was already used,
    // or the user revoked the app. Anything else — a 5xx, a mangled body —
    // is a reason to try again on the next tick, not to make somebody
    // reconnect.
    if (body.error === "bad_refresh_token" || body.error === "invalid_grant") {
      throw new OAuthReauthRequiredError(
        "GitHub has stopped honouring this connection. Reconnect it to carry on.",
      );
    }
    if (!response.ok || !hasToken(body)) {
      throw new Error(`GitHub token refresh failed: ${body.error ?? response.status}`);
    }
    return { ...credentials, ...tokens(body) };
  },
};
