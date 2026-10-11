/**
 * One `<script type="application/ld+json">`.
 *
 * Every graph on this site is assembled from our own strings and from the
 * manifests in `packages/integrations`, never from user input, so the
 * `dangerouslySetInnerHTML` here is the serialiser it looks like and not a
 * sink. Centralised so that stays true in one place rather than nine.
 */
export function JsonLd({ data }: { data: Record<string, unknown> | Record<string, unknown>[] }) {
  return (
    <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(data) }} />
  );
}
