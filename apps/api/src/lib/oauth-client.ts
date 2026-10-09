import { getAdapter, oauthSecretNames } from "@notch/integrations";
import type { Env } from "../env.ts";

/**
 * A connector's OAuth client id and secret, from the Worker secrets named by
 * `oauthSecretNames`. Null when the deployment was never finished for this
 * connector — callers name that plainly rather than letting it surface as a
 * 500 nobody can act on.
 */
export function oauthClient(
  env: Env,
  connectorId: string,
): { clientId: string; clientSecret: string } | null {
  // A connector may name the secrets itself — every Google connector reads
  // the one Google client the server already has. Otherwise the pair is
  // derived from the provider id.
  const names =
    getAdapter(connectorId).oauth?.clientSecretNames ??
    oauthSecretNames(connectorId as Parameters<typeof oauthSecretNames>[0]);
  const bag = env as unknown as Record<string, string | undefined>;
  const clientId = bag[names.clientId];
  const clientSecret = bag[names.clientSecret];
  if (!clientId || !clientSecret) return null;
  return { clientId, clientSecret };
}
