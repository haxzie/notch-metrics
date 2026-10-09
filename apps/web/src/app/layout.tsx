import type { Metadata } from "next";
import { ReactGrab } from "@/components/ReactGrab";
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
    default: "Notch Metrics — the dashboard you never have to open",
    template: "%s · Notch Metrics",
  },
  description:
    "Revenue, MRR and subscribers from Stripe, Polar, Paddle, Dodo Payments and more, in the MacBook notch. Hover to see them; move away and it is gone.",
  openGraph: {
    siteName: "Notch Metrics",
    title: "Notch Metrics — the dashboard you never have to open",
    description: "Your business metrics, in the MacBook notch.",
    type: "website",
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
