import { readFileSync } from "node:fs";
import { join } from "node:path";
import type { NextConfig } from "next";

/**
 * Loads the monorepo's root `.env`.
 *
 * The root scripts run Next through `dotenv -e .env -- turbo`, so a plain
 * `pnpm next dev` from this directory sees none of it — and because
 * `NEXT_PUBLIC_API_URL` has a production fallback at every use site, the
 * failure is not a missing variable but a dev build quietly pointing at
 * api.notchmetrics.com. Every request then fails at the network layer, which
 * reads as "the API is down" rather than "the config did not load".
 *
 * Values already in the environment win, so CI and an explicit
 * `NEXT_PUBLIC_API_URL=… next dev` still override the file.
 */
function loadRootEnv(): void {
  let text: string;
  try {
    text = readFileSync(join(process.cwd(), "..", "..", ".env"), "utf8");
  } catch {
    // Absent in CI and in a deployed build, where the values arrive as real
    // environment variables. Not an error.
    return;
  }

  for (const line of text.split("\n")) {
    const match = /^\s*([A-Z][A-Z0-9_]*)\s*=\s*(.*?)\s*$/.exec(line);
    if (!match) continue;
    const [, key, raw] = match;
    if (key === undefined || raw === undefined) continue;
    if (process.env[key] !== undefined) continue;
    process.env[key] = raw.replace(/^["']|["']$/g, "");
  }
}

loadRootEnv();

const config: NextConfig = {
  reactStrictMode: true,
  // Deployed to Cloudflare Workers through OpenNext rather than Pages: Pages
  // cannot run this version of Next, and @cloudflare/next-on-pages only
  // supports the edge runtime — which the /download route handler is not.
  images: { unoptimized: true },
};

export default config;
