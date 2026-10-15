import { after, NextResponse, type NextRequest } from "next/server";
import { userAgent } from "next/server";

/**
 * Redirects to the current disk image.
 *
 * Reads the manifest from the Worker's update feed — the same feed the app's
 * updater polls — rather than from the bucket, so the download button and the
 * in-app update can never disagree about what the current version is. That
 * matters most when they are *meant* to disagree with the bucket: setting
 * `PINNED_VERSION` on the Worker withholds a bad release, and reading
 * `latest.json` directly here would leave the front page cheerfully handing
 * out the build the app just stopped offering.
 */
const API_URL = process.env.NEXT_PUBLIC_API_URL ?? "https://api.notchmetrics.com";
const ASSETS_URL = process.env.NEXT_PUBLIC_ASSETS_URL ?? "https://assets.notchmetrics.com";

interface Latest {
  version: string;
  url: string;
  filename: string;
}

async function currentRelease(): Promise<Latest | null> {
  try {
    const response = await fetch(`${API_URL}/v1/updates/latest`, {
      // A minute, not the feed's own five.
      //
      // This number is how long the front page keeps handing out a release
      // that `PINNED_VERSION` has already withheld, and a rollback that
      // reaches the app instantly but not the download button for five
      // minutes is most of the way to not being a rollback. A minute matches
      // the TTL on the bucket's own latest.json, so the propagation is no
      // worse than it was before the button went through the Worker.
      next: { revalidate: 60 },
    });
    if (!response.ok) return null;

    const body = (await response.json()) as Latest;

    // The manifest names the file to send the visitor to, and this handler
    // turns that into a redirect. A manifest pointing anywhere other than our
    // own bucket is a manifest to ignore — without this check, anybody who
    // could write latest.json could redirect every download somewhere else.
    if (typeof body.url !== "string" || !body.url.startsWith(`${ASSETS_URL}/`)) return null;

    return body;
  } catch {
    return null;
  }
}

export async function GET(request: NextRequest) {
  // Crawlers should index the page, not be counted as downloads or sent a
  // 60 MB file.
  if (userAgent(request).isBot) {
    return NextResponse.json({ ok: true });
  }

  const latest = await currentRelease();

  if (!latest) {
    // Never a dead button. The manual page lists the versioned URLs directly.
    return NextResponse.redirect(new URL("/download/manual", request.url), 302);
  }

  after(() => {
    // Deferred so it never delays the redirect.
    console.log(`[download] ${latest.version}`);
  });

  // 302, not 301. A permanent redirect to a version-pinned file would be
  // cached by the browser forever and keep handing out an old build.
  return NextResponse.redirect(latest.url, 302);
}
