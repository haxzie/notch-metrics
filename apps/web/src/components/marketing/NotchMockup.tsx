import { ConnectorMark } from "@/components/ConnectorMark";
import { PERSONAS, type Widget } from "./personas";

/**
 * The top of a MacBook display with the notch expanded, drawn in CSS.
 *
 * Drawn rather than screenshotted so it stays sharp at any width and so the
 * numbers can be whatever reads well. The layout matches the app's canvas:
 * six columns, with 2x2s, 2x1s and 1x1s packed the way a real one looks once
 * somebody has set it up.
 *
 * The menu bar is drawn because the notch is only legible against it. On a
 * bare wallpaper a black rounded shape reads as a floating widget; sitting
 * in the bar, over the menus, it reads as the hardware it hangs from.
 */
export function NotchMockup({
  widgets = PERSONAS[0]?.widgets ?? [],
  controls,
}: {
  widgets?: Widget[];
  /** Anything that belongs on the desktop under the notch, like the setup
      picker on the home page. Inside the screen rather than under the frame,
      so the mockup stays one object. */
  controls?: React.ReactNode;
}) {
  return (
    /* No bottom edge. A display with all four sides drawn is a picture of a
       Mac sitting on the page; one that runs off the bottom is the Mac the
       reader is looking at. The fade below does the cutting, so there is no
       hard line anywhere. */
    <div className="relative">
      <div className="rounded-t-[34px] bg-black px-[7px] pt-[7px]">
        <div className="relative overflow-hidden rounded-t-[27px] bg-[#f1ecf5]">
          <MenuBar />

          {/* The desktop under the notch, sized so the panel keeps roughly the
              same share of the screen at every width. The panel scales down on
              a phone (see NOTCH_SCALE) and a fixed height would leave it
              floating at the top of a great field of empty wallpaper. */}
          <div className="relative h-[340px] min-[400px]:h-[380px] min-[440px]:h-[420px] min-[520px]:h-[480px] min-[600px]:h-[545px] sm:h-[575px] md:h-[620px]">
            <ExpandedNotch widgets={widgets} />
            {controls && (
              <div className="absolute inset-x-0 bottom-[86px] z-20 flex justify-center px-3 min-[440px]:bottom-[100px] min-[600px]:bottom-[120px] sm:px-4 md:bottom-[148px]">
                {controls}
              </div>
            )}
          </div>
        </div>
      </div>

      {/* The paper, brought up over the bottom of the screen. It has to be
          the page's own colour rather than a mask: the frame is black to its
          edge, and a mask would fade the desktop and the bezel at different
          rates and leave the bezel as two grey legs. */}
      <div
        aria-hidden
        /* Shorter on a phone, where the screen itself is shorter: a fixed
           128px fade would reach up over the setup picker and grey it out. */
        className="pointer-events-none absolute inset-x-0 bottom-0 z-30 h-[80px] sm:h-[110px] md:h-[128px]"
        style={{
          background:
            "linear-gradient(to bottom, rgba(251,250,252,0) 0%, rgba(251,250,252,0.72) 46%, rgba(251,250,252,0.97) 72%, #fbfafc 86%)",
        }}
      />
    </div>
  );
}

const MENUS = ["Finder", "File", "Edit", "View", "Window", "Help"];

/**
 * The macOS menu bar, which the notch hangs into.
 *
 * Absolutely placed so it sits under the notch panel rather than pushing it
 * down: on a real Mac the bar runs edge to edge behind the camera housing,
 * and the app's panel covers the middle of it when it opens.
 */
function MenuBar() {
  return (
    <div
      aria-hidden
      className="text-ink/70 absolute inset-x-0 top-0 z-0 flex h-[30px] items-center justify-between px-3 text-[11px]"
    >
      <div className="flex min-w-0 items-center gap-2.5 sm:gap-3.5">
        <AppleMenuMark />
        {MENUS.map((menu, index) => (
          <span
            key={menu}
            className={`${index === 0 ? "text-ink font-semibold" : ""} ${
              // A real menu bar drops the menus it has no room for, so the
              // mockup does too. Keeping all six on a phone pushed the clock
              // off the right edge, which is the one part of the bar a
              // reader checks against their own screen.
              index >= 2 ? "hidden sm:inline" : ""
            }`}
          >
            {menu}
          </span>
        ))}
      </div>
      <div className="flex shrink-0 items-center gap-2 sm:gap-2.5">
        <BatteryMark />
        <WifiMark />
        <ControlCentreMark />
        <span className="font-medium tabular-nums">Wed 9:41 AM</span>
      </div>
    </div>
  );
}

