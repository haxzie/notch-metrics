import { ConnectorMark } from "@/components/ConnectorMark";

/**
 * The top of a MacBook display with the notch expanded, drawn in CSS.
 *
 * Drawn rather than screenshotted so it stays sharp at any width and so the
 * numbers can be whatever reads well. The layout matches the app's six-by-two
 * canvas: a 2x2, four 1x1s and a 2x2 list, which is what a real one looks
 * like once somebody has set it up. No menu bar: the notch hangs from the
 * top edge of the display, and the real one leaves the bar untouched.
 */
export function NotchMockup({ variant = "expanded" }: { variant?: "expanded" | "collapsed" }) {
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

      <div className={`relative ${expanded ? "h-[400px] sm:h-[420px]" : "h-[170px]"}`}>
        {expanded ? <ExpandedNotch /> : <CollapsedNotch />}
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

function ExpandedNotch() {
  return (
    <>
      <div className="absolute left-1/2 top-0 w-[min(660px,94%)] -translate-x-1/2 rounded-b-[30px] bg-black p-3 shadow-[0_30px_60px_-20px_rgba(0,0,0,0.9)]">
        <Flares />
        <div className="grid grid-cols-6 grid-rows-2 gap-2">
          <Tile span="col-span-2 row-span-2">
            <TileHeader id="stripe" name="Stripe" accent="#635BFF" label="MRR" />
            <div className="mt-auto">
              <Value>$12,480</Value>
              <Delta>+4.2% vs last month</Delta>
            </div>
            <Sparkline />
          </Tile>

          <Tile>
            <TileHeader id="stripe" name="Stripe" accent="#635BFF" label="Subscribers" />
            <Value small>318</Value>
          </Tile>
          <Tile>
            <TileHeader id="polar" name="Polar" accent="#0062FF" label="Today" />
            <Value small>$640</Value>
          </Tile>

          <Tile span="col-span-2 row-span-2">
            <TileHeader id="paddle" name="Paddle" accent="#FDDD35" label="Recent payments" />
            <ul className="mt-2 flex flex-col gap-[9px] text-[11px] leading-none">
              {[
                ["Pro · yearly", "$79"],
                ["Pro · monthly", "$19"],
                ["Pro · monthly", "$19"],
                ["Pro · yearly", "$79"],
                ["Pro · monthly", "$19"],
              ].map(([plan, amount], index) => (
                <li key={index} className="flex items-center justify-between text-white/75">
                  <span className="truncate">{plan}</span>
                  <span className="font-semibold tabular-nums text-white">{amount}</span>
                </li>
              ))}
            </ul>
          </Tile>

          <Tile>
            <TileHeader id="github" name="GitHub" accent="#181717" label="Stars" />
            <Value small>2,104</Value>
          </Tile>
          <Tile>
            <TileHeader id="revenuecat" name="RevenueCat" accent="#F2545B" label="Trials" />
            <Value small>27</Value>
          </Tile>
        </div>
      </div>

      {/* The pointer, resting where it would be to keep the notch open. */}
      <svg
        aria-hidden
        viewBox="0 0 24 24"
        className="absolute left-[calc(50%+120px)] top-[228px] h-6 w-6 drop-shadow-[0_2px_6px_rgba(0,0,0,0.7)] sm:top-[238px]"
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

function Tile({ span = "", children }: { span?: string; children: React.ReactNode }) {
  return (
    <div
      className={`flex min-h-[92px] flex-col rounded-[14px] border border-white/[0.07] bg-white/[0.07] p-2.5 ${span}`}
    >
      {children}
    </div>
  );
}

function TileHeader({
  id,
  name,
  accent,
  label,
}: {
  id: string;
  name: string;
  accent: string;
  label: string;
}) {
  return (
    <div className="flex items-center gap-1.5">
      <ConnectorMark id={id} name={name} accentColor={accent} size={16} />
      <span className="truncate text-[11px] font-medium leading-none text-white/55">{label}</span>
    </div>
  );
}

function Value({ small, children }: { small?: boolean; children: React.ReactNode }) {
  return (
    <span
      className={`mt-auto block font-semibold tabular-nums tracking-tight text-white ${
        small ? "text-[17px]" : "text-[26px]"
      }`}
    >
      {children}
    </span>
  );
}

function Delta({ children }: { children: React.ReactNode }) {
  return <span className="block text-[11px] font-medium text-emerald-400">{children}</span>;
}

function Sparkline() {
  const points = "0,30 14,26 28,28 42,20 56,22 70,15 84,17 98,10 112,12 126,6 140,8 154,2";
  return (
    <svg viewBox="0 0 154 32" preserveAspectRatio="none" className="mt-2 h-14 w-full" aria-hidden>
      <defs>
        <linearGradient id="spark-fill" x1="0" x2="0" y1="0" y2="1">
          <stop offset="0" stopColor="#635BFF" stopOpacity="0.45" />
          <stop offset="1" stopColor="#635BFF" stopOpacity="0" />
        </linearGradient>
      </defs>
      <polygon points={`0,32 ${points} 154,32`} fill="url(#spark-fill)" />
      <polyline
        points={points}
        fill="none"
        stroke="#8f88ff"
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
