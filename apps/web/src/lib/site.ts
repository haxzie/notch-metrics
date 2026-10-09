import type { Metadata } from "next";

/**
 * The site's own origin, in one place.
 *
 * `metadataBase`, the sitemap, robots.txt, every canonical URL and every
 * JSON-LD `@id` have to agree on it. When they disagree, a crawler treats
 * the disagreement as two sites and splits the ranking between them — a
 * failure that never shows up in a local build, because locally both halves
 * read the same fallback.
 *
 * No trailing slash, so `${SITE_URL}${path}` is always correct.
 */
export const SITE_URL = (process.env.NEXT_PUBLIC_APP_URL ?? "https://notchmetrics.com").replace(
  /\/+$/,
  "",
);

export const SITE_NAME = "Notch Metrics";

/**
 * An absolute URL for a site-relative path.
 *
 * `"/"` returns the bare origin with no trailing slash, because that is the
 * form Next emits for `alternates.canonical: "/"`. Without this, the home
 * page's canonical, its JSON-LD `url` and its sitemap entry would be three
 * spellings of one URL — exactly the split this module exists to prevent.
 */
export function absoluteUrl(path: string): string {
  if (path === "/" || path === "") return SITE_URL;
  return `${SITE_URL}${path.startsWith("/") ? path : `/${path}`}`;
}

/**
 * The plain-text mirrors, as `<link rel="alternate">`.
 *
 * Set on the home page and the blog, whose content these files mirror, rather
 * than once in the root layout — a `rel="alternate"` on the billing page is
 * a claim that is not true. Discovery for everything else is robots.txt.
 *
 * Spread rather than inherited in any case: Next replaces the whole
 * `alternates` object when a child declares one, so a page with its own
 * canonical would otherwise drop these.
 */
export const LLM_ALTERNATES: NonNullable<NonNullable<Metadata["alternates"]>["types"]> = {
  "text/plain": [
    { url: "/llms.txt", title: `${SITE_NAME} — index for LLMs` },
    { url: "/llms-full.txt", title: `${SITE_NAME} — full text for LLMs` },
  ],
};
