import { notFound } from "next/navigation";
import { KIND_LABELS, allLibraryEntries, libraryEntryBySlug } from "@/lib/library";
import { OG_CONTENT_TYPE, OG_SIZE, ogCard } from "@/lib/og";

export const alt = "Notch Metrics";
export const size = OG_SIZE;
export const contentType = OG_CONTENT_TYPE;

export const dynamic = "force-static";
export const dynamicParams = false;

export function generateStaticParams(): { slug: string }[] {
  return allLibraryEntries().map((entry) => ({ slug: entry.slug }));
}

export default async function Image({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const entry = libraryEntryBySlug(slug);
  if (!entry) notFound();

  return ogCard({
    kicker: KIND_LABELS[entry.kind],
    title: entry.title,
    footnote: `${entry.readingMinutes} min read`,
  });
}
