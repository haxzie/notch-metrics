import { Hono } from "hono";
import { count, eq } from "drizzle-orm";
import { z } from "zod";
import { deviceToken, integration, user as userTable, widget } from "@notch/db";
import { authenticate, sessionOnly, type AppContext } from "../middleware.ts";
import { billingState } from "../lib/entitlement.ts";
import { loadUser } from "../lib/identity.ts";

export function publicUser(row: typeof userTable.$inferSelect) {
  return {
    id: row.id,
    name: row.name,
    email: row.email,
    image: row.image,
    timezone: row.timezone,
    preferredCurrency: row.preferredCurrency,
    createdAt: row.createdAt.toISOString(),
  };
}

export const me = new Hono<AppContext>();

me.use("*", authenticate);

me.get("/", async (c) => {
  const db = c.get("db");
  const userId = c.get("identity").userId;

  const row = await loadUser(db, userId);
  if (!row) return c.json({ code: "NOT_FOUND", message: "No such account." }, 404);

  const [integrations] = await db
    .select({ n: count() })
    .from(integration)
    .where(eq(integration.userId, userId));
  const [widgets] = await db.select({ n: count() }).from(widget).where(eq(widget.userId, userId));

  return c.json({
    user: publicUser(row),
    billing: await billingState(db, userId),
    counts: { integrations: integrations?.n ?? 0, widgets: widgets?.n ?? 0 },
  });
});

const PatchMe = z.object({
  name: z.string().min(1).max(80).optional(),
  // Validated against the runtime's own tz database rather than a hardcoded
  // list, which would go stale the next time a country changes its rules.
  timezone: z
    .string()
    .refine((tz) => {
      try {
        new Intl.DateTimeFormat("en", { timeZone: tz });
        return true;
      } catch {
        return false;
      }
    }, "Unknown time zone")
    .optional(),
  preferredCurrency: z
    .string()
    .length(3)
    .regex(/^[A-Z]{3}$/)
    .optional(),
});

me.patch("/", async (c) => {
  const body = PatchMe.safeParse(await c.req.json().catch(() => ({})));
  if (!body.success) return c.json({ code: "BAD_REQUEST", message: "Invalid request." }, 400);

  const userId = c.get("identity").userId;
  await c.get("db").update(userTable).set(body.data).where(eq(userTable.id, userId));

  const row = await loadUser(c.get("db"), userId);
  return row
    ? c.json(publicUser(row))
    : c.json({ code: "NOT_FOUND", message: "No such account." }, 404);
});

me.get("/devices", sessionOnly, async (c) => {
  const rows = await c
    .get("db")
    .select()
    .from(deviceToken)
    .where(eq(deviceToken.userId, c.get("identity").userId));

  return c.json(
    rows
      .filter((r) => r.revokedAt === null)
      .map((r) => ({
        id: r.id,
        label: r.label,
        lastUsedAt: r.lastUsedAt?.toISOString() ?? null,
        createdAt: r.createdAt.toISOString(),
      })),
  );
});

me.delete("/devices/:id", sessionOnly, async (c) => {
  await c
    .get("db")
    .update(deviceToken)
    .set({ revokedAt: new Date() })
    .where(eq(deviceToken.id, c.req.param("id")));
  return c.json({ ok: true });
});

/**
 * Deletes the account, and with it every ciphertext.
 *
 * Requires the email in the body: this is unrecoverable, there is no backup of
 * a user's Stripe key, and a misrouted DELETE should not be able to do it.
 */
me.delete("/", sessionOnly, async (c) => {
  const body: { confirm?: string } = await c.req.json<{ confirm?: string }>().catch(() => ({}));
  const userId = c.get("identity").userId;
  const row = await loadUser(c.get("db"), userId);

  if (!row || body.confirm !== row.email) {
    return c.json(
      { code: "CONFIRM_REQUIRED", message: "Send your email address to confirm." },
      400,
    );
  }

  // Every owned table cascades from `user`, so this one statement removes the
  // integrations and therefore every encrypted credential.
  await c.get("db").delete(userTable).where(eq(userTable.id, userId));
  return c.json({ ok: true });
});
