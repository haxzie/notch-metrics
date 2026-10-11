import { notFound } from "next/navigation";
import { OG_CONTENT_TYPE, OG_SIZE, ogCard } from "@/lib/og";
import { sourceBySlug, sourcePages } from "@/lib/sources";

export const alt = "Notch Metrics";
export const size = OG_SIZE;
export const contentType = OG_CONTENT_TYPE;

export const dynamic = "force-static";
export const dynamicParams = false;

export function generateStaticParams(): { provider: string }[] {
  return sourcePages().map(({ manifest }) => ({ provider: manifest.id }));
}

export default async function Image({ params }: { params: Promise<{ provider: string }> }) {
  const { provider } = await params;
  const manifest = sourceBySlug(provider);
  if (!manifest) notFound();

  return ogCard({
    kicker: "Source",
    title: `${manifest.name} in the MacBook notch`,
    footnote: `${manifest.metrics.length} ${manifest.metrics.length === 1 ? "number" : "numbers"}`,
  });
}