function AppleMenuMark() {
  return (
    <svg viewBox="0 0 24 24" className="fill-ink h-[13px] w-[13px]">
      <path d="M16.3 12.6c0-2.3 1.9-3.4 2-3.5-1.1-1.6-2.8-1.8-3.4-1.8-1.4-.1-2.8.9-3.5.9s-1.8-.9-3-.8c-1.5 0-2.9.9-3.7 2.3-1.6 2.7-.4 6.8 1.1 9 .8 1.1 1.7 2.3 2.9 2.2 1.2 0 1.6-.7 3-.7s1.8.7 3 .7c1.3 0 2.1-1.1 2.8-2.2.9-1.2 1.3-2.5 1.3-2.5s-2.5-1-2.5-3.6ZM14 5.9c.6-.8 1-1.9.9-3-.9 0-2.1.6-2.7 1.4-.6.7-1.1 1.8-1 2.9 1 .1 2.1-.5 2.8-1.3Z" />
    </svg>
  );
}

function BatteryMark() {
  return (
    <svg viewBox="0 0 28 14" className="h-[11px] w-[22px]">
      <rect
        x="0.75"
        y="0.75"
        width="22.5"
        height="12.5"
        rx="3.5"
        fill="none"
        stroke="currentColor"
        strokeOpacity="0.45"
        strokeWidth="1.5"
      />
      <rect x="2.75" y="2.75" width="15" height="8.5" rx="1.75" fill="currentColor" />
      <path
        d="M25.5 5v4c1-.4 1.5-1.1 1.5-2s-.5-1.6-1.5-2Z"
        fill="currentColor"
        fillOpacity="0.45"
      />
    </svg>
  );
}

function WifiMark() {
  return (
    <svg viewBox="0 0 24 18" className="h-[12px] w-[16px] fill-current">
      <path d="M12 16.5 9.2 13a3.6 3.6 0 0 1 5.6 0ZM12 9.2c-1.9 0-3.6.8-4.8 2.1L5.4 9c1.7-1.7 4-2.8 6.6-2.8s4.9 1.1 6.6 2.8l-1.8 2.3A6.4 6.4 0 0 0 12 9.2ZM12 2.4c-3.6 0-6.9 1.5-9.2 3.9L1 3.9A15.3 15.3 0 0 1 12 .6c4.3 0 8.2 1.7 11 4.4L21 7.3A12.3 12.3 0 0 0 12 2.4Z" />
    </svg>
  );
}

function ControlCentreMark() {
  return (
    <svg viewBox="0 0 20 20" className="h-[12px] w-[12px] fill-none stroke-current">
      <rect x="3" y="3.5" width="14" height="5.5" rx="2.75" strokeWidth="1.4" />
      <circle cx="7" cy="6.25" r="1.4" fill="currentColor" stroke="none" />
      <rect x="3" y="11" width="14" height="5.5" rx="2.75" strokeWidth="1.4" />
      <circle cx="13" cy="13.75" r="1.4" fill="currentColor" stroke="none" />
    </svg>
  );
}

const SPANS: Record<NonNullable<Widget["span"]>, string> = {
  "1x1": "",
  "2x1": "col-span-2",
  "2x2": "col-span-2 row-span-2",
};

/**
 * The panel is drawn at one fixed width and scaled down to fit, rather than
 * being allowed to narrow.
 *
 * It is a picture of a fixed geometry: six columns, type sized in pixels
 * against a 660px panel, tiles with a minimum height. Let the width shrink on
 * a phone and the columns land at about fifty pixels each while the type stays
 * where it was, so `$12,480` sits on top of its own sparkline and every label
 * truncates to an ellipsis. Reflowing to fewer columns would be a different
 * misstatement: the app really is six wide, and the claim this section makes
 * is that nine numbers fit at once. Scaling keeps every proportion and costs
 * only absolute size, which is what a notch looks like from across a room.
 *
 * Steps rather than a `vw` expression, because the honest version of this is
 * `min(1, available / 660px)` and CSS cannot divide a length by a length to
 * get the number `scale()` wants. A `min()` mixing the two is invalid and is
 * dropped silently, which looks exactly like the bug it was meant to fix.
 *
 * Each step is the largest that still fits inside the frame at that width:
 * the screen is the viewport less the 7px bezel on each side.
 */
