import type { ProviderId } from "@notch/schemas";

/**
 * When a connector's tokens should be refreshed.
 *
 * Two numbers rather than one, and both matter. `leadTimeMs` refreshes before
 * expiry so a request never races the clock. `minIntervalMs` is a hard floor
 * between refreshes for one connection — most providers rate-limit their
 * token endpoint far more aggressively than their data endpoints, and a bug
 * that refreshes in a loop gets the whole app's client id throttled rather
 * than one user.
 */
export interface OAuthRefreshPolicy {
  leadTimeMs: number;
  minIntervalMs: number;
}

export const DEFAULT_REFRESH_POLICY: OAuthRefreshPolicy = {
  leadTimeMs: 5 * 60 * 1000,
  minIntervalMs: 60 * 1000,
};

/**
 * The credential field a connector that declares a `refresh` policy must
 * write: when its access token stops working, as Unix milliseconds.
 *
 * A decimal string rather than a number, because a credential blob is
 * string-valued end to end — it is fingerprinted and hinted as strings, and a
 * number that survived one JSON round trip and not another is the kind of
 * drift that shows up as "expires in 1970".
 */
export const EXPIRES_AT_FIELD = "expires_at";

/** Reads the expiry out of a blob, tolerating either representation. */
export function credentialExpiry(credentials: Record<string, unknown>): number | null {
  const raw = credentials[EXPIRES_AT_FIELD];
  const value = typeof raw === "string" ? Number(raw) : raw;
  return typeof value === "number" && Number.isFinite(value) && value > 0 ? value : null;
}

/**
 * Whether a refresh is due right now, by the connector's policy.
 *
 * The one place staleness is decided: the cron sweep and the fetch path both
 * ask this, so they cannot disagree. Connectors never check expiry
 * themselves — `refreshCredentials` is only called once this says yes.
 */
export function isRefreshDue(
  policy: OAuthRefreshPolicy,
  state: { expiresAt: number | null; lastAttemptAt: number | null },
  now = Date.now(),
): boolean {
  // The floor wins unconditionally. Even a token that already looks expired
  // must not re-hit the provider's token endpoint faster than the connector
  // says is safe — that is how a whole client id gets throttled, not one user.
  if (state.lastAttemptAt !== null && now - state.lastAttemptAt < policy.minIntervalMs) {
    return false;
  }
  // Unknown expiry: a row from before expiry was recorded. Try once; a
  // successful refresh writes the expiry and the question answers itself.
  if (state.expiresAt === null) return true;
  return state.expiresAt - now <= policy.leadTimeMs;
}

/**
 * The grant is dead and no amount of retrying will fix it — the user revoked
 * access, or changed their password, or the app was uninstalled on the
 * provider's side.
 *
 * Distinct from a transient failure because the response is different: the
 * integration is marked `auth_failed`, polling stops, and the user is asked
 * to reconnect. Retrying a dead grant forever is how an app gets its client
 * id rate-limited.
 */
export class OAuthReauthRequiredError extends Error {
  constructor(message = "This connection needs to be authorised again.") {
    super(message);
    this.name = "OAuthReauthRequiredError";
  }
}

/** Something the user picks after authorising — a GA4 property, a site, an ad account. */
export interface OAuthSelectionOption {
  value: string;
  label: string;
  hint?: string;
}

export interface OAuthSelection<C> {
  /** Heading for the picker. */
  label: string;
  /** Which credential field the chosen value is written to. */
  field: string;
  /** Fetched with the fresh tokens, before anything is persisted. */
  options(credentials: C): Promise<OAuthSelectionOption[]>;
}

export interface OAuthConfig<C> {
  /**
   * Which Worker secrets hold this connector's client, when it is not the
   * pair `oauthSecretNames` derives from the provider id.
   *
   * Every Google connector reads the one Google client the server already
   * has for sign-in: Google issues a client per project, not per API, and
   * three copies of the same secret under three names is three places to
   * rotate. Scopes are requested per flow, so sharing the client does not
   * mean signing in grants analytics access.
   */
  readonly clientSecretNames?: { clientId: string; clientSecret: string };
  /** Shown on the connect page so the user knows what they are granting. */
  readonly scopes: readonly string[];
  /** Human-readable version of the above, for people rather than APIs. */
  readonly scopeSummary: readonly string[];

  authorizationUrl(params: { clientId: string; redirectUri: string; state: string }): string;

  exchangeCode(params: {
    code: string;
    redirectUri: string;
    clientId: string;
    clientSecret: string;
  }): Promise<C>;

  readonly refresh?: OAuthRefreshPolicy;

  /**
   * Exchange the refresh token for a fresh access token.
   *
   * Callers gate this against the policy first, so do not check expiry here —
   * assume the refresh is due. Return null when the provider has nothing to
   * refresh (non-expiring tokens). Throw `OAuthReauthRequiredError` when only
   * a human can fix it.
   */
  refreshCredentials(params: {
    credentials: C;
    clientId: string;
    clientSecret: string;
  }): Promise<C | null>;

  /**
   * A choice the user makes after authorising but before the connection is
   * saved. GA4 needs a property, Search Console a site, Ads a customer —
   * without it the tokens are valid and there is still nothing to query.
   */
  readonly selection?: OAuthSelection<C>;
}

/** Which Worker secrets hold a connector's OAuth client credentials. */
export function oauthSecretNames(id: ProviderId): { clientId: string; clientSecret: string } {
  const key = id.toUpperCase().replace(/-/g, "_");
  return { clientId: `OAUTH_${key}_CLIENT_ID`, clientSecret: `OAUTH_${key}_CLIENT_SECRET` };
}
