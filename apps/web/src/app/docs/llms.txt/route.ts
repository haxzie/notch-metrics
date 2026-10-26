import { docsBundle } from "@/lib/docs-llms";

// Built from `content/docs` plus `contracts/` and `packages/core`, all read
// with `node:fs` at build time. The Worker this deploys to has no `node:fs`,
// so this must stay static.
export const dynamic = "force-static";

export function GET(): Response {
  return new Response(docsBundle(), {
    headers: {
      "content-type": "text/plain; charset=utf-8",
      "cache-control": "public, max-age=3600, s-maxage=86400",
    },
  });
}
