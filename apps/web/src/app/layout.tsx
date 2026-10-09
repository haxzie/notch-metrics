import type { Metadata } from "next";
import { ReactGrab } from "@/components/ReactGrab";
import "./globals.css";

export const metadata: Metadata = {
  metadataBase: new URL(process.env.NEXT_PUBLIC_APP_URL ?? "https://notchmetrics.com"),
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
