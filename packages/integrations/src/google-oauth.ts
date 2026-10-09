import { ProviderError } from "./types.ts";
import {
  EXPIRES_AT_FIELD,
  OAuthReauthRequiredError,
  type OAuthConfig,
  type OAuthRefreshPolicy,
  type OAuthSelection,
} from "./oauth.ts";

/**
 * The token fields every Google connector stores. The selection — a GA4
 * property, a Search Console site — is the connector's own field on top.
 */
export interface GoogleTokens extends Record<string, unknown> {
  access_token: string;
  refresh_token?: string;
  expires_at?: string;
}

/** Google secrets are one pair per project, shared by every Google connector. */
export const GOOGLE_CLIENT_SECRET_NAMES = {
  clientId: "GOOGLE_CLIENT_ID",
  clientSecret: "GOOGLE_CLIENT_SECRET",
} as const;

/**
 * Google access tokens last an hour. Fifteen minutes of lead on a
 * five-minute cron is three chances to catch it. Refreshing hourly also
 * keeps the refresh token off Google's six-month inactivity clock.
 */
export const GOOGLE_REFRESH_POLICY: OAuthRefreshPolicy = {
  leadTimeMs: 15 * 60 * 1000,
  minIntervalMs: 5 * 60 * 1000,
};

interface TokenResponse {
  access_token?: string;
  refresh_token?: string;
  expires_in?: number;
  error?: string;
  error_description?: string;
}

/**
 * One OAuth leg for every Google connector. Only the scopes and the
 * post-authorise picker differ between Analytics and Search Console; the
 * token endpoint, its error vocabulary and the refresh policy are Google's,
 * not the API's.
 *
 * `fetch` rather than `ctx.http`, as in the GitHub adapter: these run
 * before any adapter context exists, against hosts fixed in this file.
 * `redirect: "manual"` still, so a token is never replayed across a hop.
 */
export function googleOAuth<C extends GoogleTokens>(options: {
  scopes: readonly string[];
  scopeSummary: readonly string[];
  selection: OAuthSelection<C>;
  /** Fields the code exchange leaves empty for the picker to fill. */
  empty: Omit<C, keyof GoogleTokens>;
}): OAuthConfig<C> {
  return {
    clientSecretNames: GOOGLE_CLIENT_SECRET_NAMES,
    scopes: options.scopes,
    scopeSummary: options.scopeSummary,

    authorizationUrl({ clientId, redirectUri, state }) {
      const url = new URL("https://accounts.google.com/o/oauth2/v2/auth");
      url.searchParams.set("client_id", clientId);
      url.searchParams.set("redirect_uri", redirectUri);
      url.searchParams.set("response_type", "code");
      url.searchParams.set("scope", options.scopes.join(" "));
      // Both, or there is no refresh token. `offline` asks for one;
      // `consent` makes Google issue it again on a re-authorisation, which
      // it otherwise only does the first time an account ever grants the
      // app. A reconnect without this comes back with an hour-long token
      // and nothing to renew it with.
      url.searchParams.set("access_type", "offline");
      url.searchParams.set("prompt", "consent");
      url.searchParams.set("state", state);
      return url.toString();
    },

    async exchangeCode({ code, redirectUri, clientId, clientSecret }) {
      const body = await token({
        code,
        redirect_uri: redirectUri,
        grant_type: "authorization_code",
        client_id: clientId,
        client_secret: clientSecret,
      });
      if (!hasToken(body)) {
        throw new ProviderError(
          "auth_failed",
          body.error_description ?? "Google would not complete the sign-in.",
        );
      }
      return { ...options.empty, ...tokens(body) } as C;
    },

    refresh: GOOGLE_REFRESH_POLICY,

    async refreshCredentials({ credentials, clientId, clientSecret }) {
      if (!credentials.refresh_token) return null;
      const body = await token({
        refresh_token: credentials.refresh_token,
        grant_type: "refresh_token",
        client_id: clientId,
        client_secret: clientSecret,
      });
      // `invalid_grant` is the grant being gone for good: revoked by the
      // user, expired through six months of disuse, or the account removed.
      // Only a fresh consent fixes it. Anything else is Google having a
      // moment, and the next tick tries again.
      if (body.error === "invalid_grant") {
        throw new OAuthReauthRequiredError(
          "Google has stopped honouring this connection. Reconnect it to carry on.",
        );
      }
      if (!hasToken(body)) {
        throw new Error(`Google token refresh failed: ${body.error ?? "no token"}`);
      }
      // A refresh answers without a refresh token; the one we hold stays
      // valid, so it is kept rather than overwritten with nothing.
      return { ...credentials, ...tokens(body) };
    },

    selection: options.selection,
  };
}

function hasToken(body: TokenResponse): body is TokenResponse & { access_token: string } {
  return typeof body.access_token === "string" && body.access_token.length > 0;
}

async function token(form: Record<string, string>): Promise<TokenResponse> {
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    redirect: "manual",
    headers: { "content-type": "application/x-www-form-urlencoded", accept: "application/json" },
    body: new URLSearchParams(form),
  });
  return (await response.json().catch(() => ({}))) as TokenResponse;
}

function tokens(body: TokenResponse & { access_token: string }): GoogleTokens {
  return {
    access_token: body.access_token,
    ...(body.refresh_token ? { refresh_token: body.refresh_token } : {}),
    ...(typeof body.expires_in === "number" && body.expires_in > 0
      ? { [EXPIRES_AT_FIELD]: String(Date.now() + body.expires_in * 1000) }
      : {}),
  };
}

/** Bearer headers for a Google API call made outside an adapter context. */
export function googleHeaders(accessToken: string): Record<string, string> {
  return { authorization: `Bearer ${accessToken}`, accept: "application/json" };
}
