import { GoogleAnalytics } from "@next/third-parties/google";
import type { Metadata } from "next";
import { ReactGrab } from "@/components/ReactGrab";
import { OG_IMAGE, OG_SIZE } from "@/lib/og";
import { SITE_NAME, SITE_URL } from "@/lib/site";
import "./globals.css";

/**
 * Site-wide defaults. Every field here is inherited by routes that do not
 * override it — which is why there is deliberately no `alternates.canonical`:
 * inherited, it would have every page claiming to be the home page.
 */
export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  applicationName: SITE_NAME,
  title: {
    default: "Notch Metrics: put your metrics in the notch",
    template: "%s · Notch Metrics",
  },
  description:
    "Notch Metrics puts your revenue, MRR and subscribers in your MacBook notch. Look up, and the number is already there.",
  openGraph: {
    siteName: "Notch Metrics",
    title: "Notch Metrics: put your metrics in the notch",
    description: "Put your metrics in the notch. Look up, and the number is already there.",
    type: "website",
    // Inherited by every route that does not set its own `openGraph`. One
    // that does replaces this block whole, which is what `ogDefaults` in
    // `src/lib/og.tsx` exists to put back.
    images: [{ url: OG_IMAGE, width: OG_SIZE.width, height: OG_SIZE.height }],
  },
  twitter: { card: "summary_large_image" },
  icons: { icon: "/logo.svg", apple: "/brand/app-icon.png" },
  robots: {
    index: true,
    follow: true,
    // Lets Google show a full-length text snippet and a large image rather
    // than the truncated default. Individual routes still override this —
    // a draft post sets `index: false`.
    googleBot: { index: true, follow: true, "max-snippet": -1, "max-image-preview": "large" },
  },
};

/**
 * Google Analytics, alongside PostHog rather than instead of it. The two
 * answer different questions: GA is the acquisition picture that Search
 * Console and Ads already speak, PostHog is what somebody did once they
 * arrived and who they turned out to be.
 *
 * Unset is no tag at all, which is what a preview build and a local run
 * should get. A measurement id is public, so this is a variable in
 * `deploy-web.yml` and not a secret.
 */
const GA_ID = process.env.NEXT_PUBLIC_GA_ID;

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body className="min-h-screen antialiased">
        {children}
        <ReactGrab />
        {/* `@next/third-parties` rather than a hand-written `<Script>`: it
            loads gtag after hydration and handles App Router navigation, so
            this stays a server component and the pages stay static. */}
        {GA_ID && <GoogleAnalytics gaId={GA_ID} />}
      </body>
    </html>
  );
}
