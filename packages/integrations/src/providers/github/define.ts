import { z } from "zod";
import { EXPIRES_AT_FIELD } from "../../oauth.ts";
import { metricsFor } from "../../metric.ts";

export const credentialSchema = z.object({
  access_token: z.string().min(8),
  // Both present only when the OAuth App has "expire user authorization
  // tokens" switched on. GitHub turns that on by default for new apps, and
  // the tokens it then issues still start with `gho_` — so nothing about the
  // token itself says whether it will stop working in eight hours.
  refresh_token: z.string().min(8).optional(),
  [EXPIRES_AT_FIELD]: z.string().regex(/^\d+$/).optional(),
  /**
   * Legacy. Connections made before the repository moved onto the widget
   * carry one here, and their widgets have no `repository` param to supply —
   * so `fetchMetric` still falls back to it. Nothing writes it any more.
   */
  repository: z
    .string()
    .regex(/^[\w.-]+\/[\w.-]+$/, "A repository looks like owner/name.")
    .optional(),
});
export type GitHubCredentials = z.infer<typeof credentialSchema>;

/**
 * The factories, bound to this connector's credentials once.
 *
 * Every metric file imports these rather than `scalarMetric<GitHubCredentials>`
 * — a file that forgot the type parameter would widen `creds` to the base
 * record, which still compiles and then fails on the first property read.
 */
export const { scalar, list } = metricsFor<GitHubCredentials>();
