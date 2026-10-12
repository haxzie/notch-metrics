import type { Tool } from "./types.ts";
import { safeDivide } from "./types.ts";

export const OTHER_TOOLS: Tool[] = [
  {
    slug: "average-order-value-calculator",
    name: "Average order value calculator",
    category: "commerce",
    heading: "Average order value calculator",
    description:
      "Divide sales by orders to get AOV, with the revenue per customer and repeat rate that explain what moved it.",
    lede: "Average order value is sales divided by orders. The arithmetic is trivial; the reporting is where it goes wrong.",
    formula: "AOV = total sales ÷ number of orders",
    fields: [
      { key: "sales", label: "Total sales in the period", unit: "money", default: 4820000, min: 0 },
      { key: "orders", label: "Number of orders", unit: "count", default: 620, min: 0 },
      {
        key: "customers",
        label: "Distinct customers",
        unit: "count",
        default: 480,
        min: 0,
        help: "Used for revenue per customer and the repeat rate.",
      },
    ],
    outputs: [
      { key: "aov", label: "Average order value", unit: "money", primary: true },
      { key: "perCustomer", label: "Revenue per customer", unit: "money" },
      {
        key: "ordersPer",
        label: "Orders per customer",
        unit: "count",
        help: "Above 1 means repeat purchasing.",
      },
    ],
    compute: (v) => {
      const aov = safeDivide(v("sales"), v("orders"));
      const perCustomer = safeDivide(v("sales"), v("customers"));
      return {
        aov: aov === null ? null : Math.round(aov),
        perCustomer: perCustomer === null ? null : Math.round(perCustomer),
        ordersPer: safeDivide(v("orders"), v("customers")),
      };
    },
    sections: [
      {
        heading: "The mistake almost every chart makes",
        paragraphs: [
          "There are two ways to compute AOV over a week and only one is right. Sum the week's sales, sum the week's orders, divide. Do not compute each day's AOV and average the seven numbers.",
          "The second method treats a Sunday with two orders as equal in weight to a Black Friday with two thousand, and a single quiet day with one expensive order can move it by a third.",
          "This is also why a correct AOV chart looks inconsistent with its own headline: each point is that day's ratio and the headline is the period's. They are not supposed to match.",
        ],
      },
      {
        heading: "Use the same filter on both sides",
        paragraphs: [
          "The easiest bug to write here is filtering the sales total to exclude refunded orders and forgetting to filter the order count. AOV then quietly drops and nothing looks obviously wrong.",
          "Include refunded orders in both and AOV is the average value of orders placed. Exclude them from both and it is the average value of orders kept. Both are defensible. Only mixing them is not.",
        ],
      },
      {
        heading: "What actually moves AOV",
        paragraphs: [
          "Price increases move it evenly across every order, which is the easiest case to read.",
          "Bundles and upsells move it only for the orders that take them, so the mean rises while the median order does not change at all. If AOV is up and nothing feels different, look at the distribution before celebrating.",
          "One wholesale order moves it for a single day and then it falls back. If a single order can visibly move your AOV, the mean is the wrong statistic and you want the median.",
        ],
      },
      {
        heading: "Read it with volume",
        paragraphs: [
          "AOV rising while orders fall is a smaller, richer customer base. That might be the strategy or it might be a problem, and the ratio alone cannot say which.",
          "Put sales, orders and AOV side by side. Sales climbing on flat orders is a bigger basket; sales climbing on flat AOV is simply more customers. One number cannot tell you which happened.",
        ],
      },
    ],
    faq: [
      {
        question: "How do you calculate average order value?",
        answer:
          "Divide total sales in a period by the number of orders in the same period. Do not average the daily values: that weights a quiet Sunday equally with Black Friday.",
      },
      {
        question: "Why does my AOV headline not match my AOV chart?",
        answer:
          "Because each chart point is that day's own ratio and the headline is the period's total sales divided by its total orders. They are not supposed to match, and a tool whose headline equals the mean of its points is calculating it wrongly.",
      },
      {
        question: "Should refunded orders count in average order value?",
        answer:
          "Either, as long as both sides match. Include them in sales and in the order count and AOV is the average value of orders placed; exclude from both and it is the average value of orders kept. Filtering one and not the other is the common bug.",
      },
      {
        question: "Is average order value the same as revenue per customer?",
        answer:
          "No. AOV divides by orders and revenue per customer divides by customers. A shopper who orders four times is four orders and one customer, so the two diverge as repeat purchasing rises.",
      },
      {
        question: "How do I increase average order value?",
        answer:
          "Price rises move it evenly. Bundles and upsells move it only for the orders that take them, so the mean rises while the median does not. Watch the distribution rather than the mean if a single large order can move your figure.",
      },
    ],
    related: [
      { label: "What is average order value?", href: "/library/average-order-value" },
      {
        label: "Shopify average order value in the notch",
        href: "/sources/shopify/average-order-value",
      },
      {
        label: "How to calculate AOV from Shopify orders",
        href: "/blog/calculate-average-order-value-from-shopify-orders",
      },
    ],
  },

  {
    slug: "conversion-rate-calculator",
    name: "Conversion rate calculator",
    category: "marketing",
    heading: "Conversion rate calculator",
    description:
      "Work out a conversion rate from visitors and conversions, with the revenue per visitor that makes it comparable across pages.",
    lede: "Conversions divided by visitors. The number is easy; knowing which visitors belong in the denominator is not.",
    formula: "Conversion rate = conversions ÷ visitors",
    fields: [
      { key: "visitors", label: "Visitors", unit: "count", default: 12400, min: 0 },
      { key: "conversions", label: "Conversions", unit: "count", default: 248, min: 0 },
      {
        key: "value",
        label: "Average value of a conversion",
        unit: "money",
        default: 7900,
        min: 0,
        help: "Optional. Gives you revenue per visitor, which compares across pages.",
      },
    ],
    outputs: [
      { key: "rate", label: "Conversion rate", unit: "percent", primary: true },
      { key: "perVisitor", label: "Revenue per visitor", unit: "money" },
      { key: "needed", label: "Visitors per conversion", unit: "count" },
    ],
    compute: (v) => {
      const rate = safeDivide(v("conversions"), v("visitors"));
      const revenue = v("conversions") * v("value");
      const perVisitor = safeDivide(revenue, v("visitors"));
      return {
        rate: rate === null ? null : rate * 100,
        perVisitor: perVisitor === null ? null : Math.round(perVisitor),
        needed: safeDivide(v("visitors"), v("conversions")),
      };
    },
    sections: [
      {
        heading: "Pick the denominator deliberately",
        paragraphs: [
          "Visitors, sessions and pageviews give three different conversion rates for the same business, and they can differ by a lot. One person visiting four times is one visitor, four sessions and perhaps a dozen pageviews.",
          "Unique visitors is usually the honest choice for a landing page, because it answers how many people decided. Sessions is better for a checkout flow, where the same person genuinely gets several attempts.",
          "Whichever you use, use the same one when you compare two pages. Most conversion rate arguments turn out to be denominator arguments.",
        ],
      },
      {
        heading: "Revenue per visitor beats conversion rate",
        paragraphs: [
          "A conversion rate treats every conversion as identical. Revenue per visitor does not, which matters the moment you have more than one price.",
          "A page that converts 2% at $79 is worth more than one converting 4% at $29, and a conversion rate chart would show you the opposite conclusion. If you are testing anything that touches price or plan mix, revenue per visitor is the metric to decide on.",
        ],
      },
      {
        heading: "Small numbers lie",
        paragraphs: [
          "At 20 conversions, moving one conversion changes the rate by 5% relative. Two weeks of traffic on a small site can easily produce a difference that looks decisive and is noise.",
          "Before acting on a change, ask how many conversions it rests on. Under a few hundred, the honest answer is usually that you cannot tell yet.",
        ],
      },
      {
        heading: "Where conversion rates go wrong",
        paragraphs: [
          "Bot traffic inflates the denominator and depresses the rate. Analytics filtering helps; server logs usually show the scale of it.",
          "Internal traffic does the same. Your own team reloading a pricing page forty times a day is visitors who will never convert.",
          "And a rate that improves while conversions fall is a smaller, better-matched audience rather than a better page. Always read the two numbers together.",
        ],
      },
    ],
    faq: [
      {
        question: "How do you calculate conversion rate?",
        answer:
          "Divide conversions by visitors in the same period and multiply by a hundred. 248 conversions from 12,400 visitors is a 2% conversion rate.",
      },
      {
        question: "Should conversion rate use visitors or sessions?",
        answer:
          "Unique visitors is usually right for a landing page, because it answers how many people decided. Sessions suits a checkout flow, where the same person genuinely gets several attempts. The two give different numbers, so use the same one when comparing pages.",
      },
      {
        question: "What is a good conversion rate?",
        answer:
          "It depends on the traffic and the price. A free signup from branded search may convert above 10%, while a paid plan from cold traffic can be well under 1%. Compare against your own trend before any benchmark.",
      },
      {
        question: "Why use revenue per visitor instead of conversion rate?",
        answer:
          "Because a conversion rate treats every conversion as identical. A page converting 2% at $79 beats one converting 4% at $29, and only revenue per visitor shows that.",
      },
      {
        question: "How many conversions do I need before trusting a change?",
        answer:
          "More than most people assume. At 20 conversions, one more or fewer moves the rate by 5% relative, so a fortnight of small-site traffic can produce a difference that looks decisive and is noise.",
      },
    ],
    related: [
      { label: "CTR calculator", href: "/free-tools/ctr-calculator" },
      { label: "Plausible visitors in the notch", href: "/sources/plausible/visitors" },
      { label: "What is bounce rate?", href: "/library/bounce-rate" },
    ],
  },

  {
    slug: "ctr-calculator",
    name: "CTR calculator",
    category: "marketing",
    heading: "Click-through rate calculator",
    description:
      "Work out click-through rate from clicks and impressions, for search results, ads and email alike.",
    lede: "Clicks divided by impressions. How often the people who saw you chose you.",
    formula: "CTR = clicks ÷ impressions",
    fields: [
      { key: "impressions", label: "Impressions", unit: "count", default: 48200, min: 0 },
      { key: "clicks", label: "Clicks", unit: "count", default: 1640, min: 0 },
      {
        key: "target",
        label: "Target CTR",
        unit: "percent",
        default: 5,
        min: 0,
        step: 0.1,
        help: "Shows how many more clicks the same impressions would need.",
      },
    ],
    outputs: [
      { key: "ctr", label: "Click-through rate", unit: "percent", primary: true },
      { key: "gap", label: "Clicks needed to hit target", unit: "count" },
      { key: "perThousand", label: "Clicks per thousand impressions", unit: "count" },
    ],
    compute: (v) => {
      const ratio = safeDivide(v("clicks"), v("impressions"));
      if (ratio === null) return { ctr: null, gap: null, perThousand: null };
      const needed = v("impressions") * (v("target") / 100);
      return {
        ctr: ratio * 100,
        gap: Math.max(0, Math.round(needed - v("clicks"))),
        perThousand: ratio * 1000,
      };
    },
    sections: [
      {
        heading: "It is a ratio over the period, not an average of days",
        paragraphs: [
          "Sum the clicks, sum the impressions, divide. Do not average the daily rates: that weights a Sunday with ten impressions the same as a Monday with ten thousand.",
          "This is why a correct CTR chart and its headline disagree. Each point is that day's ratio; the headline is the period's.",
        ],
      },
      {
        heading: "Why a falling CTR is often good",
        paragraphs: [
          "CTR falls when a page starts ranking for broader terms. More impressions at worse positions means a smaller share convert, while the page earns more clicks in total. The percentage fell and the outcome improved.",
          "It also falls when a search engine answers the query on the results page, or when a rich result appears above you. Neither is something you did.",
          "The case where a falling CTR is genuinely bad is when impressions and position are both steady and clicks drop. That isolates the one variable you control: what your result says.",
        ],
      },
      {
        heading: "In search, position explains most of it",
        paragraphs: [
          "Roughly half the variation in a page's search CTR is explained by where it ranks. Comparing two pages' CTRs without comparing their positions is close to meaningless.",
          "A page at position two with a low CTR is a snippet problem: the title or the description is not answering the query somebody typed. A page at position fifteen with a low CTR is a ranking problem, and rewriting the title will not fix it.",
        ],
      },
      {
        heading: "CTR in email and ads",
        paragraphs: [
          "The same ratio, with different denominators. Email CTR is usually clicks over delivered, while click-to-open rate uses opens instead, and open tracking has been unreliable since Apple began pre-fetching images.",
          "Ad platforms count an impression when the ad is served, whether or not it entered the viewport. Viewable CTR, where available, is the more honest number.",
        ],
      },
    ],
    faq: [
      {
        question: "How do you calculate click-through rate?",
        answer:
          "Divide clicks by impressions and multiply by a hundred. 1,640 clicks from 48,200 impressions is a CTR of about 3.4%.",
      },
      {
        question: "Is a falling CTR bad?",
        answer:
          "Often not. CTR falls when a page starts ranking for broader terms, so more impressions at worse positions convert at a lower rate while total clicks rise. It is genuinely bad only when impressions and position are steady and clicks fall.",
      },
      {
        question: "What is a good CTR?",
        answer:
          "It depends almost entirely on position and context. A top search result for a branded query can exceed 30%, while position ten often sits near 1%. Compare a page against its own history and against its position, not against a published average.",
      },
      {
        question: "Why does my CTR headline not match the chart?",
        answer:
          "Because each chart point is that day's ratio and the headline is the period's clicks divided by the period's impressions. Averaging the daily rates would weight a quiet day equally with a busy one.",
      },
      {
        question: "Can I compare CTR between two pages?",
        answer:
          "Only alongside their positions. Roughly half the variation in search CTR is explained by rank, so a comparison that ignores position is close to meaningless.",
      },
    ],
    related: [
      { label: "What is click-through rate?", href: "/library/click-through-rate" },
      { label: "Search Console CTR in the notch", href: "/sources/google-search-console/ctr" },
      {
        label: "How to get average position and CTR from Search Console",
        href: "/blog/get-average-position-and-ctr-from-search-console",
      },
    ],
  },

  {
    slug: "rpm-calculator",
    name: "RPM calculator",
    category: "marketing",
    heading: "RPM calculator for creators",
    description:
      "Work out revenue per mille from your earnings and views, and see how it differs from the CPM advertisers are quoted.",
    lede: "Revenue per thousand views, counting every view. Not CPM, which counts only monetised ad impressions and is always higher.",
    formula: "RPM = revenue ÷ views × 1,000",
    fields: [
      {
        key: "revenue",
        label: "Estimated revenue in the period",
        unit: "money",
        default: 142000,
        min: 0,
      },
      { key: "views", label: "Views in the period", unit: "count", default: 86000, min: 0 },
      {
        key: "monetised",
        label: "Share of views that showed an ad",
        unit: "percent",
        default: 55,
        min: 0,
        help: "Used to show the implied CPM. Most channels sit between 40% and 70%.",
      },
    ],
    outputs: [
      { key: "rpm", label: "RPM", unit: "money", primary: true },
      {
        key: "cpm",
        label: "Implied CPM",
        unit: "money",
        help: "Revenue over monetised impressions only, before the platform's share.",
      },
      { key: "perView", label: "Revenue per view", unit: "money" },
    ],
    compute: (v) => {
      const rpmRaw = safeDivide(v("revenue") * 1000, v("views"));
      const monetisedViews = v("views") * (v("monetised") / 100);
      // Grossed back up by the platform's usual 55/45 creator split.
      const cpmRaw = safeDivide((v("revenue") / 0.55) * 1000, monetisedViews);
      const perViewRaw = safeDivide(v("revenue"), v("views"));
      return {
        rpm: rpmRaw === null ? null : Math.round(rpmRaw),
        cpm: cpmRaw === null ? null : Math.round(cpmRaw),
        perView: perViewRaw,
      };
    },
    sections: [
      {
        heading: "RPM and CPM measure opposite sides",
        paragraphs: [
          "RPM divides your revenue, after the platform's share, by every view. CPM divides what advertisers paid, before the platform's share, by monetised ad impressions only.",
          "Both differences push the same way, which is why CPM is always substantially higher than RPM on every channel. The gap is structural and is not a sign of anything wrong.",
          "Comparing your RPM against somebody's quoted CPM and concluding you are underpaid is the most common mistake in creator revenue discussions.",
        ],
      },
      {
        heading: "Compute it over the whole period",
        paragraphs: [
          "RPM is a ratio, so it has the trap every ratio has. Total revenue divided by total views, not the average of daily RPM values.",
          "A quiet day with one high-value view produces an enormous daily RPM and should contribute almost nothing to the period figure. Averaging the points weights it equally with a day of ten thousand views.",
        ],
      },
      {
        heading: "What moves RPM",
        paragraphs: [
          "Audience country, more than anything else. The same video earns several times more from viewers in high-advertising-spend markets than from the global average.",
          "Video length, because longer videos carry more ad slots. Subject matter, because advertisers pay very differently for finance than for gaming. And format: a shift towards short-form usually lowers RPM sharply, because short-form monetises from a shared pool rather than per-view.",
          "Seasonality is large and predictable. Advertising budgets peak in the final quarter and collapse in January, so a January RPM drop is the calendar rather than your channel.",
        ],
      },
      {
        heading: "About the implied CPM here",
        paragraphs: [
          "The CPM figure above grosses your revenue back up by the platform's usual creator split and divides by the share of views you said carried an ad. It is an estimate of what advertisers paid, derived from what you received.",
          "It will not match the CPM in your analytics exactly, because the split and the monetised share are both approximations. Use it to understand the shape of the gap, not as a figure to quote.",
        ],
      },
    ],
    faq: [
      {
        question: "How do you calculate RPM?",
        answer:
          "Divide your revenue by your views and multiply by a thousand. Compute it over the whole period rather than averaging daily values, or a quiet day with one high-value view distorts the figure.",
      },
      {
        question: "What is the difference between RPM and CPM?",
        answer:
          "RPM is your revenue after the platform's share, divided by every view. CPM is what advertisers paid before the platform's share, divided by monetised ad impressions only. CPM is always much higher, and the gap is structural rather than a problem.",
      },
      {
        question: "Why is my RPM so low?",
        answer:
          "Usually audience country, video length or format. Viewers in lower-advertising-spend markets earn far less per view, shorter videos carry fewer ad slots, and short-form monetises from a shared pool rather than per view.",
      },
      {
        question: "Why did my RPM drop in January?",
        answer:
          "Advertising budgets peak in the final quarter and fall sharply in the new year. A January drop of a third or more is normal seasonality rather than anything about your channel.",
      },
      {
        question: "Should I track RPM or CPM?",
        answer:
          "RPM. It is the only one that answers what a view is worth to you. CPM describes advertiser demand in your niche and tells you nothing about your own earnings.",
      },
    ],
    related: [
      { label: "RPM against CPM", href: "/library/rpm-vs-cpm" },
      { label: "YouTube RPM in the notch", href: "/sources/youtube/rpm" },
      {
        label: "How to read estimated revenue and RPM from YouTube Analytics",
        href: "/blog/read-estimated-revenue-and-rpm-from-youtube-analytics",
      },
    ],
  },

  {
    slug: "stripe-fee-calculator",
    name: "Stripe fee calculator",
    category: "payments",
    heading: "Stripe fee calculator",
    description:
      "Work out what you keep after payment processing fees, and what to charge to receive a specific amount net.",
    lede: "A percentage plus a fixed amount, taken per successful charge. The fixed part is what makes small transactions expensive.",
    formula: "Fee = (amount × percentage) + fixed fee",
    fields: [
      { key: "amount", label: "Charge amount", unit: "money", default: 2900, min: 0 },
      {
        key: "percent",
        label: "Percentage fee",
        unit: "percent",
        default: 2.9,
        min: 0,
        step: 0.1,
        help: "Editable because the rate differs by country, card type and whether the card is domestic.",
      },
      { key: "fixed", label: "Fixed fee per charge", unit: "money", default: 30, min: 0 },
    ],
    outputs: [
      { key: "net", label: "You receive", unit: "money", primary: true },
      { key: "fee", label: "Processing fee", unit: "money" },
      { key: "effective", label: "Effective rate", unit: "percent" },
      {
        key: "gross",
        label: "Charge this to net the amount above",
        unit: "money",
        help: "The amount to charge so that the figure you entered arrives after fees.",
      },
    ],
    compute: (v) => {
      const rate = v("percent") / 100;
      const fee = Math.round(v("amount") * rate + v("fixed"));
      const net = v("amount") - fee;
      const effective = safeDivide(fee, v("amount"));
      // Inverted: what to charge so `amount` survives the fee.
      const grossRaw = safeDivide(v("amount") + v("fixed"), 1 - rate);
      return {
        net,
        fee,
        effective: effective === null ? null : effective * 100,
        gross: grossRaw === null ? null : Math.round(grossRaw),
      };
    },
    sections: [
      {
        heading: "The fixed fee is what hurts",
        paragraphs: [
          "At 2.9% plus 30 cents, a $100 charge loses 3.2% and a $3 charge loses 13%. The percentage is the same; the fixed fee is not, and on small amounts it dominates completely.",
          "This is the whole argument for annual plans and for bundling. One $190 charge a year costs far less in fees than twelve $19 charges, and the difference goes straight to your margin.",
        ],
      },
      {
        heading: "Rates are not one number",
        paragraphs: [
          "The percentage above is editable because the real rate depends on where you are, where the card is from, and what kind of card it is. International cards usually add roughly a percentage point, currency conversion adds another, and American Express is often priced differently.",
          "Charge an international customer in their own currency and you can pay the international fee and the conversion fee on the same transaction. Check your own Stripe pricing page for your country rather than trusting any published figure, including this one.",
        ],
      },
      {
        heading: "What else comes out",
        paragraphs: [
          "Disputes carry a fixed fee that is not returned even if you win, and the disputed amount is held meanwhile. A product with a high dispute rate can lose more to dispute fees than to the disputes themselves.",
          "Refunds do not return the original processing fee in most regions, so a refunded $100 charge costs you the $3.20 permanently. That is worth knowing before offering a generous refund policy on a low-margin product.",
          "Payouts to another country, instant payouts and some subscription tooling carry their own charges. The fee above is per-charge processing only.",
        ],
      },
      {
        heading: "Charging to net a specific amount",
        paragraphs: [
          "The last figure inverts the calculation: what to charge so that the amount you entered actually arrives. It is the amount plus the fixed fee, divided by one minus the rate.",
          "Adding the fee percentage to your price does not work, because the fee then applies to the larger amount too. At 2.9% plus 30 cents, netting exactly $29 means charging $30.18, not $29.84.",
        ],
      },
    ],
    faq: [
      {
        question: "How do you calculate Stripe fees?",
        answer:
          "Multiply the charge by the percentage rate and add the fixed fee. At 2.9% plus 30 cents, a $29 charge costs $1.14 in fees and you receive $27.86.",
      },
      {
        question: "Why do small charges lose more to fees?",
        answer:
          "Because of the fixed fee. At 2.9% plus 30 cents, a $100 charge loses 3.2% while a $3 charge loses 13%. The percentage is identical; the fixed component dominates small amounts.",
      },
      {
        question: "How much should I charge to receive a specific amount?",
        answer:
          "Add the fixed fee, then divide by one minus the percentage rate. Netting exactly $29 at 2.9% plus 30 cents means charging $30.18. Simply adding the percentage to your price does not work, because the fee then applies to the larger amount too.",
      },
      {
        question: "Do I get the processing fee back on a refund?",
        answer:
          "In most regions, no. A refunded $100 charge still costs you the original processing fee permanently, which is worth knowing before offering a generous refund policy on a low-margin product.",
      },
      {
        question: "Are international card fees higher?",
        answer:
          "Usually yes, by roughly a percentage point, and currency conversion adds another. Charging an international customer in their own currency can incur both on the same transaction. Check your own country's pricing page rather than any published figure.",
      },
      {
        question: "Does annual billing save on payment fees?",
        answer:
          "Yes, meaningfully. One charge a year pays the fixed fee once rather than twelve times. On a $19 monthly plan that is roughly $3.30 a year of pure margin, before counting the reduced failed-payment churn.",
      },
    ],
    related: [
      { label: "Stripe in the MacBook notch", href: "/sources/stripe" },
      { label: "MRR calculator", href: "/free-tools/mrr-calculator" },
      {
        label: "How to get Stripe revenue for a date range",
        href: "/blog/stripe-revenue-for-a-date-range",
      },
    ],
  },
];
