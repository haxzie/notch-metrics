import { ConnectorMark } from "@/components/ConnectorMark";
import { catalogue } from "@notch/integrations";
import { Flares } from "./NotchMockup";

/**
 * The feature grid: one card per thing the notch does, each opening with a
 * drawing of the island doing it.
 *
 * The illustrations are the argument, so they are the app's own components
 * at a smaller size rather than grey placeholders. A card that shows a
 * stand-in of the product is a card that promises something the download
 * does not deliver.
 */
const SPARK = [30, 26, 28, 20, 22, 15, 17, 10, 12, 6, 8, 2];
const BARS = [42, 58, 51, 74, 66, 88, 97];
const PAYMENTS: [string, string][] = [
  ["Pro · yearly", "$79"],
  ["Pro · monthly", "$19"],
  ["Team · yearly", "$1,188"],
  ["Pro · monthly", "$19"],
];

const stripe = { provider: "stripe", name: "Stripe", accent: "#635BFF", colour: "#8f88ff" };
const polar = { provider: "polar", name: "Polar", accent: "#090909", colour: "#ffffff" };
const paddle = { provider: "paddle", name: "Paddle", accent: "#FDDD35" };
const dodo = {
  provider: "dodopayments",
  name: "Dodo Payments",
  accent: "#111111",
  colour: "#c6f135",
};
const github = { provider: "github", name: "GitHub", accent: "#181717", colour: "#d0d7de" };
const revenuecat = { provider: "revenuecat", name: "RevenueCat", accent: "#F2545B" };

export function NotchBento() {
  return (
    <section className="mx-auto max-w-6xl scroll-mt-28 px-6 pt-28" id="features">
      <h2 className="mx-auto max-w-3xl text-balance text-center text-[2.5rem] font-bold leading-[1.02] tracking-[-0.03em] sm:text-[3.5rem]">
        Every number you check, in the notch.
      </h2>

      <div className="mt-14 grid items-start gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <div className="flex flex-col gap-4">
          <Card
            title="Every number at once"
            body="Revenue, subscribers and today's takings sit side by side. Nine widgets open at a glance, and the island still reads in a second."
          >
            <div className="grid grid-cols-2 gap-2">
              <Tile
                mark={stripe}
                label="MRR"
                value="$12,480"
                delta="+4.2% vs last month"
                spark={SPARK}
                colour="#8f88ff"
                tall
              />
              <div className="flex flex-col gap-2">
                <Tile mark={stripe} label="Subscribers" value="318" />
                <Tile mark={polar} label="Today" value="$640" />
              </div>
            </div>
          </Card>

          <Card
            title="Lists, not only numbers"
            body="A recent-payments feed sits beside the headline figures, so you see who just paid without opening a dashboard."
          >
            <Tile mark={paddle} label="Recent payments" rows={PAYMENTS} />
          </Card>
        </div>

        <div className="flex flex-col gap-4">
          <Card
            title="Opens on hover"
            body="Rest the pointer on the camera housing and the notch expands over whatever you are doing. Leave, and it folds back to the shape it had."
          >
            <Screen />
          </Card>

          <Card
            title="Four tile sizes"
            body="Widgets go from a single square up to the full width. Drag to arrange them and resize them in place, in the notch itself."
          >
            <div className="flex flex-col gap-2">
              <Tile
                mark={dodo}
                label="Revenue · 7d"
                value="$3,920"
                delta="+11% vs last week"
                bars={BARS}
                colour="#c6f135"
              />
              <div className="grid grid-cols-2 gap-2">
                <Tile mark={github} label="Issues" value="14" />
                <Tile mark={revenuecat} label="Trials" value="27" />
              </div>
            </div>
          </Card>
        </div>

        <div className="flex flex-col gap-4">
          <ConnectorCard />

          <Card
            title="Quiet by default"
            body="A small native app, written in Swift. No dock icon, no window, and no menu bar clutter while you work."
          >
            <div className="flex h-[140px] items-center justify-center">
              <span className="bg-ink flex items-center gap-2.5 rounded-full px-4 py-2.5 text-[13px] font-medium text-white/80">
                <span className="h-1.5 w-1.5 rounded-full bg-emerald-400" />
                $12,480
              </span>
            </div>
          </Card>
        </div>
      </div>
    </section>
  );
}

function Card({
  title,
  body,
  children,
}: {
  title: string;
  body: string;
  children: React.ReactNode;
}) {
  return (
    <div className="bg-ink/[0.035] rounded-[28px] p-5 sm:p-6">
      {children}
      <h3 className="mt-6 text-[17px] font-semibold tracking-tight">{title}</h3>
      <p className="text-ink/55 mt-2 text-pretty text-[15px] leading-relaxed">{body}</p>
    </div>
  );
}

/**
 * One widget, lifted out of the notch and shown on its own.
 *
 * Solid black rather than the translucent fill the app uses: in the notch a
 * tile sits on the drawer, and the same 7% white on a light card would be a
 * grey rectangle.
 */
