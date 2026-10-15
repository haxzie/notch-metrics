import { readFileSync } from "node:fs";
import { join } from "node:path";
import { renderMarkdown } from "./collection.ts";

/**
 * The Mac app's released versions, from `apps/mac/CHANGELOG.md`.
 *
 * Read from the app's own changelog rather than from a copy under
 * `content/`, because changesets regenerates that file on every release and a
 * copy is a thing somebody has to remember to sync. The repository is private,
 * so this page is the only place a release note can be read: the manifest's
 * `notes` URL points here, and the app's Updates pane links to it.
 *
 * `node:fs` does not exist on the Worker this site deploys to, so the route
 * that calls this is `force-static` and the read happens during `next build`.
 */
export interface Release {
  version: string;
  /** `v0-3-0`, so `/changelog#v0-3-0` lands on it. */
  id: string;
  html: string;
}

/**
 * Changesets' GitHub changelog writes every entry as a commit link and a
 * thank-you, both pointing at a repository nobody outside can open. Stripped
 * here rather than by switching the generator, so the existing file and every
 * future one read the same way.
 */
function withoutGitHub(markdown: string): string {
  return markdown
    .replace(/^- \[`[^`]+`\]\([^)]*\)\s*Thanks \[@[^\]]+\]\([^)]*\)!\s*-\s*/gm, "- ")
    .replace(/^- \[`[^`]+`\]\([^)]*\)\s*-\s*/gm, "- ")
    .replace(/^\s*Updated dependencies \[[^\]]*\]:?\s*$/gm, "");
}

export function readChangelog(): Release[] {
  let text: string;
  try {
    text = readFileSync(join(process.cwd(), "..", "mac", "CHANGELOG.md"), "utf8");
  } catch {
    // No changelog before the first release, and an empty page is better than
    // a build that fails on a file that does not exist yet.
    return [];
  }

  const releases: Release[] = [];
  const lines = text.split("\n");
  let version: string | null = null;
  let body: string[] = [];

  const flush = () => {
    if (!version) return;
    const markdown = withoutGitHub(body.join("\n")).trim();
    if (markdown) {
      releases.push({
        version,
        id: `v${version.replace(/\./g, "-")}`,
        html: renderMarkdown(markdown).html,
      });
    }
  };

  for (const line of lines) {
    const heading = /^## (.+)$/.exec(line);
    if (heading) {
      flush();
      version = heading[1]!.trim();
      body = [];
      continue;
    }
    if (version) body.push(line);
  }
  flush();

  return releases;
}
