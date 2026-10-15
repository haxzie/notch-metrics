import { z } from "zod";

/**
 * `desktop/latest.json` in R2, and the body of `GET /v1/updates/latest`.
 *
 * There is no Sparkle and no appcast — the Mac app polls this, compares
 * `build`, verifies the download against `sha256` *and* against the Developer
 * ID signature, then installs.
 */
export const LatestJson = z.object({
  version: z.string(),
  /**
   * A monotonically increasing integer.
   *
   * Comparing semver strings in Swift is doable and is one more thing to get
   * wrong — "0.10.0" sorts before "0.9.0" under a string compare, and that bug
   * only appears on the tenth minor release.
   *
   * Positive, so a manifest built from an unset variable is rejected rather
   * than published. Build 0 parses perfectly and is lower than every installed
   * copy, so it does not break a release — it makes the release invisible, to
   * everyone, with nothing anywhere saying why.
   */
  build: z.number().int().positive(),
  tag: z.string(),
  publishedAt: z.string(),
  platform: z.literal("darwin-arm64"),
  /** So a Mac on 14 is not offered 18 MB of a build that needs 15. */
  minimumSystemVersion: z.string(),
  filename: z.string(),
  url: z.url(),
  size: z.number().int(),
  sha256: z.string().length(64),
  notes: z.url().nullable().default(null),
  /** Set by the Worker when a release is being withheld. */
  mandatory: z.boolean().default(false),
});
export type LatestJson = z.infer<typeof LatestJson>;