function Tile({
  mark,
  label,
  value,
  delta,
  spark,
  bars,
  rows,
  colour,
  tall,
}: {
  mark: { provider: string; name: string; accent: string };
  label: string;
  value?: string;
  delta?: string;
  spark?: number[];
  bars?: number[];
  rows?: [string, string][];
  colour?: string;
  tall?: boolean;
}) {
  return (
    <div className={`bg-ink flex flex-col rounded-[18px] p-3.5 ${tall ? "" : "flex-1"}`}>
      <div className="flex items-center gap-2">
        <ConnectorMark id={mark.provider} name={mark.name} accentColor={mark.accent} size={18} />
        <span className="truncate text-[12px] font-medium leading-none text-white/55">{label}</span>
      </div>

      {rows && (
        <ul className="mt-3 flex flex-col gap-2 text-[12px]">
          {rows.map((row, index) => (
            <li key={index} className="flex justify-between text-white/70">
              <span>{row[0]}</span>
              <span className="font-semibold tabular-nums text-white">{row[1]}</span>
            </li>
          ))}
        </ul>
      )}

      {value && (
        <span
          className={`mt-auto pt-3 font-semibold tabular-nums tracking-tight text-white ${
            tall ? "text-[26px]" : "text-[18px]"
          }`}
        >
          {value}
        </span>
      )}
      {delta && <span className="text-[11px] font-medium text-emerald-400">{delta}</span>}

      {spark && colour && <Spark colour={colour} points={spark} />}
      {bars && colour && <Bars colour={colour} values={bars} />}
    </div>
  );
}

function Spark({ colour, points }: { colour: string; points: number[] }) {
  const line = points
    .map((y, index) => `${Math.round((index * 154) / (points.length - 1))},${y}`)
    .join(" ");
  return (
    <svg viewBox="0 0 154 32" preserveAspectRatio="none" className="mt-3 h-14 w-full" aria-hidden>
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

function Bars({ colour, values }: { colour: string; values: number[] }) {
  const max = Math.max(...values);
  return (
    <span className="mt-3 flex h-10 items-end gap-1" aria-hidden>
      {values.map((value, index) => (
        <span
          key={index}
          className="flex-1 rounded-[2px]"
          style={{
            height: `${(value / max) * 100}%`,
            backgroundColor: colour,
            opacity: index === values.length - 1 ? 1 : 0.55,
          }}
        />
      ))}
    </span>
  );
}

/**
 * The closed notch in the menu bar, for the two cards whose claim is about
 * the shape rather than about what is in it.
 */
function Screen() {
  return (
    <div className="mx-auto w-full max-w-[300px] rounded-[18px] bg-black p-[4px]">
      <div className="relative h-[132px] overflow-hidden rounded-[15px] bg-[#f1ecf5]">
        <div
          aria-hidden
          className="text-ink/60 absolute inset-x-0 top-0 flex h-[16px] items-center justify-between px-2 text-[7px] font-medium"
        >
          <span className="flex items-center gap-1.5">
            <span className="text-ink font-semibold">Finder</span>
            <span>File</span>
            <span>Edit</span>
          </span>
          <span className="tabular-nums">Wed 9:41 AM</span>
        </div>

        <div className="relative mx-auto -mt-px h-[19px] w-[96px] rounded-b-[9px] bg-black">
          <Flares />
        </div>

        <svg
          aria-hidden
          viewBox="0 0 24 24"
          className="absolute left-[calc(50%+30px)] top-[22px] h-5 w-5 drop-shadow-[0_2px_6px_rgba(11,10,14,0.35)]"
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
    </div>
  );
}

/** The one white card, because the marks are drawn for a light background. */
function ConnectorCard() {
  const live = catalogue()
    .flatMap((group) => group.connectors)
    .filter((connector) => connector.status !== "coming_soon");
  const shown = live.slice(0, 5);

  return (
    <div className="bg-ink/[0.035] rounded-[28px] p-5 sm:p-6">
      <div className="flex h-[140px] items-center justify-center gap-2 rounded-[20px] bg-white">
        {shown.map((connector, index) => (
          <span
            key={connector.id}
            // The middle mark is the one in focus, the rest step back from it.
            className="drop-shadow-[0_8px_18px_rgba(11,10,14,0.18)]"
            style={{
              transform: `rotate(${(index - 2) * 7}deg) scale(${index === 2 ? 1.15 : 0.9})`,
            }}
          >
            <ConnectorMark
              id={connector.id}
              name={connector.name}
              accentColor={connector.accentColor}
              size={52}
              shape="squircle"
            />
          </span>
        ))}
      </div>
      <h3 className="mt-6 text-[17px] font-semibold tracking-tight">{live.length} sources, live</h3>
      <p className="text-ink/55 mt-2 text-pretty text-[15px] leading-relaxed">
        Stripe, Polar, Paddle, Shopify and more. Connect one on the web, and every Mac you own picks
        it up.
      </p>
    </div>
  );
}
