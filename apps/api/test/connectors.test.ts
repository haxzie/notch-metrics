import { env } from "cloudflare:test";
import { createExecutionContext } from "cloudflare:test";
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import { ConnectorCategory, ProviderId } from "@notch/schemas";
import { deviceToken, integration, user } from "@notch/db";
import worker from "../src/index.ts";
import { id, randomToken, sha256Base64Url } from "../src/lib/ids.ts";
import { db, makeUser, migrate, scalar } from "./helpers.ts";

beforeAll(migrate);
beforeEach(async () => {
  await db().delete(integration);
  await db().delete(deviceToken);
  await db().delete(user);
});

const ctx = createExecutionContext();

function get(path: string, token?: string) {
  return worker.fetch(
    new Request(`http://localhost:8787${path}`, {
      headers: token ? { authorization: `Bearer ${token}` } : {},
    }),
    env,
    ctx,
  );
}

interface Catalogue {
  version: string;
  categories: {
    id: string;
    label: string;
    connectors: {
      id: string;
      name: string;
      category: string;
      authMode: string;
      status: string;
      fields: { key: string; type: string }[];
      oauth?: { scopeSummary: string[]; requiresSelection: boolean };
      connections: { id: string; label: string; status: string }[];
    }[];
  }[];
}

describe("the connector catalogue", () => {
  it("is readable without signing in", async () => {
    // The app fetches this on first launch, before anybody has an account.
    const response = await get("/v1/connectors");
    expect(response.status).toBe(200);
    expect(response.headers.get("cache-control")).toContain("public");
  });

  it("returns every category in a deliberate order", async () => {
    const body = await (await get("/v1/connectors")).json<Catalogue>();
    expect(body.categories.map((c) => c.id)).toEqual([
      "revenue",
      "analytics",
      "marketing",
      "crm",
      "developer",
    ]);
    expect(body.categories.map((c) => c.label)).toEqual([
      "Revenue",
      "Product analytics",
      "Marketing & SEO",
      "CRM",
      "Developer",
    ]);
    // Money first is the deliberate part. The rest is grouping; this asserts
    // none of them went missing, which is the failure that actually happens.
    expect(body.categories).toHaveLength(ConnectorCategory.options.length);
  });

  it("puts working connectors before coming-soon ones", async () => {
    // A category whose first three rows are all greyed out reads as a product
    // that does not work yet.
    const body = await (await get("/v1/connectors")).json<Catalogue>();

    for (const group of body.categories) {
      const rank = group.connectors.map((c) => (c.status === "coming_soon" ? 1 : 0));
      // Sorted, i.e. no working connector appears after a greyed-out one.
      expect(rank).toEqual(rank.slice().sort());
    }

    const revenue = scalar(body.categories.find((c) => c.id === "revenue"));
    expect(scalar(revenue.connectors[0]).status).toBe("stable");
  });

  it("describes every connector well enough to render a connect page", async () => {
    const body = await (await get("/v1/connectors")).json<Catalogue>();
    const all = body.categories.flatMap((c) => c.connectors);
    // Every registered connector must appear. A hardcoded number here hid a
    // real bug once: a new category was dropped from the grouping and its
    // connectors silently disappeared from the catalogue.
    expect(all.map((c) => c.id).sort()).toEqual(ProviderId.options.slice().sort());

    for (const connector of all) {
      expect(connector.name, connector.id).toBeTruthy();
      expect(["api_key", "oauth2"]).toContain(connector.authMode);

      if (connector.authMode === "oauth2") {
        // Tokens are never typed in, so an OAuth connector must not ask for
        // one as a form field.
        const secretFields = connector.fields.filter((f) => f.type === "secret");
        expect(secretFields, connector.id).toHaveLength(0);
        // And it has to be able to tell the user what it is asking for.
        expect(connector.oauth?.scopeSummary.length, connector.id).toBeGreaterThan(0);
      } else {
        expect(connector.fields.length, connector.id).toBeGreaterThan(0);
      }
    }
  });

  it("never leaks a credential into the catalogue", async () => {
    const u = await makeUser();
    const token = randomToken(32);
    await db()
      .insert(deviceToken)
      .values({
        id: id("dev"),
        tokenHash: await sha256Base64Url(token),
        userId: u.id,
        label: "Mac",
      });
    await db()
      .insert(integration)
      .values({
        id: id("int"),
        userId: u.id,
        provider: "stripe",
        label: "Acme",
        credentialCiphertext: "CIPHERTEXT_SENTINEL",
        credentialIv: "IV_SENTINEL",
        credentialWrappedDek: "DEK_SENTINEL",
        keyVersion: 1,
        credentialHint: "rk_live_…4f2a",
        credentialFingerprint: "fp",
        accountLabel: "Acme Inc",
      });

    const raw = await (await get("/v1/connectors", token)).text();
    for (const sentinel of ["CIPHERTEXT_SENTINEL", "IV_SENTINEL", "DEK_SENTINEL"]) {
      expect(raw).not.toContain(sentinel);
    }

    const body = JSON.parse(raw) as Catalogue;
    const stripe = scalar(
      body.categories.flatMap((c) => c.connectors).find((x) => x.id === "stripe"),
    );
    expect(stripe.connections).toHaveLength(1);
    expect(scalar(stripe.connections[0]).label).toBe("Acme Inc");
  });

  it("does not cache a signed-in response publicly", async () => {
    const u = await makeUser();
    const token = randomToken(32);
    await db()
      .insert(deviceToken)
      .values({
        id: id("dev"),
        tokenHash: await sha256Base64Url(token),
        userId: u.id,
        label: "Mac",
      });
    // It carries connected-account state, so a shared cache must not keep it.
    const response = await get("/v1/connectors", token);
    expect(response.headers.get("cache-control")).toContain("private");
  });
});

