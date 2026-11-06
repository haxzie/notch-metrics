import { z } from "zod";
import { metricsFor } from "../../metric.ts";

export const credentialSchema = z.object({
  /**
   * A personal access token: `ghp_` classic, or `github_pat_` fine-grained.
   *
   * Deliberately looser than the manifest's `pattern`. That one is a hint the
   * app renders over what somebody types; this one also parses the blob back
   * out of the database, where a connection made under the old OAuth flow
   * still carries a `gho_` token that works. A prefix check here would fail
   * those rows on the first fetch after deploying, which reads as every
   * GitHub tile breaking at once.
   */
  access_token: z.string().min(8),
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
