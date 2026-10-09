/**
 * When each legal page's text last changed.
 *
 * Shared rather than written into the page, because the sitemap reports the
 * same date as `lastModified`. Two copies drift, and the half that drifts is
 * always the sitemap — which is the half that decides whether a crawler
 * bothers to re-read the page at all.
 *
 * Bump the date here in the same commit that changes the wording.
 */
export const LEGAL_UPDATED = {
  privacy: "2026-10-09",
  terms: "2026-10-09",
} as const;
