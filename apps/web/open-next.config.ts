import { defineCloudflareConfig } from "@opennextjs/cloudflare";
import staticAssetsIncrementalCache from "@opennextjs/cloudflare/overrides/incremental-cache/static-assets-incremental-cache";

/**
 * Serve prerendered pages from the Workers assets bundle.
 *
 * Without an `incrementalCache`, OpenNext has nowhere to read prerendered
 * output from at request time. Next writes a statically generated **dynamic**
 * route into `.open-next/cache`, not into `.open-next/assets`, and
 * `wrangler.jsonc` only uploads the latter. The Worker therefore falls back
 * to rendering on demand, and every one of those routes sets
 * `dynamicParams = false`, so the answer is a 404.
 *
 * That stayed invisible for as long as the site had no prerendered dynamic
 * route. `/sources/[provider]/[metric]`, `/blog/[slug]`, `/library/[slug]`
 * and `/free-tools/[slug]` are all of them, and they 404ed in production
 * while building perfectly in CI.
 *
 * The same gap quietly broke `sitemap.xml`. It is a `force-static` route
 * handler, so it was re-executed per request instead of served, and its
 * `node:fs` read of `content/` failed on the Worker. `readCollection` catches
 * a missing directory and returns an empty collection, by design, so the
 * sitemap shipped with every registry-driven URL and not one blog post.
 *
 * `staticAssetsIncrementalCache` is the right override here rather than the
 * R2 or KV ones: it is read-only and documented for applications that do not
 * revalidate and only serve prerendered data, which is this site exactly.
 * Every route is `force-static`; nothing here ever writes to the cache.
 *
 * If a route ever needs real ISR, this has to become `r2IncrementalCache`
 * with a bucket, because this one refuses writes.
 */
export default defineCloudflareConfig({
  incrementalCache: staticAssetsIncrementalCache,
});
