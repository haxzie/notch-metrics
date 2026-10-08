import { Hono } from "hono";
import { eq } from "drizzle-orm";
import { REGISTRY_VERSION, catalogue, connectable } from "@notch/integrations";
import { CONNECTOR_CATEGORY_LABELS, type ConnectorCategory } from "@notch/schemas";
import { integration as integrationTable } from "@notch/db";
import { authenticate, type AppContext } from "../middleware.ts";
import { identityFromBearer } from "../lib/identity.ts";

/**
 * The connector catalogue: everything the app can connect to, grouped the way
 * the settings UI lists it.
 *
 * Public and unauthenticated. The Mac fetches this on first launch, before
 * anybody has signed in, and an app that cannot say what it connects to until
 * you have an account is an app that cannot explain what it is for.
 *
 * This is also the reason a new connector needs no Mac release: the settings
 * UI is rendered from this response, not from anything compiled into the app.
 */
export const connectors = new Hono<AppContext>();

const CACHE_CONTROL = "public, max-age=300, s-maxage=3600";

connectors.get("/", async (c) => {
  const etag = `W/"${REGISTRY_VERSION}"`;

  // Connected accounts are folded in when the caller is signed in, so the app
  // can render "Connected · Acme Inc" against a row without a second request
  // and a flash of the wrong state.
  //
  // Resolved by hand rather than through `authenticate`, because this route
  // has to answer for anonymous callers too.
  const identity = await identityFromBearer(c.get("db"), c.req.header("authorization") ?? null);

  // Revalidation is answered only for anonymous callers, and deliberately
  // after identity is known.
  //
  // The ETag is a fingerprint of the manifests, which are identical for
  // everyone — so a signed-in client holding a cached *anonymous* response
  // would revalidate, be told 304, and keep a body with no connections in it.
  // Permanently: the manifests do not change when somebody connects an
  // account. Every app read "not connected" however many were.
  if (!identity && c.req.header("if-none-match") === etag) {
    return c.body(null, 304, { etag, "cache-control": CACHE_CONTROL });
  }

  const connected = new Map<string, { id: string; label: string; status: string }[]>();
  if (identity) {
    const rows = await c
      .get("db")
      .select()
      .from(integrationTable)
      .where(eq(integrationTable.userId, identity.userId));
    for (const row of rows) {
      const list = connected.get(row.provider) ?? [];
      list.push({
        id: row.id,
        label: row.label,
        status: row.status,
      });
      connected.set(row.provider, list);
    }
  }

  return c.json(
    {
      version: REGISTRY_VERSION,
      categories: catalogue().map(({ category, connectors: list }) => ({
        id: category,
        label: CONNECTOR_CATEGORY_LABELS[category as ConnectorCategory],
        connectors: list.map((manifest) => ({
          ...manifest,
          // Never a credential, and never enough to identify an account to
          // anybody who should not already know it.
          connections: connected.get(manifest.id) ?? [],
        })),
      })),
    },
    200,
    // Only safe to cache publicly when the response carries nothing
    // user-specific.
    //
    // `vary: authorization` on the public one, because a cache that keys on
    // the URL alone — Foundation's URLCache does — would otherwise hand a
    // signed-in client the anonymous body for the next five minutes, and
    // that body says the user has no connections.
    identity
      ? { "cache-control": "private, max-age=30", vary: "authorization" }
      : { etag, "cache-control": CACHE_CONTROL, vary: "authorization" },
  );
});

/** Just the ids a user could connect right now. Used by the web connect page. */
connectors.get("/connectable", async (c) =>
  c.json(
    { connectors: connectable().map((m) => ({ id: m.id, name: m.name, authMode: m.authMode })) },
    200,
    { "cache-control": CACHE_CONTROL },
  ),
);

connectors.get("/:id", authenticate, async (c) => {
  const manifest = catalogue()
    .flatMap((group) => group.connectors)
    .find((m) => m.id === c.req.param("id"));
  if (!manifest) return c.json({ code: "NOT_FOUND", message: "Unknown connector." }, 404);
  return c.json(manifest);
});
