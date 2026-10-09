import { llmsIndex } from "@/lib/llms";

// Built from `content/blog`, read with `node:fs` — see src/lib/blog.ts.
export const dynamic = "force-static";

export function GET(): Response {
  return new Response(llmsIndex(), {
    headers: {
      // text/plain, not text/markdown: every client renders it, and the
      // convention is a file you can read in a browser tab.
      "content-type": "text/plain; charset=utf-8",
      "cache-control": "public, max-age=3600, s-maxage=86400",
    },
  });
}
