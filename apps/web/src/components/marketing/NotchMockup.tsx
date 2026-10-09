import { ConnectorMark } from "@/components/ConnectorMark";
import { PERSONAS, type Widget } from "./personas";

/**
 * The top of a MacBook display with the notch expanded, drawn in CSS.
 *
 * Drawn rather than screenshotted so it stays sharp at any width and so the
 * numbers can be whatever reads well. The layout matches the app's canvas:
 * six columns, with 2x2s, 2x1s and 1x1s packed the way a real one looks once
 * somebody has set it up. No menu bar: the notch hangs from the top edge of
 * the display, and the real one leaves the bar untouched.
 */
export function NotchMockup({
  variant = "expanded",
  widgets = PERSONAS[0]?.widgets ?? [],
}: {
  variant?: "expanded" | "collapsed";
  widgets?: Widget[];
}) {
  const expanded = variant === "expanded";
  return (
    <div className="relative overflow-hidden rounded-[28px] border border-white/[0.09] bg-[#0c0b0f] shadow-[0_40px_120px_-30px_rgba(0,0,0,0.9)]">
      {/* Wallpaper. */}
      <div
        aria-hidden
        className="absolute inset-0"
        style={{
          background:
            "radial-gradient(90% 70% at 20% 110%, rgba(216,25,194,0.55), transparent 60%), radial-gradient(70% 60% at 85% 100%, rgba(255,193,7,0.45), transparent 60%), radial-gradient(60% 50% at 60% 40%, rgba(88,40,140,0.5), transparent 70%), linear-gradient(180deg, #110d1c 0%, #1a1026 100%)",
        }}
      />

      <div className={`relative ${expanded ? "h-[500px] sm:h-[520px]" : "h-[170px]"}`}>
        {expanded ? <ExpandedNotch widgets={widgets} /> : <CollapsedNotch />}
      </div>
    </div>
  );
}

function CollapsedNotch() {
  return (
    <div className="absolute left-1/2 top-0 h-[30px] w-[180px] -translate-x-1/2 rounded-b-[14px] bg-black">
      <Flares />
    </div>
  );
}

const SPANS: Record<NonNullable<Widget["span"]>, string> = {
  "1x1": "",
  "2x1": "col-span-2",
  "2x2": "col-span-2 row-span-2",
};

function ExpandedNotch({ widgets }: { widgets: Widget[] }) {
  return (
    <>
      <div className="absolute left-1/2 top-0 w-[min(660px,94%)] -translate-x-1/2 rounded-b-[30px] bg-black p-3 shadow-[0_30px_60px_-20px_rgba(0,0,0,0.9)]">
        <Flares />
        <div className="grid grid-cols-6 grid-rows-3 gap-2">
          {widgets.map((widget, index) => (
            <WidgetTile key={index} widget={widget} />
          ))}
        </div>
      </div>

      {/* The pointer, resting where it would be to keep the notch open. */}
      <svg
        aria-hidden
        viewBox="0 0 24 24"
        className="absolute left-[calc(50%+120px)] top-[328px] h-6 w-6 drop-shadow-[0_2px_6px_rgba(0,0,0,0.7)] sm:top-[338px]"
      >
        <path
          d="M5 3.5 19 10.2l-6.1 1.9-2.6 5.9Z"
          fill="white"
          stroke="black"
          strokeWidth={1.5}
          strokeLinejoin="round"
        />
      </svg>
    </>
  );
}

