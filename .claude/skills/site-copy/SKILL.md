---
name: site-copy
description: Write or edit the words on the marketing site, a landing page headline or lede, a feature card, an FAQ answer, a section heading, a button label, a meta description or an OG title. Use this whenever someone asks to reword, tighten, rewrite or add copy anywhere under apps/web, or says the site reads badly. Covers the voice, where every string lives, the claims that may not be made, and the checks before it ships.
---

# site-copy

The words on `apps/web`. Not blog posts or library pages, which are
`articles` and have their own shape.

**The canonical guide is `apps/web/COPY.md`. Read it before writing
anything.** This file is the operating procedure around it.

## Before writing

1. Read `apps/web/COPY.md`.
2. Read the section you are changing **and the two either side of it**. The
   landing page is one argument in several sections, and a heading that works
   alone often repeats the one above it.
3. Check any claim against the source, not against memory. Prices come from
   `PLANS` in `packages/schemas`; connectors, metrics and the wording of what
   a number means come from the manifests in `packages/integrations`.

## What is shared with what

- **`src/lib/faq.tsx`** holds `FaqEntry` and `<FaqSection>`. Every page
  passes **one array** to both `<FaqSection>` and `faqPageJsonLd()`. Never
  edit an answer in only one place, and never introduce a second array.
- **`src/lib/jsonld.ts`** holds every structured-data builder. Two rules are
  load-bearing: a breadcrumb hop must be a page that returns 200, and `item`
  URLs are absolute.
- **`src/components/marketing/primitives.tsx`** holds `Section`, `Pillar`,
  `Feature` and `SecurityCard`, shared by the landing page, `/sources` and
  `/library`. Editing one changes all three. That is the intent.
- **`src/lib/site.ts`** holds anything said on more than one page.
- **`/sources` copy is generated** from the manifests. To change what a
  metric page says, change the `methodology` string in
  `packages/integrations`, or add a sidecar in `apps/web/content/sources/`
  or `apps/web/content/source-metrics/`.

## The section shape

```
Eyebrow      One or two words, small caps. A category, not a claim.
Heading      One line. Two beats if it wants them, second beat shorter.
Lede         Two sentences. Three only if the third is short.
Cards        3 to 6. Outcome as the title, mechanism in one or two sentences.
```

Nothing on the landing page is a paragraph. A section that runs to four
sentences of lede is not a longer section, it is a section written in the
wrong register.

## The rules, in short

Full versions and the reasoning are in `apps/web/COPY.md`.

- No em dashes in anything a visitor reads. `aria-label` counts.
- British spelling.
- Notch Metrics is the subject and does the verb. No `we` in product copy.
- Second person for what the reader owns.
- Short sentences, no hedging, no superlatives.
- Never define the thing by what it is not.
- Concrete nouns: notch, tile, widget, sparkline, Keychain.
- Card titles are outcomes, bodies are mechanisms.

## Claims that may not be made

- **Never imply custom metrics are sandboxed.** They are _contained_: each
  declares the hosts it may reach and nothing else is reachable, and it still
  runs as the user. `AGENTS.md` requires this wording. It is the one false
  sentence somebody would act on.
- **Never claim a connector or a metric the manifests do not have.** Three
  providers are `coming_soon` and their adapters throw. Eight of the fourteen
  live ones are `beta`, and `/sources` says so.
- **No Notch Metrics shortcoming on a marketing page**, with the honest
  exceptions that stay: the macOS requirement, keys never reaching the Mac,
  containment, and the beta labels.
- **Never promise rankings, clicks, indexing or AI citations.**

## Before it ships

```bash
grep -rn "—" apps/web/src apps/web/content --include="*.tsx" --include="*.ts" --include="*.md" \
  | grep -vE ":[0-9]+: *(\*|//|/\*)"
grep -rniE "normaliz|customiz|behavior|centered" apps/web/content apps/web/src/lib
pnpm --filter @notch/web typecheck
pnpm format
```

Do not run a full build to see a copy change. Read the section out loud: if
you run out of breath inside one sentence, it is two sentences.
