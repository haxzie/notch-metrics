import { notFound } from "next/navigation";
import { OG_CONTENT_TYPE, OG_SIZE, ogCard } from "@/lib/og";
import { CATEGORY_LABELS, allTools, toolBySlug } from "@/lib/tools";

export const alt = "Notch Metrics";
export const size = OG_SIZE;
export const contentType = OG_CONTENT_TYPE;

export const dynamic = "force-static";
export const dynamicParams = false;

export function generateStaticParams(): { slug: string }[] {
  return allTools().map((tool) => ({ slug: tool.slug }));
}

export default async function Image({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const tool = toolBySlug(slug);
  if (!tool) notFound();

  return ogCard({
    kicker: CATEGORY_LABELS[tool.category],
    title: tool.heading,
    footnote: "Free, no signup",
  });
}
