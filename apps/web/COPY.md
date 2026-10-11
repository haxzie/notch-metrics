# The words on notchmetrics.com

This is the rulebook for every string a visitor can read: the landing page,
`/sources`, the blog, the content library, meta descriptions, OG titles,
button labels, FAQ answers and `aria-label`s.

## The trap this file exists to stop

This repository's code comments are long, discursive and full of em dashes,
and `AGENTS.md` rewards that on purpose. **That voice is wrong for the site
and it leaks constantly**, because the file you are editing is nine parts
comment to one part string.

The two registers are not compatible. A maintainer reads a comment because
they are already committed. A visitor decides in about five seconds whether
to download a menu bar app they have never heard of. Copy written in the
comment voice reads as someone explaining the product to themselves.

## The rules

- **No em dashes anywhere a visitor can read.** Comma, colon, brackets, or
  two sentences. `aria-label` counts, because it is read aloud. En dashes in
  numeric ranges (`$14–$79`) are fine.
- **British spelling.** Colour, normalised, behaviour, centred, organisation.
- **Notch Metrics is the subject and does the verb.** "Notch Metrics reports
  your MRR", not "your MRR is reported". No `we` in product copy; `we` is
  allowed in blog prose and on the about page.
- **Second person for everything the reader owns.** Your MRR, your keys, your
  Mac, your notch. Notch Metrics owns the labour.
- **Short sentences.** Under fifteen words is the norm. A subordinate clause
  hanging off a subordinate clause is two sentences.
- **No hedging.** Not "helps you", not "designed to", not "can". It either
  does it or it is not on the page.
- **Never define the thing by what it is not.** No "not a dashboard, but a
  notch", and none of its cousins: "X rather than Y", "X instead of Y". A
  factual contrast inside a sentence is allowed where the contrast is the
  fact ("a snapshot, not a sum over the window"); the rhetorical version is
  not.
- **Concrete nouns.** Notch, tile, widget, sparkline, Keychain, camera
  housing. Never workflow, experience, solution, platform, engine.
- **No superlatives, no buzzwords, no claim with nothing in it.** If a
  heading would survive being moved to a different product's page, it is not
  about this one.
- **Card titles are outcomes, bodies are mechanisms.** Sentence case, no full
  stop. "Opens on hover", not "Hover support".
- **Section headers are spoken English.** "Questions", not "Frequently asked
  questions".
- **Value is work not done.** Nothing to open, no tab, no dock icon, already
  there when you look up.
- **No pain agitation.** Never open by telling the reader their habits are
  bad. Where a problem is named it is mechanical and blameless: "a browser
  tab is a decision every time", not "you waste hours refreshing Stripe".
- **Repetition across pages is fine.** Do not reword a line to avoid saying
  it twice. Rewriting is how two pages end up making different promises.
- **No exclamation marks, no emoji, one adjective per noun at most.**

## What never goes on a marketing page

- **Anything the product does not do.** Check the manifests in
  `packages/integrations` before claiming a connector or a metric exists.
- **A Notch Metrics shortcoming.** No "the catch", no conceding a feature to
  a rival, no hedging about maturity.
- **A competitor's outbound link.** Reddit is the one permitted outbound host
  for citations. Everything else gets named without a link.
- **Numbers we cannot stand behind.** No "thousands of founders". Real specs
  are exact because they are checkable.
- **A promise about rankings, clicks, indexing or AI citations.**

## The honest exceptions, which stay

These are not self-criticism, they are the product's actual security story,
and removing them costs more trust than it buys.

- **Apple silicon, macOS 14 or later.** A requirement, stated plainly, never
  as an apology. Somebody who buys software that will not run leaves a refund
  request and a one-star review.
- **Keys never reach the Mac.** Say it, because it is the differentiator.
- **Custom metrics are contained, not sandboxed.** Required wording, and
  `AGENTS.md` says so too. Implying a sandbox is the one false sentence that
  somebody would act on.
- **`beta` connectors are labelled beta.** Eight of the fourteen are, and
  `/sources` says which.

## Facts, in one place each

| What                                     | Where it lives                                         |
| ---------------------------------------- | ------------------------------------------------------ |
| Prices, plans, the trial                 | `PLANS` in `packages/schemas`                          |
| The connector list, metrics, methodology | the manifests in `packages/integrations`               |
| Origin, site name, LLM alternates        | `apps/web/src/lib/site.ts`                             |
| When a legal page last changed           | `apps/web/src/lib/legal.ts`                            |
| Blog and library prose, with FAQs        | `apps/web/content/`                                    |
| Hand-written copy for a `/sources` page  | `apps/web/content/sources/`, `content/source-metrics/` |

Anything said on more than one page belongs in a constant. Anything said once
belongs with the section that says it, because a constant used once is just
indirection.

## Before it ships

```bash
# Must be empty.
grep -rn "—" apps/web/src apps/web/content --include="*.tsx" --include="*.ts" --include="*.md" \
  | grep -vE ":[0-9]+: *(\*|//|/\*)"

# American spellings. Must be empty.
grep -rniE "normaliz|customiz|behavior|centered|optimiz|organiz" apps/web/content apps/web/src/lib

# Outbound hosts in content. API endpoints in code blocks are fine; a
# competitor's marketing site is not.
grep -ohE "https?://[a-zA-Z0-9./_-]+" apps/web/content/**/*.md \
  | sed -E 's|(https?://[^/]+).*|\1|' | sort -u

pnpm --filter @notch/web typecheck
pnpm --filter @notch/web build    # frontmatter is Zod-validated and throws here
```

Read the section out loud before calling it done. If you run out of breath
inside one sentence, it is two sentences.
