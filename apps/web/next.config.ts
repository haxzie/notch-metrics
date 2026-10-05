import type { NextConfig } from "next";

const config: NextConfig = {
  reactStrictMode: true,
  // Deployed to Cloudflare Workers through OpenNext rather than Pages: Pages
  // cannot run this version of Next, and @cloudflare/next-on-pages only
  // supports the edge runtime — which the /download route handler is not.
  images: { unoptimized: true },
};

export default config;
