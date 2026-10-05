import { applyD1Migrations, env } from "cloudflare:test";
import { drizzle } from "drizzle-orm/d1";
import { schema, user, widgetRevision } from "@notch/db";
import { id } from "../src/lib/ids.ts";

export async function migrate(): Promise<void> {
  await applyD1Migrations(env.DB, env.TEST_MIGRATIONS);
}

export function db() {
  return drizzle(env.DB, { schema });
}

export async function makeUser(overrides: Partial<typeof user.$inferInsert> = {}) {
  const userId = overrides.id ?? id("usr");
  const row = {
    id: userId,
    email: `${userId}@example.com`,
    name: "Test",
    plan: "pro",
    timezone: "UTC",
    preferredCurrency: "USD",
    trialEndsAt: new Date(Date.now() + 7 * 24 * 3600 * 1000),
    ...overrides,
  };
  await db().insert(user).values(row);
  await db().insert(widgetRevision).values({ userId, revision: 0 }).onConflictDoNothing();
  return row;
}

/**
 * `noUncheckedIndexedAccess` makes every index access `T | undefined`, which is
 * right and tedious where the row is known to exist.
 */
export function scalar<T>(value: T | undefined, what = "value"): T {
  if (value === undefined) throw new Error(`expected a ${what}`);
  return value;
}
