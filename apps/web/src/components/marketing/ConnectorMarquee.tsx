import Link from "next/link";
import { catalogue } from "@notch/integrations";
import { ConnectorMark } from "@/components/ConnectorMark";

/**
 * Every source as a drifting pill, in three rows.
 *
 * A static wall of sixteen marks made the reader count them. Moving rows
 * read as "more than fits", which is the claim, and naming each one means a
 * visitor looking for Paddle finds the word rather than having to recognise
 * a logo.
 *
 * Each row renders its connectors twice and travels exactly half its own
 * width, so the second copy is under the cursor at the moment the first one
 * ends and the loop has no seam.
 */
export function ConnectorMarquee() {
  const all = catalogue().flatMap((group) => group.connectors);
  const live = all.filter((connector) => connector.status !== "coming_soon");
  const rows = [0, 1, 2].map((row) => all.filter((_, index) => index % 3 === row));

  return (
    <div className="flex flex-col items-center gap-6">
      <div
        className="w-full overflow-hidden"
        style={{
          // Both edges dissolve, so a pill leaves without being cut off.
          maskImage: "linear-gradient(to right, transparent, #000 7%, #000 93%, transparent)",
          WebkitMaskImage: "linear-gradient(to right, transparent, #000 7%, #000 93%, transparent)",
        }}
      >
        <div className="flex flex-col gap-3">
          {rows.map((connectors, index) => (
            <div
              key={index}
              className="marquee-track flex w-max gap-3"
              style={{
                animationDuration: `${52 + index * 9}s`,
                // The middle row runs the other way. Three rows all going
                // left read as one block sliding; alternating reads as a
                // surface with things on it.
                animationDirection: index === 1 ? "reverse" : "normal",
              }}
            >
              {[...connectors, ...connectors].map((connector, copy) => (
                <span
                  key={`${connector.id}-${copy}`}
                  className={`border-ink/[0.06] flex shrink-0 items-center gap-2.5 rounded-full border bg-white py-2 pl-2 pr-5 shadow-[0_6px_18px_-10px_rgba(11,10,14,0.35)] ${
                    connector.status === "coming_soon" ? "opacity-45" : ""
                  }`}
                >
                  <ConnectorMark
                    id={connector.id}
                    name={connector.name}
                    accentColor={connector.accentColor}
                    size={32}
                    shape="squircle"
                  />
                  <span className="whitespace-nowrap text-[15px] font-medium">
                    {connector.name}
                  </span>
                </span>
              ))}
            </div>
          ))}
        </div>
      </div>

      <p className="text-ink/35 text-xs">
        {live.length} live today. Dimmed marks are on the way, and arrive without an app update.
      </p>
      <Link
        href="/sources"
        className="text-ink/50 hover:text-ink text-[13px] underline-offset-4 transition hover:underline"
      >
        Every source and the numbers it reports
      </Link>
    </div>
  );
}
