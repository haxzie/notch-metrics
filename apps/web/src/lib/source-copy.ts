import { existsSync, readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import matter from "gray-matter";
import { z } from "zod";
import { renderMarkdown } from "@/lib/collection";
import type { FaqEntry } from "@/lib/faq";

/**
 * Optional hand-written copy for a `/sources` page.
 *
 * The `/sources` tree is generated from the provider manifests and renders in
 * full with no file here. A sidecar deepens one page: a paragraph of prose
 * above the generated blocks, and an FAQ that replaces the generated one.
 *
 * Optional on purpose, and this is the whole design. The requirement is that
 * a metric added to a manifest becomes a live page with no edit in this app.
 * A required sidecar would make every new metric a build failure, which is
 * the opposite. `pnpm seo:thin` is how you find the pages that want one.
 *
 * Flat directories, with the metric's provider in the filename
 * (`content/source-metrics/stripe-mrr.md`), so the same `readdirSync` serves
 * both and there is no nested walk to get wrong.
 *
 * `node:fs`, so build time only. See the note in `src/lib/collection.ts`.
 */
const Sidecar = z.object({
  /** Replaces the generated lede under the title. */
  lede: z.string().min(1).optional(),
  /** Replaces the generated FAQ entirely. Not merged: a partial override
   *  would leave a generated answer sitting under a hand-written one and
   *  nobody would notice which was which. */
  faq: z
    .array(z.object({ question: z.string().min(1), answer: z.string().min(1) }))
    .min(1)
    .optional(),
});

export type SourceCopy = {
  lede?: string;
  faq?: FaqEntry[];
  /** The rendered markdown body, if the file had one. */
  html?: string;
  markdown?: string;
};

function read(dir: string, slug: string): SourceCopy | undefined {
  const file = join(process.cwd(), "content", dir, `${slug}.md`);
  if (!existsSync(file)) return undefined;

  const { data, content } = matter(readFileSync(file, "utf8"));
  const parsed = Sidecar.safeParse(data);
  if (!parsed.success) {
    const issues = parsed.error.issues.map(
      (issue) => `  ${issue.path.join(".") || "(root)"}: ${issue.message}`,
    );
    // Thrown rather than ignored. A sidecar that silently stops applying is
    // a page that quietly reverts to the generated copy, which is exactly
    // the kind of regression nobody reads the diff for.
    throw new Error(`content/${dir}/${slug}.md has invalid frontmatter:\n${issues.join("\n")}`);
  }

  const body = content.trim();
  return {
    ...parsed.data,
    ...(body ? { markdown: body, html: renderMarkdown(body).html } : {}),
  };
}

export function sourceCopy(providerId: string): SourceCopy | undefined {
  return read("sources", providerId);
}

export function metricCopy(providerId: string, metricSlug: string): SourceCopy | undefined {
  return read("source-metrics", `${providerId}-${metricSlug}`);
}

/** Which sidecars exist, for the thin-content report. */
export function sidecarSlugs(dir: "sources" | "source-metrics"): Set<string> {
  try {
    return new Set(
      readdirSync(join(process.cwd(), "content", dir))
        .filter((file) => file.endsWith(".md"))
        .map((file) => file.replace(/\.md$/, "")),
    );
  } catch {
    return new Set();
  }
}
