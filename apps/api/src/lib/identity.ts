import { and, eq, isNull } from "drizzle-orm";
import { deviceToken, user } from "@notch/db";
import { sha256Base64Url } from "./ids.ts";
import type { Database } from "./db.ts";

/** How stale `device_token.last_used_at` is allowed to get. */
const LAST_USED_RESOLUTION_MS = 15 * 60 * 1000;

export interface Identity {
  userId: string;
  /** How this request authenticated. Some routes accept only one. */
  kind: "session" | "device";
  deviceTokenId: string | null;
}

/**
 * Resolves a device bearer token to a user.
 *
 * Only the hash is stored, so this hashes what arrived and looks that up —
 * there is no way to go the other direction, which is the point.
 */
export async function identityFromBearer(
  db: Database,
  authorization: string | null,
): Promise<Identity | null> {
  if (!authorization?.startsWith("Bearer ")) return null;
  const token = authorization.slice("Bearer ".length).trim();
  if (token.length < 16) return null;

  const hash = await sha256Base64Url(token);
  const rows = await db
    .select({ id: deviceToken.id, userId: deviceToken.userId, lastUsedAt: deviceToken.lastUsedAt })
    .from(deviceToken)
    .where(and(eq(deviceToken.tokenHash, hash), isNull(deviceToken.revokedAt)))
    .limit(1);

  const row = rows[0];
  if (!row) return null;

  // `lastUsedAt` answers "which of my Macs is still signed in", which
  // revocation depends on — but it does not need to be to-the-second, and this
  // runs on *every* authenticated request. Coalescing it to a quarter of an
  // hour drops roughly 95% of the writes, which is what makes a recurring
  // notification poll affordable: at one write per poll per device this single
  // timestamp would cost more than the rest of the feature put together.
  if (row.lastUsedAt === null || row.lastUsedAt.getTime() < Date.now() - LAST_USED_RESOLUTION_MS) {
    await db.update(deviceToken).set({ lastUsedAt: new Date() }).where(eq(deviceToken.id, row.id));
  }

  return { userId: row.userId, kind: "device", deviceTokenId: row.id };
}

export async function loadUser(db: Database, userId: string) {
  const rows = await db.select().from(user).where(eq(user.id, userId)).limit(1);
  return rows[0] ?? null;
}
