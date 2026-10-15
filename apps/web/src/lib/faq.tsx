/**
 * The FAQ shape, and the one component that renders it.
 *
 * Every page that has an FAQ passes a single array to both `<FaqSection>` and
 * `faqPageJsonLd()`. That is the whole point of this module: an answer edited
 * in the visible copy but not in the structured data, or the reverse, is
 * markup that disagrees with the page, and the mismatch is grounds for the
 * rich result being dropped. One array cannot drift from itself.
 *
 * Two rules decide whether these are worth writing at all, and neither is
 * about the markup:
 *
 * - **Answer the query, not the article.** These are questions someone types
 *   into a search box. A question only a reader of this page would think to
 *   ask is a question nobody searches.
 * - **Each answer stands alone.** They get lifted and shown with nothing
 *   around them, by search engines and by assistants. Repeat the subject,
 *   name the number again, and say what Notch Metrics does with it.
 */
export type FaqEntry = { question: string; answer: string };

export function FaqSection({
  entries,
  heading = "Questions",
  id = "questions",
}: {
  entries: FaqEntry[];
  heading?: string;
  id?: string;
}) {
  if (entries.length === 0) return null;

  return (
    <section className="border-ink/[0.06] mt-16 border-t pt-10">
      <h2 id={id} className="text-xl font-semibold tracking-tight">
        {heading}
      </h2>
      <dl className="mt-6 flex flex-col gap-6">
        {entries.map((entry) => (
          <div key={entry.question}>
            <dt className="text-ink/90 text-[15px] font-medium">{entry.question}</dt>
            <dd className="text-ink/55 mt-2 text-[15px] leading-relaxed">{entry.answer}</dd>
          </div>
        ))}
      </dl>
    </section>
  );
}
