/**
 * One notch layout per kind of person who might install the app.
 *
 * Every layout fills the same six-by-three canvas so the slides line up, and
 * every one is a plausible setup rather than a showcase of everything: a
 * founder's notch has revenue on it, not GitHub stars.
 *
 * There was a fourth, Sales, until HubSpot and Intercom were removed. It was
 * nine-tenths those two, and the note here used to say that leaning on
 * connectors marked "Soon" was deliberate — it showed where the product was
 * going. With them gone it showed where it is not, so the layout went with
 * them rather than being rebuilt out of revenue widgets the Founders layout
 * already covers.
 */
export type WidgetSpan = "1x1" | "2x1" | "2x2";

export interface Widget {
  provider: string;
  name: string;
  accent: string;
  label: string;
  span?: WidgetSpan;
  value?: string;
  delta?: string;
  /** A week of bars, in `colour`. */
  bars?: number[];
  /** A line, in `colour`. */
  spark?: number[];
  rows?: [string, string][];
  colour?: string;
}

export interface Persona {
  id: string;
  label: string;
  widgets: Widget[];
}

const stripe = { provider: "stripe", name: "Stripe", accent: "#635BFF", colour: "#8f88ff" };
// White graphs: Polar's brand is monochrome, so there is no brand colour to
// draw a line in — a tinted one would be invented.
const polar = { provider: "polar", name: "Polar", accent: "#090909", colour: "#ffffff" };
const paddle = { provider: "paddle", name: "Paddle", accent: "#FDDD35" };
const dodo = {
  provider: "dodopayments",
  name: "Dodo Payments",
  accent: "#111111",
  colour: "#c6f135",
};
const revenuecat = { provider: "revenuecat", name: "RevenueCat", accent: "#F2545B" };
const github = { provider: "github", name: "GitHub", accent: "#181717", colour: "#d0d7de" };
const ga = {
  provider: "google-analytics",
  name: "Google Analytics",
  accent: "#E8710A",
  colour: "#f4a259",
};
const plausible = {
  provider: "plausible",
  name: "Plausible",
  accent: "#5850EC",
  colour: "#8a84ff",
};
const gsc = {
  provider: "google-search-console",
  name: "Search Console",
  accent: "#4285F4",
  colour: "#7aa9ff",
};

export const PERSONAS: Persona[] = [
  {
    id: "builders",
    label: "Builders",
    widgets: [
      {
        ...stripe,
        label: "MRR",
        span: "2x2",
        value: "$12,480",
        delta: "+4.2% vs last month",
        spark: [30, 26, 28, 20, 22, 15, 17, 10, 12, 6, 8, 2],
      },
      { ...stripe, label: "Subscribers", value: "318" },
      { ...polar, label: "Today", value: "$640" },
      {
        ...paddle,
        label: "Recent payments",
        span: "2x2",
        rows: [
          ["Pro · yearly", "$79"],
          ["Pro · monthly", "$19"],
          ["Pro · monthly", "$19"],
          ["Pro · yearly", "$79"],
          ["Pro · monthly", "$19"],
        ],
      },
      { ...github, label: "Stars", value: "2,104" },
      { ...revenuecat, label: "Trials", value: "27" },
      {
        ...dodo,
        label: "Revenue · 7d",
        span: "2x1",
        value: "$3,920",
        delta: "+11% vs last week",
        bars: [42, 58, 51, 74, 66, 88, 97],
      },
      { ...dodo, label: "Orders", value: "146" },
      {
        ...revenuecat,
        label: "Active subs",
        span: "2x1",
        value: "1,208",
        delta: "+38 this week",
        bars: [61, 64, 63, 70, 72, 78, 84],
      },
      { ...github, label: "Open issues", value: "14" },
    ],
  },
  {
    id: "founders",
    label: "Founders",
    widgets: [
      {
        ...stripe,
        label: "ARR",
        span: "2x2",
        value: "$486k",
        delta: "+6.1% vs last month",
        spark: [32, 30, 29, 27, 26, 22, 21, 18, 15, 12, 9, 4],
      },
      { ...stripe, label: "MRR", value: "$40.5k" },
      { ...stripe, label: "Net new", value: "+$2.3k" },
      {
        ...stripe,
        label: "Recent payments",
        span: "2x2",
        rows: [
          ["Team · yearly", "$1,188"],
          ["Pro · monthly", "$49"],
          ["Team · monthly", "$119"],
          ["Pro · yearly", "$490"],
          ["Pro · monthly", "$49"],
        ],
      },
      { ...stripe, label: "Customers", value: "1,842" },
      { ...stripe, label: "Churn", value: "1.4%" },
      {
        ...polar,
        label: "Revenue · 7d",
        span: "2x1",
        value: "$9,140",
        delta: "+8% vs last week",
        bars: [55, 48, 62, 70, 64, 81, 90],
      },
      { ...polar, label: "New customers", value: "63" },
      {
        ...revenuecat,
        label: "App subscribers",
        span: "2x1",
        value: "5,310",
        delta: "+112 this week",
        bars: [60, 62, 66, 65, 71, 76, 82],
      },
      { ...revenuecat, label: "Trial → paid", value: "38%" },
    ],
  },
  {
    id: "marketing",
    label: "Marketing",
    widgets: [
      {
        ...ga,
        label: "Visitors · 30d",
        span: "2x2",
        value: "48,210",
        delta: "+17% vs last month",
        spark: [30, 28, 29, 25, 24, 21, 22, 17, 15, 12, 10, 5],
      },
      { ...plausible, label: "Live now", value: "212" },
      { ...gsc, label: "Clicks today", value: "1,940" },
      {
        ...plausible,
        label: "Top pages",
        span: "2x2",
        rows: [
          ["/", "9,412"],
          ["/pricing", "3,870"],
          ["/blog/launch", "2,206"],
          ["/docs", "1,540"],
          ["/changelog", "988"],
        ],
      },
      { ...gsc, label: "Avg position", value: "8.4" },
      { ...ga, label: "Signups", value: "386" },
      {
        ...plausible,
        label: "Pageviews · 7d",
        span: "2x1",
        value: "126k",
        delta: "+12% vs last week",
        bars: [40, 44, 42, 48, 52, 50, 56],
      },
      { ...ga, label: "Sessions", value: "61,400" },
      {
        ...gsc,
        label: "Impressions",
        span: "2x1",
        value: "214k",
        delta: "+9% vs last week",
        bars: [58, 61, 66, 70, 74, 80, 86],
      },
      { ...plausible, label: "Bounce", value: "41%" },
    ],
  },
];
