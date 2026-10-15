import { Hono } from "hono";
import { LatestJson } from "@notch/schemas";
import type { AppContext } from "../middleware.ts";
import { logError } from "../lib/redact.ts";

/**
 * The update feed the Mac app polls, and the download the website's buttons
 * point at.
 *
 * Both could read `desktop/latest.json` off R2 directly — and the app does, as
 * a fallback — but going through the Worker is what makes a bad release
 * recoverable in seconds: set `PINNED_VERSION` and deploy, and every client
 * stops being offered the broken build without touching the bucket or waiting
 * out a CDN TTL. Routing the website's button through here too means one
 * deploy pulls back the in-app update *and* the download, rather than leaving
 * the front page handing out the build the app just stopped offering.
 *
 * The ~18 MB disk image itself never passes through here. Only this ~400-byte
 * manifest does, and a redirect to the object on R2.
 */
export const updates = new Hono<AppContext>();

const KEY = "desktop/latest.json";

type Manifest = ReturnType<typeof LatestJson.parse>;

/** `null` is "nothing to offer"; the string is why, for the log. */
type Read = { manifest: Manifest } | { manifest: null; status: 404 | 502; message: string };

async function readManifest(c: { env: AppContext["Bindings"] }): Promise<Read> {
  try {
    const object = await c.env.ASSETS_BUCKET.get(KEY);
    if (!object) return { manifest: null, status: 404, message: "No release yet." };

    const parsed = LatestJson.safeParse(await object.json());
    if (!parsed.success) {
      // A malformed manifest must not be handed to an updater that will act on
      // it. Better no update than an update to an unverifiable artefact.
      logError("updates.manifest", parsed.error);
      return { manifest: null, status: 502, message: "The release manifest is unreadable." };
    }

    if (c.env.PINNED_VERSION && parsed.data.version !== c.env.PINNED_VERSION) {
      return { manifest: null, status: 404, message: "No update available." };
    }

    return { manifest: parsed.data };
  } catch (error) {
    logError("updates.manifest", error);
    return { manifest: null, status: 502, message: "Could not read the release manifest." };
  }
}

updates.get("/latest", async (c) => {
  const read = await readManifest(c);
  if (read.manifest === null) {
    return c.json(
      { code: read.status === 404 ? "NOT_FOUND" : "BAD_MANIFEST", message: read.message },
      read.status,
    );
  }
  return c.json(read.manifest, 200, { "cache-control": "public, max-age=300" });
});

/**
 * Sends a browser to the current disk image.
 *
 * A redirect rather than a proxy: streaming 18 MB through a Worker costs
 * duration on every download and loses R2's range requests, which is what lets
 * an interrupted download resume instead of starting over.
 *
 * `no-store`, and 302 rather than 301, because the target is version-pinned.
 * A cached redirect here would keep handing out an old build long after the
 * manifest moved on — a failure that looks exactly like the release never
 * happened.
 */
updates.get("/download", async (c) => {
  const read = await readManifest(c);
  if (read.manifest === null) {
    return c.json({ code: "NOT_FOUND", message: read.message }, read.status);
  }
  c.header("cache-control", "no-store");
  return c.redirect(read.manifest.url, 302);
});

updates.get("/notes", async (c) => {
  const version = c.req.query("version");
  if (!version || !/^\d+\.\d+\.\d+$/.test(version)) {
    return c.json({ version: null, notes: null });
  }
  // 200-with-nulls rather than an error. A "what's new" sheet that cannot load
  // its text should show nothing, not an error dialog over an update the user
  // already agreed to.
  //
  // The website, not the repository. The repository is private, so a GitHub
  // release URL is a sign-in wall for everyone who is not the author.
  return c.json({
    version,
    notes: `${c.env.APP_URL}/changelog#v${version.replace(/\./g, "-")}`,
  });
});
