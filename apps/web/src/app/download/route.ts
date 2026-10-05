import { after, NextResponse, type NextRequest } from "next/server";
import { userAgent } from "next/server";

/**
 * Redirects to the current disk image.
 *
 * Reads the same `latest.json` the app's updater does, so the download button
 * and the in-app update can never disagree about what the current version is.
 */
const MIRROR_URL = process.env.NEXT_PUBLIC_ASSETS_URL ?? "https://assets.notchmetrics.com";

interface Latest {
  version: string;
  url: string;
  filename: string;
}

async function fromMirror(): Promise<Latest | null> {
  try {
    const response = await fetch(`${MIRROR_URL}/desktop/latest.json`, {
      // Matches the object's own max-age, so the page cache and the CDN agree.
      next: { revalidate: 60 },
    });
    if (!response.ok) return null;

    const body = (await response.json()) as Latest;

    // The manifest names the file to send the visitor to, and this handler
    // turns that into a redirect. A manifest pointing anywhere other than our
    // own bucket is a manifest to ignore — without this check, anybody who
    // could write latest.json could redirect every download somewhere else.
    if (typeof body.url !== "string" || !body.url.startsWith(`${MIRROR_URL}/`)) return null;

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

  const latest = await fromMirror();

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
