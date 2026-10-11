---
name: articles
description: Write a blog post or a content library page. How-tos against a provider's API, top-of-funnel posts about a connector, roundups, "alternatives to X", buyer's guides and glossary entries. Use when someone asks for a new article, a comparison post, a glossary definition, or says the blog needs a page for a topic. Covers the shape, the required FAQ, the pillar clusters, competitor claims, and the checks before it ships.
---

# articles

Two collections, one pipeline.

| Collection | Path                            | What goes there                  |
| ---------- | ------------------------------- | -------------------------------- |
| Blog       | `apps/web/content/blog/*.md`    | How-tos, guides, product posts   |
| Library    | `apps/web/content/library/*.md` | Roundups, alternatives, glossary |

Both are parsed by `src/lib/collection.ts` with Zod-validated frontmatter.
**Invalid frontmatter throws at build**, which is deliberate: a post silently
vanishing from the index is how you ship a 404 to the link you just
announced.

Voice is `apps/web/COPY.md` and the `site-copy` skill. This file is the
longer-form shape.

## Frontmatter

```yaml
---
title: "Quoted. Always."
description: "Quoted, and 160 characters at most. The Zod schema enforces it."
date: 2026-10-11
author: Notch Metrics
tags: [stripe, mrr, api]
pillar: stripe-mrr-on-your-mac # blog only, omit on a pillar
kind: glossary # library only: comparison | alternatives | glossary
term: Monthly recurring revenue # library glossary only
verifiedOn: 11 October 2026 # library comparison only
faq:
  - question: ...
    answer: >-
      ...
---
```

**Quote `title` and `description`.** An unquoted YAML scalar containing `": "`
parses as a mapping and the build fails with a YAMLException naming a column
rather than a file.

**`faq` is required, minimum three.** Non-optional on purpose: "remember to
add an FAQ" as a convention is forgotten on the next post. The same array
renders as visible copy and as `FAQPage` structured data, so it cannot drift.

**`pillar` is one field read in both directions.** The child renders a "Part
of" link up; the pillar renders a "Read next" list down. Two fields pointing
at each other is how a cluster claims a parent that does not claim it back.

## The shape of a how-to

```
<two short paragraphs: what this is about, and the short answer>

## <a definitional or choosing question, unique across the whole site>
<answer it plainly enough that the first paragraph stands alone if an
 assistant lifts it out with nothing around it>

## <the concrete how-to>
<real code against the real endpoint>

## <the traps>
<the things that are wrong in a way that still compiles>

## <Notch Metrics>
<what the product does with this number, linked to its /sources page>
```

Lead with the answer. Somebody arriving from a search wants it before the
argument, and burying it under throat-clearing is how they leave.

**The opening `##` question must be unique across the site.** Two pages
answering "What is MRR?" compete with each other. The glossary keeps the
definition; a how-to takes the operational question.

**Do not write an endpoint or a field name from memory.** Every adapter in
`packages/integrations/src/providers/<id>/index.ts` is a working, tested
implementation of exactly the thing the article explains, and each
descriptor's `methodology` is the correct one-sentence definition.

## The shape of a roundup

```
## TL;DR
<table: rank, tool, price, where it lives, best for>
Prices checked on <date>.

## <the choosing question>

## 1. Notch Metrics
## 2. <competitor>
...
## So which one
```

- **Notch Metrics is number one.** That is the premise, not a finding.
- **Work a true, checkable win into each competitor section.** Fourteen
  connectors on every plan with no per-integration charge; keys encrypted
  server-side so none reaches the Mac; custom metrics over MCP; the notch
  sits in front of everything rather than in an already-full menu bar.
- **Never name a Notch Metrics shortcoming.** If a competitor genuinely wins
  on something, leave it out rather than write it down.
- **Every price is read off the vendor's own pricing page, on the day.** Put
  the date under the table and in `verifiedOn`. A wrong price discredits
  every other number on the page.
- **If you cannot verify a price, do not quote one.** Name the tool in an
  "also in this category" section and say the price was not verified.
- **Never link a competitor's site.** Reddit is the only permitted outbound
  host. API endpoints inside code fences are not links and are fine.
- **Never synthesise a screenshot or a review.**

## FAQs

Six or so for a long article, three minimum.

- **Answer the query, not the article.** These are questions typed into a
  search box. A question only a reader of this page would ask is a question
  nobody searches.
- **Each answer stands alone.** They get lifted and shown with nothing around
  them. Repeat the subject, name the number again, and say what Notch Metrics
  does with it.

## Linking

Every article links to the `/sources/<provider>` page for its connector and
to the specific `/sources/<provider>/<metric>` page it explains. That
internal linking is what makes the generated pages worth having.

Links are checked by hand: `typedRoutes` is off in this app and would not
cover markdown anyway.

## Registering

Nothing to register. `allPosts()` and `allLibraryEntries()` read the
directory, and the sitemap, `/llms.txt` and `/llms-full.txt` map over the
same functions. Add the file and it appears.

## Before it ships

```bash
grep -c "—" apps/web/content/blog/<slug>.md        # must be 0
grep -rniE "normaliz|customiz|behavior|centered" apps/web/content/blog/<slug>.md
pnpm --filter @notch/web build                      # frontmatter throws here
pnpm format
```

Then load the page and check every internal link is a real route, the FAQ
renders once, and the `FAQPage` block carries the same questions.
