import { PLANS } from "@notch/schemas";
import { SITE_NAME, absoluteUrl } from "@/lib/site";
import type { FaqEntry } from "@/lib/faq";

/**
 * Every piece of structured data this site emits, as builders.
 *
 * Builders rather than literals because the same shapes are now needed by
 * pages that are generated: ninety-odd `/sources` pages cannot each carry a
 * hand-written graph, and the one place a `@type` is spelled has to be the
 * one place it is spelled.
 *
 * Two rules are encoded here rather than left to each caller, because both
 * produce markup that validates and is then silently discarded:
 *
 * - **Every breadcrumb hop must be a page that returns 200.** A `ListItem`
 *   naming a URL that 404s is valid JSON and an unfetchable item, and Google
 *   drops the whole breadcrumb. `breadcrumbJsonLd` therefore also returns
 *   `null` below two items, since a one-hop trail is dropped anyway.
 * - **`item` and `url` are absolute.** A relative `item` passes the
 *   validator and resolves against nothing useful.
 */

/** A `@graph` wrapper. Callers hand it the nodes they want in one script. */
export function graph(...nodes: (Record<string, unknown> | null)[]): Record<string, unknown> {
  return {
    "@context": "https://schema.org",
    "@graph": nodes.filter((node): node is Record<string, unknown> => node !== null),
  };
}

export function organizationJsonLd(): Record<string, unknown> {
  return {
    "@type": "Organization",
    "@id": absoluteUrl("/#organization"),
    name: SITE_NAME,
    url: absoluteUrl("/"),
    logo: absoluteUrl("/brand/app-icon.png"),
    email: "support@notchmetrics.com",
  };
}

export function websiteJsonLd(): Record<string, unknown> {
  return {
    "@type": "WebSite",
    "@id": absoluteUrl("/#website"),
    name: SITE_NAME,
    url: absoluteUrl("/"),
    publisher: { "@id": absoluteUrl("/#organization") },
    inLanguage: "en",
  };
}

/**
 * The product, with its prices.
 *
 * Offers are built from `PLANS` so the markup cannot quote a price the
 * checkout no longer charges. A mismatch there is grounds for the whole
 * structured-data block being ignored.
 */
export function softwareApplicationJsonLd(): Record<string, unknown> {
  return {
    "@type": "SoftwareApplication",
    "@id": absoluteUrl("/#app"),
    name: SITE_NAME,
    applicationCategory: "BusinessApplication",
    operatingSystem: "macOS 14 or later, Apple silicon",
    url: absoluteUrl("/"),
    downloadUrl: absoluteUrl("/download"),
    description:
      "Revenue, MRR and subscribers from Stripe, Polar, Paddle, Dodo Payments and more, in the MacBook notch.",
    publisher: { "@id": absoluteUrl("/#organization") },
    offers: Object.values(PLANS).map((plan) => ({
      "@type": "Offer",
      // Schema.org prices are major units; ours are minor units, as money is
      // everywhere in this codebase.
      price: (plan.amount / 100).toFixed(2),
      priceCurrency: plan.currency,
      category: plan.interval === "year" ? "Annual subscription" : "Monthly subscription",
      url: absoluteUrl("/#pricing"),
    })),
  };
}

type PostLike = {
  slug: string;
  title: string;
  description: string;
  date: string;
  author: string;
  tags: string[];
  markdown: string;
};

export function blogJsonLd(
  posts: Pick<PostLike, "slug" | "title" | "description" | "date">[],
): Record<string, unknown> {
  return {
    "@type": "Blog",
    "@id": absoluteUrl("/blog#blog"),
    name: `${SITE_NAME} blog`,
    url: absoluteUrl("/blog"),
    publisher: { "@id": absoluteUrl("/#organization") },
    inLanguage: "en",
    blogPost: posts.map((post) => ({
      "@type": "BlogPosting",
      headline: post.title,
      description: post.description,
      datePublished: post.date,
      url: absoluteUrl(`/blog/${post.slug}`),
    })),
  };
}

/**
 * One post.
 *
 * `mainEntityOfPage` pointing back at the canonical URL is what stops a
 * syndicated or scraped copy of the text from being read as the original.
 */
export function articleJsonLd(
  post: PostLike,
  options: { path: string; modified: string; collection: string },
): Record<string, unknown> {
  const url = absoluteUrl(options.path);

  return {
    "@type": "BlogPosting",
    "@id": `${url}#post`,
    headline: post.title,
    description: post.description,
    url,
    mainEntityOfPage: { "@type": "WebPage", "@id": url },
    datePublished: post.date,
    dateModified: options.modified,
    author: { "@type": "Organization", name: post.author, url: absoluteUrl("/") },
    publisher: { "@id": absoluteUrl("/#organization") },
    isPartOf: { "@type": "Blog", "@id": absoluteUrl(options.collection) },
    keywords: post.tags.join(", "),
    wordCount: post.markdown.split(/\s+/).filter(Boolean).length,
    inLanguage: "en",
  };
}

/**
 * The FAQ, off the same array the page renders visibly.
 *
 * Returns `null` for an empty list: an `FAQPage` with no `mainEntity` is
 * markup claiming a section that is not on the page.
 */
export function faqPageJsonLd(entries: FaqEntry[], id: string): Record<string, unknown> | null {
  if (entries.length === 0) return null;

  return {
    "@type": "FAQPage",
    "@id": `${absoluteUrl(id)}#faq`,
    mainEntity: entries.map((entry) => ({
      "@type": "Question",
      name: entry.question,
      acceptedAnswer: { "@type": "Answer", text: entry.answer },
    })),
  };
}

/**
 * A breadcrumb trail. Every `path` must be a route that returns 200.
 *
 * `null` below two items, because Google drops a breadcrumb with fewer than
 * two `ListItem`s and emitting one is noise in the page source.
 */
export function breadcrumbJsonLd(
  trail: { name: string; path: string }[],
  id: string,
): Record<string, unknown> | null {
  if (trail.length < 2) return null;

  return {
    "@type": "BreadcrumbList",
    "@id": `${absoluteUrl(id)}#breadcrumbs`,
    itemListElement: trail.map((hop, index) => ({
      "@type": "ListItem",
      position: index + 1,
      name: hop.name,
      item: absoluteUrl(hop.path),
    })),
  };
}

/**
 * An index page's contents.
 *
 * `ItemList` rather than `CollectionPage`: the list is the useful part, and
 * every `url` is absolute for the reason at the top of this file.
 */
export function itemListJsonLd(
  items: { name: string; path: string }[],
  id: string,
): Record<string, unknown> {
  return {
    "@type": "ItemList",
    "@id": `${absoluteUrl(id)}#list`,
    numberOfItems: items.length,
    itemListElement: items.map((item, index) => ({
      "@type": "ListItem",
      position: index + 1,
      name: item.name,
      url: absoluteUrl(item.path),
    })),
  };
}

/** A `/sources/<provider>/<metric>` page's number, as a defined term. */
export function definedTermJsonLd(options: {
  name: string;
  description: string;
  path: string;
  setName: string;
  setPath: string;
}): Record<string, unknown> {
  const url = absoluteUrl(options.path);

  return {
    "@type": "DefinedTerm",
    "@id": `${url}#term`,
    name: options.name,
    description: options.description,
    url,
    inDefinedTermSet: {
      "@type": "DefinedTermSet",
      name: options.setName,
      url: absoluteUrl(options.setPath),
    },
  };
}
