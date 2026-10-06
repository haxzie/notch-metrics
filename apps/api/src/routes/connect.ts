import { Hono } from "hono";
import { eq } from "drizzle-orm";
import { getAdapter } from "@notch/integrations";
import { connectLink } from "@notch/db";
import { authenticate, rateLimited, type AppContext } from "../middleware.ts";
import { id, randomToken, sha256Base64Url } from "../lib/ids.ts";

/**
 * Minting a connect link.
 *
 * The Mac app cannot show a credentials form itself and should not try: an
 * OAuth flow has to happen in a real browser with a real address bar, and a
 * native window asking for a Stripe key is indistinguishable from one a
 * phishing app would show. So the app asks for a link, opens it, and waits.
 *
 * The token is short-lived, single-use and bound to the user who minted it.
 * It travels in a URL, so it is stored hashed — a leaked server log or
 * browser history should not be a working credential.
 */
export const connect = new Hono<AppContext>();

/** Ten minutes: long enough to find your API key, short enough to be useless later. */
const LINK_TTL_MS = 10 * 60 * 1000;

connect.post(
  "/:connectorId",
  authenticate,
  rateLimited({ limit: 30, windowSeconds: 3600 }),
  async (c) => {
    const connectorId = c.req.param("connectorId");

    let adapter;
    try {
      adapter = getAdapter(connectorId);
    } catch {
      return c.json({ code: "NOT_FOUND", message: "Unknown connector." }, 404);
    }

    if (adapter.manifest.status === "coming_soon") {
      return c.json(
        {
          code: "NOT_AVAILABLE",
          message: `${adapter.manifest.name} is not ready to connect yet.`,
        },
        409,
      );
    }

    const token = randomToken(32);
    await c
      .get("db")
      .insert(connectLink)
      .values({
        id: id("lnk"),
        // Hashed, for the same reason a device token is: the plaintext exists
        // in the response and in the browser's address bar, and neither should
        // be enough to resume somebody else's connect flow.
        tokenHash: await sha256Base64Url(token),
        userId: c.get("identity").userId,
        connectorId,
        expiresAt: new Date(Date.now() + LINK_TTL_MS),
      });

    return c.json({
      url: `${c.env.APP_URL}/connect/${token}`,
      connectorId,
      expiresIn: LINK_TTL_MS / 1000,
    });
  },
);

/**
 * What the app polls while the browser is open.
 *
 * The alternative is a deep link back from the website, which is also wired —
 * but a browser that was closed, or a redirect a security extension ate,
 * would leave the app waiting forever with no way to notice.
 */
connect.get("/:connectorId/status", authenticate, async (c) => {
  const rows = await c
    .get("db")
    .select()
    .from(connectLink)
    .where(eq(connectLink.userId, c.get("identity").userId));

  const latest = rows
    .filter((r) => r.connectorId === c.req.param("connectorId"))
    .sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime())[0];

  if (!latest) return c.json({ state: "none" });
  if (latest.completedAt)
    return c.json({ state: "connected", integrationId: latest.integrationId });
  if (latest.expiresAt.getTime() < Date.now()) return c.json({ state: "expired" });
  return c.json({ state: "pending" });
});
