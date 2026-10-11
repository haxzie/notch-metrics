import { notFound } from "next/navigation";
import { allPosts, postBySlug } from "@/lib/blog";
import { OG_CONTENT_TYPE, OG_SIZE, ogCard } from "@/lib/og";

export const alt = "Notch Metrics";
export const size = OG_SIZE;
export const contentType = OG_CONTENT_TYPE;

// Drawn at build, not on the Worker — see the note in src/lib/og.tsx.
export const dynamic = "force-static";
export const dynamicParams = false;

export function generateStaticParams(): { slug: string }[] {
  return allPosts().map((post) => ({ slug: post.slug }));
}

export default async function Image({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const post = postBySlug(slug);
  if (!post) notFound();

  return ogCard({
    kicker: post.tags[0] ?? "Blog",
    title: post.title,
    footnote: `${post.readingMinutes} min read`,
  });
}
