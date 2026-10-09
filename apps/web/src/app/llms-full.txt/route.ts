import { llmsFull } from "@/lib/llms";

// Built from `content/blog`, read with `node:fs` — see src/lib/blog.ts.
export const dynamic = "force-static";

export function GET(): Response {
  return new Response(llmsFull(), {
    headers: {
      "content-type": "text/plain; charset=utf-8",
      "cache-control": "public, max-age=3600, s-maxage=86400",
    },
  });
}
