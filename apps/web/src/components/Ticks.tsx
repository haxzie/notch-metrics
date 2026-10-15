import { Fragment } from "react";

/**
 * Renders the backticked spans in a manifest string as inline code.
 *
 * The `methodology` and `help` strings in `packages/integrations` were
 * written for a tooltip in the Mac app and use markdown backticks around
 * field names: `recurring_pre_tax_amount`, `$pageview`, `screenPageViews`.
 * Those are useful and exact, and surfacing them raw on a web page prints
 * the backticks.
 *
 * Deliberately not a markdown parser. These strings are prose with field
 * names in them, so a parser would also start interpreting an underscore in
 * `active_subscribers` as emphasis, which is precisely the failure this
 * avoids.
 */
export function Ticks({ children }: { children: string }) {
  const parts = children.split("`");

  return (
    <>
      {parts.map((part, index) =>
        // Odd indices sit between a pair of backticks. An unmatched trailing
        // backtick leaves its text in an even slot, so it renders as prose
        // rather than swallowing the rest of the sentence.
        index % 2 === 1 ? (
          <code
            key={index}
            className="bg-ink/[0.06] text-ink/80 rounded px-1 py-0.5 font-mono text-[0.9em]"
          >
            {part}
          </code>
        ) : (
          <Fragment key={index}>{part}</Fragment>
        ),
      )}
    </>
  );
}
