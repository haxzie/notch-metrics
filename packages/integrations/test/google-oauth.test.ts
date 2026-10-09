import { afterEach, describe, expect, it, vi } from "vitest";
import { googleOAuth, dayAt, ymd } from "../src/google-oauth.ts";
import { OAuthReauthRequiredError } from "../src/oauth.ts";
import { ProviderError } from "../src/types.ts";

type Creds = { access_token: string; refresh_token?: string; expires_at?: string; site: string };

const oauth = googleOAuth<Creds>({
  scopes: ["https://www.googleapis.com/auth/webmasters.readonly"],
  scopeSummary: ["Read"],
  empty: { site: "" },
  selection: { label: "Site", field: "site", options: async () => [] },
});
const client = { clientId: "123.apps.googleusercontent.com", clientSecret: "s" };

function stubToken(body: Record<string, unknown>, status = 200) {
  const calls: URLSearchParams[] = [];
  vi.stubGlobal("fetch", async (_url: string, init?: RequestInit) => {
    calls.push(new URLSearchParams(String(init?.body)));
    return new Response(JSON.stringify(body), { status });
  });
  return calls;
}

describe("google oauth", () => {
  afterEach(() => vi.unstubAllGlobals());

  it("reads the shared Google client, not a per-provider one", () => {
    expect(oauth.clientSecretNames).toEqual({
      clientId: "GOOGLE_CLIENT_ID",
      clientSecret: "GOOGLE_CLIENT_SECRET",
    });
  });

  it("asks for offline access with a forced consent, or there is no refresh token", () => {
    const url = new URL(
      oauth.authorizationUrl({
        clientId: client.clientId,
        redirectUri: "https://api/cb",
        state: "s",
      }),
    );
    expect(url.searchParams.get("access_type")).toBe("offline");
    expect(url.searchParams.get("prompt")).toBe("consent");
    expect(url.searchParams.get("scope")).toContain("webmasters.readonly");
  });

  it("stores the pair and the expiry from the code exchange", async () => {
    const calls = stubToken({ access_token: "ya29.a", refresh_token: "1//r", expires_in: 3599 });
    const creds = await oauth.exchangeCode({ code: "c", redirectUri: "https://api/cb", ...client });
    expect(calls[0]?.get("grant_type")).toBe("authorization_code");
    expect(creds).toMatchObject({ access_token: "ya29.a", refresh_token: "1//r", site: "" });
    expect(Number(creds.expires_at)).toBeGreaterThan(Date.now() + 3500 * 1000);
  });

  it("rejects an exchange with no token as an auth failure", async () => {
    stubToken({ error: "invalid_grant", error_description: "Bad code" });
    await expect(
      oauth.exchangeCode({ code: "c", redirectUri: "https://api/cb", ...client }),
    ).rejects.toMatchObject({ code: "auth_failed", message: "Bad code" });
  });

  it("keeps the refresh token across a refresh, since Google does not resend it", async () => {
    stubToken({ access_token: "ya29.b", expires_in: 3599 });
    const next = await oauth.refreshCredentials({
      credentials: { access_token: "ya29.a", refresh_token: "1//r", site: "sc-domain:x" },
      ...client,
    });
    expect(next).toMatchObject({
      access_token: "ya29.b",
      refresh_token: "1//r",
      site: "sc-domain:x",
    });
  });

  it("asks for a human on invalid_grant and retries on anything else", async () => {
    stubToken({ error: "invalid_grant" });
    await expect(
      oauth.refreshCredentials({
        credentials: { access_token: "a", refresh_token: "r", site: "" },
        ...client,
      }),
    ).rejects.toBeInstanceOf(OAuthReauthRequiredError);

    stubToken({}, 503);
    const transient = oauth.refreshCredentials({
      credentials: { access_token: "a", refresh_token: "r", site: "" },
      ...client,
    });
    await expect(transient).rejects.not.toBeInstanceOf(OAuthReauthRequiredError);
    await expect(transient).rejects.not.toBeInstanceOf(ProviderError);
  });

  it("has nothing to refresh without a refresh token", async () => {
    const calls = stubToken({});
    expect(
      await oauth.refreshCredentials({ credentials: { access_token: "a", site: "" }, ...client }),
    ).toBeNull();
    expect(calls).toHaveLength(0);
  });
});

describe("google dates", () => {
  it("formats a moment as the user's calendar day", () => {
    const late = new Date("2026-10-09T23:30:00Z");
    expect(ymd(late, "UTC")).toBe("2026-10-09");
    expect(ymd(late, "Asia/Kolkata")).toBe("2026-10-10");
  });

  it("reads Google's two date spellings to the same day", () => {
    expect(dayAt("20261009").toISOString()).toBe("2026-10-09T12:00:00.000Z");
    expect(dayAt("2026-10-09").toISOString()).toBe("2026-10-09T12:00:00.000Z");
  });
});
