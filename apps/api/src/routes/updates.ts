import { Hono } from "hono";
import { LatestJson } from "@notch/schemas";
import type { AppContext } from "../middleware.ts";
import { logError } from "../lib/redact.ts";

/**
 * The update feed the Mac app polls.
 *
 * The app could read `desktop/latest.json` off R2 directly — and does, as a
 * fallback — but going through the Worker is what makes a bad release
 * recoverable in seconds: set `PINNED_VERSION` and deploy, and every client
 * stops being offered the broken build without touching the bucket or waiting
 * out a CDN TTL.
 *
 * The ~18 MB disk image itself never passes through here. Only this ~400-byte
 * manifest does.
 */
export const updates = new Hono<AppContext>();

const KEY = "desktop/latest.json";

updates.get("/latest", async (c) => {
  try {
    const object = await c.env.ASSETS_BUCKET.get(KEY);
    if (!object) return c.json({ code: "NOT_FOUND", message: "No release yet." }, 404);

    const parsed = LatestJson.safeParse(await object.json());
    if (!parsed.success) {
      // A malformed manifest must not be handed to an updater that will act on
      // it. Better no update than an update to an unverifiable artefact.
      logError("updates.latest", parsed.error);
      return c.json({ code: "BAD_MANIFEST", message: "The release manifest is unreadable." }, 502);
    }

    if (c.env.PINNED_VERSION && parsed.data.version !== c.env.PINNED_VERSION) {
      return c.json({ code: "NOT_FOUND", message: "No update available." }, 404);
    }

    return c.json(parsed.data, 200, { "cache-control": "public, max-age=300" });
  } catch (error) {
    logError("updates.latest", error);
    return c.json({ code: "ERROR", message: "Could not read the release manifest." }, 502);
  }
});

updates.get("/notes", async (c) => {
  const version = c.req.query("version");
  if (!version || !/^\d+\.\d+\.\d+$/.test(version)) {
    return c.json({ version: null, notes: null });
  }
  // 200-with-nulls rather than an error. A "what's new" sheet that cannot load
  // its text should show nothing, not an error dialog over an update the user
  // already agreed to.
  return c.json({
    version,
    notes: `https://github.com/${c.env.GITHUB_REPO}/releases/tag/mac-v${version}`,
  });
});
