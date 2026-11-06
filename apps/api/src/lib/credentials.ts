import { openCredentials, sealedFromRow } from "./crypto.ts";
import type { Env } from "./../env.ts";
import type { integration as integrationTable } from "@notch/db";

type Row = typeof integrationTable.$inferSelect;

/**
 * One integration's credentials, decrypted.
 *
 * This used to be `openFreshCredentials`, which opened the blob and refreshed
 * the access token first if one was due. Every connector takes a key the user
 * pasted in now, so there is nothing to refresh and no token endpoint to
 * claim a lease against — the whole refresh sweep went with the last OAuth
 * connector.
 *
 * Kept as a named function rather than inlined at the three call sites: it is
 * the one place a credential leaves the database, which is where a log line
 * or an audit hook belongs if either is ever wanted.
 */
export async function openIntegrationCredentials(
  env: Env,
  row: Row,
): Promise<Record<string, string>> {
  return openCredentials(
    env,
    { userId: row.userId, integrationId: row.id, provider: row.provider },
    sealedFromRow(row),
  );
}
