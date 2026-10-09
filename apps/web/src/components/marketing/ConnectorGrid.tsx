import { ConnectorMark } from "@/components/ConnectorMark";
import { CONNECTOR_GROUPS } from "@/lib/connectors";

/**
 * Every connector as a mark, live ones first. The name is the tooltip, not
 * a label: at this size the marks are recognisable on their own, and a wall
 * of them says "lots" faster than a list does. Ones not shipped yet are
 * dimmed rather than hidden, so a visitor can see PostHog is on the way
 * without being told it works today.
 */
export function ConnectorGrid() {
  const all = CONNECTOR_GROUPS.flatMap((group) => group.connectors);
  const live = all.filter((connector) => connector.status === "stable");
  const soon = all.filter((connector) => connector.status !== "stable");

  return (
    <div className="flex flex-col items-center gap-6">
      <ul className="flex max-w-3xl flex-wrap justify-center gap-3 sm:gap-4">
        {[...live, ...soon].map((connector) => (
          <li
            key={connector.id}
            className={`rounded-[22px] border border-white/[0.08] bg-white/[0.04] p-2 transition hover:bg-white/[0.07] ${
              connector.status === "stable" ? "" : "opacity-40 grayscale-[0.3]"
            }`}
          >
            <ConnectorMark
              id={connector.id}
              name={connector.name}
              accentColor={connector.accentColor}
              size={56}
            />
          </li>
        ))}
      </ul>
      <p className="text-xs text-white/35">
        {live.length} live today. Dimmed marks are on the way, and arrive without an app update.
      </p>
    </div>
  );
}
