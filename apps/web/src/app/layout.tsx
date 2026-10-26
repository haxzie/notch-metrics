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

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body className="min-h-screen antialiased">
        {children}
        <ReactGrab />
      </body>
    </html>
  );
}
