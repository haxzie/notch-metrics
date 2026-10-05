import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Notch Metrics — your business, in the notch",
  description:
    "Revenue, MRR and subscribers from Stripe, Dodo Payments and Lemon Squeezy, in the MacBook notch. Hover to see them.",
  openGraph: {
    title: "Notch Metrics",
    description: "Your business metrics, in the MacBook notch.",
    type: "website",
  },
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body className="min-h-screen antialiased">{children}</body>
    </html>
  );
}
