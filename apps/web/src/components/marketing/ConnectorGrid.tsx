import { ConnectorMark } from "@/components/ConnectorMark";
import { CONNECTOR_GROUPS } from "@/lib/connectors";

/**
 * Every connector as a chip, grouped the way the app's settings group them.
 * Ones not shipped yet are shown dimmed and labelled rather than hidden:
 * a visitor deciding whether to try the app wants to know PostHog is on the
 * way, and a chip that is plainly marked is not a promise it works today.
 */
export function ConnectorGrid() {
  return (
    <div className="flex flex-col gap-8">
      {CONNECTOR_GROUPS.map((group) => (
        <div key={group.label} className="flex flex-col items-center gap-3">
          <span className="eyebrow">{group.label}</span>
          <ul className="flex flex-wrap justify-center gap-2">
            {group.connectors.map((connector) => {
              const soon = connector.status === "coming_soon";
              return (
                <li
                  key={connector.id}
                  className={`flex h-11 items-center gap-2.5 rounded-xl border border-white/[0.08] bg-white/[0.04] pl-2 pr-3.5 text-sm ${
                    soon ? "opacity-55" : ""
                  }`}
                >
                  <ConnectorMark
                    id={connector.id}
                    name={connector.name}
                    accentColor={connector.accentColor}
                    size={26}
                  />
                  <span className="font-medium text-white/85">{connector.name}</span>
                  {soon && (
                    <span className="rounded-full border border-white/10 px-1.5 py-px text-[10px] uppercase tracking-wide text-white/50">
                      Soon
                    </span>
                  )}
                </li>
              );
            })}
          </ul>
        </div>
      ))}
    </div>
  );
}