const NOTCH_SCALE = [
  "scale-[0.44]",
  "min-[360px]:scale-[0.5]",
  "min-[400px]:scale-[0.56]",
  "min-[440px]:scale-[0.62]",
  "min-[520px]:scale-[0.74]",
  "min-[600px]:scale-[0.86]",
  "sm:scale-[0.92]",
  "md:scale-100",
].join(" ");

function ExpandedNotch({ widgets }: { widgets: Widget[] }) {
  return (
    <div
      className={`absolute left-1/2 top-[-1px] z-10 w-[660px] origin-top -translate-x-1/2 rounded-b-[30px] bg-black p-3 pt-[13px] shadow-[0_30px_60px_-20px_rgba(11,10,14,0.45)] ${NOTCH_SCALE}`}
    >
      <Flares />
      <DrawerHeader />
      <div className="grid grid-cols-6 grid-rows-3 gap-2">
        {widgets.map((widget, index) => (
          <WidgetTile key={index} widget={widget} />
        ))}
      </div>

      {/* The pointer, resting on the bottom edge of the panel, which is where
          it has to be for the notch to stay open. Placed against the panel
          rather than the screen so it still touches the edge when a setup
          with fewer widgets makes the panel shorter. */}
      <svg
        aria-hidden
        viewBox="0 0 24 24"
        className="absolute -bottom-2 right-[22%] h-6 w-6 drop-shadow-[0_2px_6px_rgba(11,10,14,0.35)]"
      >
        <path
          d="M5 3.5 19 10.2l-6.1 1.9-2.6 5.9Z"
          fill="white"
          stroke="black"
          strokeWidth={1.5}
          strokeLinejoin="round"
        />
      </svg>
    </div>
  );
}

/**
 * The row along the top of the open drawer, as the app draws it: the app's
 * own name and controls on the left, the widget editor and the close button
 * on the right.
 *
 * It is what tells a visitor the black shape is an app and not a screenshot
 * of a dashboard, so the mockup is wrong without it.
 */
function DrawerHeader() {
  return (
    <div className="mb-2.5 flex items-center justify-between px-1 pt-0.5">
      <div className="flex items-center gap-2.5">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src="/logo.svg" alt="" width={16} height={16} />
        <span className="text-[12px] font-semibold text-white/90">Notch Metrics</span>
        <span className="flex items-center gap-2 text-white/45">
          <RefreshGlyph />
          <BellGlyph />
          <GearGlyph />
        </span>
      </div>
      <div className="flex items-center gap-2">
        <span className="flex items-center gap-1.5 rounded-full bg-white/[0.08] px-2.5 py-1 text-[11px] font-medium text-white/80">
          <GridGlyph />
          Edit Widgets
        </span>
        <span className="text-white/45">
          <CloseGlyph />
        </span>
      </div>
    </div>
  );
}

const GLYPH = {
  viewBox: "0 0 24 24",
  fill: "none",
  stroke: "currentColor",
  strokeWidth: 1.8,
  strokeLinecap: "round",
  strokeLinejoin: "round",
  className: "h-3.5 w-3.5",
} as const;

function RefreshGlyph() {
  return (
    <svg {...GLYPH} aria-hidden>
      <path d="M20 12a8 8 0 1 1-2.6-5.9M20 4v4h-4" />
    </svg>
  );
}

function BellGlyph() {
  return (
    <svg {...GLYPH} aria-hidden>
      <path d="M18 9a6 6 0 1 0-12 0c0 5-2 6-2 6h16s-2-1-2-6M13.7 20a2 2 0 0 1-3.4 0" />
    </svg>
  );
}

function GearGlyph() {
  return (
    <svg {...GLYPH} aria-hidden>
      <circle cx="12" cy="12" r="3" />
      <path d="M12 2.5v2M12 19.5v2M21.5 12h-2M4.5 12h-2M18.7 5.3l-1.4 1.4M6.7 17.3l-1.4 1.4M18.7 18.7l-1.4-1.4M6.7 6.7 5.3 5.3" />
    </svg>
  );
}

function GridGlyph() {
  return (
    <svg viewBox="0 0 24 24" fill="currentColor" className="h-3 w-3" aria-hidden>
      <circle cx="7" cy="7" r="2.4" />
      <circle cx="17" cy="7" r="2.4" />
      <circle cx="7" cy="17" r="2.4" />
      <circle cx="17" cy="17" r="2.4" />
    </svg>
  );
}

function CloseGlyph() {
  return (
    <svg {...GLYPH} aria-hidden>
      <path d="M6 6l12 12M18 6 6 18" />
    </svg>
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
export function Flares() {
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
