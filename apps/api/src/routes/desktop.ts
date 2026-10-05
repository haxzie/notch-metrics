import { Hono } from "hono";
import { and, eq, isNull } from "drizzle-orm";
import { DesktopAuthorizeRequest, DesktopTokenRequest } from "@notch/schemas";
import { desktopAuthCode, deviceToken } from "@notch/db";
import { authenticate, rateLimitedByIp, sessionOnly, type AppContext } from "../middleware.ts";
import { id, randomToken, sha256Base64Url, timingSafeEqual } from "../lib/ids.ts";
import { billingState } from "../lib/entitlement.ts";
import { loadUser } from "../lib/identity.ts";
import { publicUser } from "./me.ts";

/**
 * The desktop handshake: PKCE over a custom URL scheme.
 *
 * Device-code flows exist for devices that cannot open a browser. A Mac can,
 * and it can register a URL handler, so making somebody read a code off one
 * screen and type it into another is friction with nothing bought for it.
 */
export const desktop = new Hono<AppContext>();

/** Two minutes. Long enough to click "Allow", short enough that a leaked code is dead. */
const CODE_TTL_MS = 2 * 60 * 1000;

desktop.post("/authorize", authenticate, sessionOnly, async (c) => {
  const body = DesktopAuthorizeRequest.safeParse(await c.req.json().catch(() => ({})));
  if (!body.success)
    return c.json({ code: "BAD_REQUEST", message: "A challenge is required." }, 400);

  const code = randomToken(24);
  await c
    .get("db")
    .insert(desktopAuthCode)
    .values({
      code,
      challenge: body.data.challenge,
      userId: c.get("identity").userId,
      expiresAt: new Date(Date.now() + CODE_TTL_MS),
    });

  return c.json({ code, expiresIn: CODE_TTL_MS / 1000 });
});

desktop.post("/token", rateLimitedByIp(20, 600), async (c) => {
  const body = DesktopTokenRequest.safeParse(await c.req.json().catch(() => ({})));
  if (!body.success) return c.json({ code: "BAD_REQUEST", message: "Invalid request." }, 400);

  const db = c.get("db");
  const { code, verifier, label } = body.data;

  // One message for all three failure modes — unknown code, expired code,
  // wrong verifier. Distinguishing them tells an attacker which half of a
  // guess was right.
  const deny = () =>
    c.json({ code: "INVALID_GRANT", message: "That sign-in link is no longer valid." }, 400);

  const [row] = await db
    .select()
    .from(desktopAuthCode)
    .where(and(eq(desktopAuthCode.code, code), isNull(desktopAuthCode.consumedAt)))
    .limit(1);

  if (!row || row.expiresAt.getTime() < Date.now()) return deny();
  if (!timingSafeEqual(await sha256Base64Url(verifier), row.challenge)) return deny();

  // Consume *then* issue, and condition the update on it still being unconsumed.
  // Two concurrent exchanges of one code therefore produce exactly one token:
  // the second update matches no rows.
  const consumed = await db
    .update(desktopAuthCode)
    .set({ consumedAt: new Date() })
    .where(and(eq(desktopAuthCode.code, code), isNull(desktopAuthCode.consumedAt)))
    .returning({ code: desktopAuthCode.code });

  if (consumed.length === 0) return deny();

  const token = randomToken(32);
  await db.insert(deviceToken).values({
    id: id("dev"),
    tokenHash: await sha256Base64Url(token),
    userId: row.userId,
    label: label.slice(0, 80),
  });

  const u = await loadUser(db, row.userId);
  if (!u) return deny();

  return c.json({
    token,
    user: publicUser(u),
    billing: await billingState(db, row.userId),
  });
});

desktop.get("/entitlement", authenticate, async (c) =>
  c.json(await billingState(c.get("db"), c.get("identity").userId)),
);

desktop.post("/revoke", authenticate, async (c) => {
  const identity = c.get("identity");
  if (identity.deviceTokenId) {
    await c
      .get("db")
      .update(deviceToken)
      .set({ revokedAt: new Date() })
      .where(eq(deviceToken.id, identity.deviceTokenId));
  }
  return c.json({ ok: true });
});