function WidgetTile({ widget }: { widget: Widget }) {
  const span = widget.span ?? "1x1";
  const colour = widget.colour ?? widget.accent;
  return (
    <div
      className={`flex min-h-[92px] flex-col rounded-[14px] border border-white/[0.07] bg-white/[0.07] p-2.5 ${SPANS[span]}`}
    >
      <div className="flex items-center gap-1.5">
        <ConnectorMark
          id={widget.provider}
          name={widget.name}
          accentColor={widget.accent}
          size={16}
        />
        <span className="truncate text-[11px] font-medium leading-none text-white/55">
          {widget.label}
        </span>
      </div>

      {widget.rows && (
        <ul className="mt-2 flex flex-col gap-[9px] text-[11px] leading-none">
          {widget.rows.map(([left, right], index) => (
            <li key={index} className="flex items-center justify-between text-white/75">
              <span className="truncate">{left}</span>
              <span className="font-semibold tabular-nums text-white">{right}</span>
            </li>
          ))}
        </ul>
      )}

      {widget.spark && (
        <>
          <div className="mt-auto">
            <Value large>{widget.value}</Value>
            {widget.delta && <Delta>{widget.delta}</Delta>}
          </div>
          <Sparkline colour={colour} points={widget.spark} />
        </>
      )}

      {widget.bars && span === "2x2" && (
        <>
          <div className="mt-auto">
            <Value large>{widget.value}</Value>
            {widget.delta && <Delta>{widget.delta}</Delta>}
          </div>
          <Bars colour={colour} values={widget.bars} tall />
        </>
      )}

      {widget.bars && span !== "2x2" && (
        <div className="mt-auto flex items-end justify-between gap-3">
          <div>
            <Value>{widget.value}</Value>
            {widget.delta && <Delta>{widget.delta}</Delta>}
          </div>
          <Bars colour={colour} values={widget.bars} />
        </div>
      )}

      {!widget.rows && !widget.spark && !widget.bars && <Value>{widget.value}</Value>}
    </div>
  );
}

function Value({ large, children }: { large?: boolean; children: React.ReactNode }) {
  return (
    <span
      className={`mt-auto block font-semibold tabular-nums tracking-tight text-white ${
        large ? "text-[26px]" : "text-[17px]"
      }`}
    >
      {children}
    </span>
  );
}

function Delta({ children }: { children: React.ReactNode }) {
  return <span className="block text-[11px] font-medium text-emerald-400">{children}</span>;
}

/** A week of bars, solid in the brand colour, the last one brightest. */
function Bars({ colour, values, tall }: { colour: string; values: number[]; tall?: boolean }) {
  const max = Math.max(...values);
  return (
    <div
      className={`flex items-end gap-[3px] ${tall ? "mt-2 h-14 gap-[5px]" : "h-11"}`}
      aria-hidden
    >
      {values.map((value, index) => (
        <span
          key={index}
          className={`rounded-[2px] ${tall ? "flex-1" : "w-[7px]"}`}
          style={{
            height: `${(value / max) * 100}%`,
            backgroundColor: colour,
            opacity: index === values.length - 1 ? 1 : 0.55,
          }}
        />
      ))}
    </div>
  );
}

/** Points are heights on a 0–32 scale, left to right; lower is higher. */
function Sparkline({ colour, points }: { colour: string; points: number[] }) {
  const step = 154 / (points.length - 1);
  const line = points.map((y, index) => `${Math.round(index * step)},${y}`).join(" ");
  // The fill's gradient id carries the colour so two sparklines on one page
  // with different colours do not share, and therefore fight over, one id.
  const gradientId = `spark-${colour.replace("#", "")}`;
  return (
    <svg viewBox="0 0 154 32" preserveAspectRatio="none" className="mt-2 h-14 w-full" aria-hidden>
      <defs>
        <linearGradient id={gradientId} x1="0" x2="0" y1="0" y2="1">
          <stop offset="0" stopColor={colour} stopOpacity="0.45" />
          <stop offset="1" stopColor={colour} stopOpacity="0" />
        </linearGradient>
      </defs>
      <polygon points={`0,32 ${line} 154,32`} fill={`url(#${gradientId})`} />
      <polyline
        points={line}
        fill="none"
        stroke={colour}
        strokeWidth={1.75}
        strokeLinejoin="round"
        strokeLinecap="round"
        vectorEffect="non-scaling-stroke"
      />
    </svg>
  );
}

/**
 * The concave corners where the notch meets the top edge. The display's
 * glass is black there too, so each is a square with a quarter circle of
 * wallpaper cut out of its outer-bottom corner.
 */
function Flares() {
  const r = 14;
  const flare = (side: "left" | "right") => ({
    width: r,
    height: r,
    [side === "left" ? "right" : "left"]: "100%",
    background: `radial-gradient(circle at ${side === "left" ? "0" : "100%"} 100%, transparent ${r - 0.5}px, black ${r}px)`,
  });
  return (
    <>
      <span aria-hidden className="absolute top-0" style={flare("left")} />
      <span aria-hidden className="absolute top-0" style={flare("right")} />
    </>
  );
}
