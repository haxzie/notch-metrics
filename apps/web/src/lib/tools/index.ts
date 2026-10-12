import { SAAS_TOOLS } from "./saas.ts";
import { OTHER_TOOLS } from "./commerce.ts";
import { CATEGORY_LABELS, CATEGORY_ORDER, type Tool, type ToolCategory } from "./types.ts";

export * from "./types.ts";

/**
 * Every free tool, in one list.
 *
 * Split across files by category only so no single file is unreadable; the
 * pages read this. A tool added here becomes a live page, a sitemap entry and
 * an `llms.txt` line with no edit anywhere else, the same way `/sources`
 * works off the provider manifests.
 */
export const TOOLS: Tool[] = validate([...SAAS_TOOLS, ...OTHER_TOOLS]);

/**
 * Checked at module load, which means at `next build`.
 *
 * Thrown rather than warned, for the same reason the blog throws on bad
 * frontmatter: a tool that quietly ships with a 200-character description or
 * no headline figure is a page nobody notices is broken until it is indexed.
 */
function validate(tools: Tool[]): Tool[] {
  const seen = new Set<string>();

  for (const tool of tools) {
    const fail = (why: string) => {
      throw new Error(`Free tool "${tool.slug}" ${why}`);
    };

    if (seen.has(tool.slug)) fail("has a duplicate slug");
    seen.add(tool.slug);

    // 160 is roughly where Google stops rendering a description. Longer is
    // not an error anywhere downstream, which is exactly why the build has
    // to be the thing that catches it.
    if (tool.description.length > 160) {
      fail(`has a ${tool.description.length} character description, max 160`);
    }
    if (tool.faq.length < 3) fail("needs at least three FAQ entries");
    if (tool.fields.length === 0) fail("has no input fields");
    if (tool.outputs.filter((output) => output.primary).length !== 1) {
      fail("must mark exactly one output as primary");
    }

    const keys = new Set(tool.outputs.map((output) => output.key));
    const computed = tool.compute(() => 1);
    for (const key of Object.keys(computed)) {
      if (!keys.has(key)) fail(`computes "${key}", which no output declares`);
    }
    for (const key of keys) {
      if (!(key in computed)) fail(`declares output "${key}", which compute never returns`);
    }
  }

  return tools;
}

export function allTools(): Tool[] {
  return TOOLS;
}

export function toolBySlug(slug: string): Tool | undefined {
  return TOOLS.find((tool) => tool.slug === slug);
}

export function toolGroups(): { category: ToolCategory; label: string; tools: Tool[] }[] {
  return CATEGORY_ORDER.map((category) => ({
    category,
    label: CATEGORY_LABELS[category],
    tools: TOOLS.filter((tool) => tool.category === category),
  })).filter((group) => group.tools.length > 0);
}
