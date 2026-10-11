import { catalogue } from "@notch/integrations";
import Link from "next/link";
import { ConnectorMark } from "@/components/ConnectorMark";

/**
 * Every connector as a mark, live ones first. The name is the tooltip, not
 * a label: at this size the marks are recognisable on their own, and a wall
 * of them says "lots" faster than a list does. Ones not shipped yet are
 * dimmed rather than hidden, so a visitor can see Mixpanel is on the way
 * without being told it works today.
 *
 * "Live" is anything not `coming_soon`, which includes `beta`. A beta
 * connector is one the server will happily connect, so dimming it told
 * visitors the opposite of the truth.
 *
 * Read from the manifests rather than from a copy of them. The copy this
 * replaced drifted inside one release, and it now has ninety-odd generated
 * `/sources` pages to disagree with.
 */
export function ConnectorGrid() {
  const all = catalogue().flatMap((group) => group.connectors);
  const live = all.filter((connector) => connector.status !== "coming_soon");
  const soon = all.filter((connector) => connector.status === "coming_soon");

  return (
    <div className="flex flex-col items-center gap-6">
      <ul className="flex max-w-3xl flex-wrap justify-center gap-3 sm:gap-4">
        {[...live, ...soon].map((connector) => {
          const mark = (
            <ConnectorMark
              id={connector.id}
              name={connector.name}
              accentColor={connector.accentColor}
              size={72}
              shape="squircle"
            />
          );

          return (
            <li
              key={connector.id}
              className={`transition hover:scale-105 ${
                connector.status === "coming_soon" ? "opacity-40 grayscale-[0.3]" : ""
              }`}
            >
              {/* A connector with no page yet is not a link. Only the live
                  ones have one, which is the same rule `/sources` uses. */}
              {connector.status === "coming_soon" ? (
                mark
              ) : (
                <Link href={`/sources/${connector.id}`}>{mark}</Link>
              )}
            </li>
          );
        })}
      </ul>
      <p className="text-xs text-white/35">
        {live.length} live today. Dimmed marks are on the way, and arrive without an app update.
      </p>
      <Link
        href="/sources"
        className="text-[13px] text-white/50 underline-offset-4 transition hover:text-white hover:underline"
      >
        Every source and the numbers it reports
      </Link>
    </div>
  );
}
