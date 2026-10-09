import { ConnectorMark } from "@/components/ConnectorMark";
import { AppleMark } from "./icons";

/**
 * The top of a MacBook display with the notch expanded, drawn in CSS.
 *
 * Drawn rather than screenshotted so it stays sharp at any width and so the
 * numbers can be whatever reads well. The layout matches the app's six-by-two
 * canvas: a 2x2, four 1x1s and a 2x2 list, which is what a real one looks
 * like once somebody has set it up.
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

      <Menubar />

      <div className={`relative ${expanded ? "h-[300px] sm:h-[320px]" : "h-[150px]"}`}>
        {expanded ? <ExpandedNotch /> : <CollapsedNotch />}
      </div>
    </div>
  );
}

function Menubar() {
  return (
    <div className="relative flex h-8 items-center justify-between px-4 text-[12px] font-medium text-white/85">
      <div className="flex items-center gap-4">
        <AppleMark className="h-3.5 w-3.5" />
        <span className="font-semibold">Finder</span>
        <span className="hidden sm:inline">File</span>
        <span className="hidden sm:inline">Edit</span>
        <span className="hidden sm:inline">View</span>
        <span className="hidden sm:inline">Go</span>
        <span className="hidden md:inline">Window</span>
        <span className="hidden md:inline">Help</span>
      </div>
      <div className="flex items-center gap-3 text-white/80">
        <Battery />
        <Wifi />
        <span className="hidden sm:inline">Thu 9 Oct</span>
        <span>10:41</span>
      </div>
    </div>
  );
}

function CollapsedNotch() {
  return (
    <div className="absolute left-1/2 top-0 h-[30px] w-[180px] -translate-x-1/2 rounded-b-[14px] bg-black" />
  );
}

function ExpandedNotch() {
  return (
    <>
      <div className="absolute left-1/2 top-0 w-[min(580px,94%)] -translate-x-1/2 rounded-b-[26px] bg-black p-2.5 shadow-[0_30px_60px_-20px_rgba(0,0,0,0.9)]">
        <div className="grid grid-cols-6 grid-rows-2 gap-1.5">
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
            <ul className="mt-1.5 flex flex-col gap-[5px] text-[10px] leading-none">
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
        className="absolute left-[calc(50%+110px)] top-[150px] h-6 w-6 drop-shadow-[0_2px_6px_rgba(0,0,0,0.7)] sm:top-[160px]"
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
      className={`flex min-h-[58px] flex-col rounded-[12px] border border-white/[0.07] bg-white/[0.07] p-2 ${span}`}
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
      <ConnectorMark id={id} name={name} accentColor={accent} size={14} />
      <span className="truncate text-[10px] font-medium leading-none text-white/55">{label}</span>
    </div>
  );
}

function Value({ small, children }: { small?: boolean; children: React.ReactNode }) {
  return (
    <span
      className={`mt-auto block font-semibold tabular-nums tracking-tight text-white ${
        small ? "text-[15px]" : "text-[22px]"
      }`}
    >
      {children}
    </span>
  );
}

function Delta({ children }: { children: React.ReactNode }) {
  return <span className="block text-[10px] font-medium text-emerald-400">{children}</span>;
}

function Sparkline() {
  const points = "0,30 14,26 28,28 42,20 56,22 70,15 84,17 98,10 112,12 126,6 140,8 154,2";
  return (
    <svg viewBox="0 0 154 32" preserveAspectRatio="none" className="mt-1.5 h-9 w-full" aria-hidden>
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

function Battery() {
  return (
    <svg viewBox="0 0 28 14" className="h-3 w-6" aria-hidden>
      <rect x="1" y="1.5" width="22" height="11" rx="3" fill="none" stroke="currentColor" />
      <rect x="3" y="3.5" width="15" height="7" rx="1.5" fill="currentColor" />
      <rect x="24.5" y="4.5" width="2" height="5" rx="1" fill="currentColor" opacity="0.6" />
    </svg>
  );
}

function Wifi() {
  return (
    <svg viewBox="0 0 24 24" className="h-3.5 w-3.5" fill="none" stroke="currentColor" aria-hidden>
      <path d="M2.5 9a14 14 0 0 1 19 0M5.5 12.5a9.5 9.5 0 0 1 13 0M8.6 16a5 5 0 0 1 6.8 0" />
      <circle cx="12" cy="19" r="1.2" fill="currentColor" />
    </svg>
  );
}