describe("managing a connection from the desktop app", () => {
  it("renames and disconnects with a device token", async () => {
    // The app is where people manage connections; sending them to a browser
    // to delete one is how a dead credential sits there failing for months.
    const u = await makeUser();
    const token = randomToken();
    await db()
      .insert(deviceToken)
      .values({
        id: id("dev"),
        userId: u.id,
        tokenHash: await sha256Base64Url(token),
        label: "Mac",
      });
    const integrationId = id("int");
    await db().insert(integration).values({
      id: integrationId,
      userId: u.id,
      provider: "stripe",
      label: "Stripe",
      credentialCiphertext: "x",
      credentialIv: "x",
      credentialWrappedDek: "x",
      keyVersion: 1,
      credentialHint: "sk_test_…1234",
      credentialFingerprint: "fp",
      enabledMetrics: [],
      availableMetrics: [],
    });

    const renamed = await worker.fetch(
      new Request(`http://localhost:8787/v1/integrations/${integrationId}`, {
        method: "PATCH",
        headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
        body: JSON.stringify({ label: "Stripe — Acme" }),
      }),
      env,
      ctx,
    );
    expect(renamed.status).toBe(200);
    expect((await renamed.json()) as { label: string }).toMatchObject({ label: "Stripe — Acme" });

    const removed = await worker.fetch(
      new Request(`http://localhost:8787/v1/integrations/${integrationId}`, {
        method: "DELETE",
        headers: { authorization: `Bearer ${token}` },
      }),
      env,
      ctx,
    );
    expect(removed.status).toBe(200);
    expect(await db().select().from(integration)).toHaveLength(0);
  });

  it("still refuses to replace credentials without a browser session", async () => {
    // That is the one route taking a raw provider key, and the app never
    // handles one — the connect-link flow exists so it does not have to.
    const u = await makeUser();
    const token = randomToken();
    await db()
      .insert(deviceToken)
      .values({
        id: id("dev"),
        userId: u.id,
        tokenHash: await sha256Base64Url(token),
        label: "Mac",
      });
    const integrationId = id("int");
    await db().insert(integration).values({
      id: integrationId,
      userId: u.id,
      provider: "stripe",
      label: "Stripe",
      credentialCiphertext: "x",
      credentialIv: "x",
      credentialWrappedDek: "x",
      keyVersion: 1,
      credentialHint: "sk_test_…1234",
      credentialFingerprint: "fp",
      enabledMetrics: [],
      availableMetrics: [],
    });

    const response = await worker.fetch(
      new Request(`http://localhost:8787/v1/integrations/${integrationId}`, {
        method: "PATCH",
        headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
        body: JSON.stringify({ credentials: { secret_key: "sk_test_51Abcdefghijklmnop" } }),
      }),
      env,
      ctx,
    );
    expect(response.status).toBe(403);
    expect((await response.json()) as { code: string }).toMatchObject({ code: "SESSION_REQUIRED" });
  });
});
