import { notFound } from "next/navigation";
import { OG_CONTENT_TYPE, OG_SIZE, ogCard } from "@/lib/og";
import { metricBySlug, metricPages, metricSlug } from "@/lib/sources";

export const alt = "Notch Metrics";
export const size = OG_SIZE;
export const contentType = OG_CONTENT_TYPE;

export const dynamic = "force-static";
export const dynamicParams = false;

export function generateStaticParams(): { provider: string; metric: string }[] {
  return metricPages().map(({ manifest, metric }) => ({
    provider: manifest.id,
    metric: metricSlug(metric.id),
  }));
}

export default async function Image({
  params,
}: {
  params: Promise<{ provider: string; metric: string }>;
}) {
  const { provider, metric } = await params;
  const page = metricBySlug(provider, metric);
  if (!page) notFound();

  return ogCard({
    kicker: page.manifest.name,
    title: `${page.metric.label} in the MacBook notch`,
    footnote: page.metric.supportsSeries ? "Figure and sparkline" : "Live figure",
  });
}
