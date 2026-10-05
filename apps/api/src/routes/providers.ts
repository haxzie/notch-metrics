import { Hono } from "hono";
import { REGISTRY_VERSION, manifests } from "@notch/integrations";
import type { AppContext } from "../middleware.ts";

/**
 * The provider catalogue the Mac settings UI renders from.
 *
 * Public and unauthenticated on purpose. The app fetches this on first launch,
 * before anybody has signed in, and an app that cannot say what it connects to
 * until you have an account is an app that cannot explain what it is for.
 *
 * Nothing here is user-specific, so it is identical for everyone and cacheable
 * at the edge.
 */
export const providers = new Hono<AppContext>();

const CACHE_CONTROL = "public, max-age=300, s-maxage=3600";

providers.get("/", async (c) => {
  const etag = `W/"${REGISTRY_VERSION}"`;

  // The app sends If-None-Match and keeps the last 200 on disk, so a cold
  // launch with no network still renders the list it saw yesterday.
  if (c.req.header("if-none-match") === etag) {
    return c.body(null, 304, { etag, "cache-control": CACHE_CONTROL });
  }

  return c.json({ version: REGISTRY_VERSION, providers: manifests() }, 200, {
    etag,
    "cache-control": CACHE_CONTROL,
  });
});

providers.get("/:id", async (c) => {
  const manifest = manifests().find((m) => m.id === c.req.param("id"));
  if (!manifest) return c.json({ code: "NOT_FOUND", message: "Unknown provider." }, 404);
  return c.json(manifest, 200, { "cache-control": CACHE_CONTROL });
});
