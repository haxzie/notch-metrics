import type { Tool } from "./types.ts";
import { safeDivide } from "./types.ts";

export const SAAS_TOOLS: Tool[] = [
  {
    slug: "mrr-calculator",
    name: "MRR calculator",
    category: "saas",
    heading: "MRR calculator",
    description:
      "Work out monthly recurring revenue from your monthly and annual subscribers, with annual plans normalised to a month.",
    lede: "Monthly recurring revenue is the value of your active subscriptions normalised to one month. Annual plans divide by twelve.",
    formula:
      "MRR = (monthly subscribers × monthly price) + (annual subscribers × annual price ÷ 12)",
    fields: [
      { key: "monthlyCount", label: "Monthly subscribers", unit: "count", default: 120, min: 0 },
      { key: "monthlyPrice", label: "Average monthly price", unit: "money", default: 1900, min: 0 },
      { key: "annualCount", label: "Annual subscribers", unit: "count", default: 40, min: 0 },
      {
        key: "annualPrice",
        label: "Average annual price",
        unit: "money",
        default: 19000,
        min: 0,
        help: "The full yearly amount, not a twelfth of it.",
      },
    ],
    outputs: [
      { key: "mrr", label: "MRR", unit: "money", primary: true },
      { key: "arr", label: "ARR", unit: "money", help: "MRR × 12." },
      {
        key: "arpu",
        label: "Average revenue per user",
        unit: "money",
        help: "MRR divided by every subscriber, monthly and annual.",
      },
    ],
    compute: (v) => {
      // Minor units throughout, rounded once at each money boundary.
      const fromMonthly = v("monthlyCount") * v("monthlyPrice");
      const fromAnnual = (v("annualCount") * v("annualPrice")) / 12;
      const mrr = Math.round(fromMonthly + fromAnnual);
      const customers = v("monthlyCount") + v("annualCount");
      const arpu = safeDivide(mrr, customers);
      return { mrr, arr: mrr * 12, arpu: arpu === null ? null : Math.round(arpu) };
    },
    sections: [
      {
        heading: "How MRR is calculated",
        paragraphs: [
          "Take every active subscription, convert its price to a monthly amount, and add them up. A monthly plan contributes its own price. An annual plan contributes a twelfth of the yearly amount, because that is what it is worth per month.",
          "A quarterly plan divides by three, and a weekly plan multiplies by 52 and divides by 12. That last one catches people: a month averages 4.345 weeks, so treating it as four undercounts weekly plans by about eight per cent.",
        ],
      },
      {
        heading: "What this calculator leaves out",
        paragraphs: [
          "Trials. A trial is revenue nobody has agreed to pay yet, so most definitions exclude it. If you want a figure that includes them, add the trialling subscribers to the monthly count and know that you have made that choice.",
          "Discounts. A customer on a permanent 20% coupon contributes 20% less than their list price. Use an average price that already reflects your discounting, or your MRR will read high by whatever share of the book is discounted.",
          "Tax. If you sell through a merchant of record such as Paddle or Lemon Squeezy, the VAT they collect is not yours. Use the amount before tax.",
          "Usage-based charges. Metered revenue is not recurring in the sense MRR means, because next month's amount is not knowable from this month's. Most people exclude it and report it separately.",
        ],
      },
      {
        heading: "A worked example",
        paragraphs: [
          "Say 120 subscribers pay $19 a month, and 40 pay $190 a year. The monthly half contributes $2,280. The annual half contributes 40 × $190 ÷ 12, which is $633.33. MRR is $2,913.33, and ARR is $34,959.96.",
          "Notice that the 40 annual subscribers brought in $7,600 of cash the day they signed, and only $633 of MRR. That gap is why MRR and cash collected are different numbers and should never be used interchangeably.",
        ],
      },
      {
        heading: "Why your number will differ from your provider's",
        paragraphs: [
          "Stripe, Polar, Paddle and RevenueCat each compute MRR their own way, and each is defensible. They differ on trials, on past-due subscriptions, on whether fixed-amount coupons are prorated across line items, and on tax.",
          "A few per cent of disagreement is normal. What matters is that your figure is consistent with itself over time and that you can say exactly what it counts when somebody asks.",
        ],
      },
    ],
    faq: [
      {
        question: "How do you calculate MRR?",
        answer:
          "Add up every active subscription normalised to one month. A monthly plan contributes its price, an annual plan contributes a twelfth of the yearly amount, and a quarterly plan contributes a third. Trials are usually excluded because they are revenue nobody has agreed to pay yet.",
      },
      {
        question: "Does MRR include annual plans?",
        answer:
          "Yes, divided by twelve. An annual plan at $1,188 contributes $99 of MRR. The full $1,188 is cash you collected, not monthly recurring revenue, and keeping the two apart is the point of the metric.",
      },
      {
        question: "Is MRR the same as last month's revenue?",
        answer:
          "No. A month with many annual renewals brings in a lot of cash without changing MRR, because the book did not grow. MRR is what you are owed per month right now; revenue is what actually arrived in a window.",
      },
      {
        question: "Should trials count towards MRR?",
        answer:
          "Usually not. A trial is revenue nobody has committed to, so including it overstates the book and makes MRR drop whenever a cohort of trials lapses. Most providers exclude trials from their own MRR figure for the same reason.",
      },
      {
        question: "How do you convert a weekly plan to MRR?",
        answer:
          "Multiply the weekly price by 52 and divide by 12. A month averages 4.345 weeks, so the common shortcut of multiplying by four undercounts weekly plans by roughly eight per cent.",
      },
    ],
    related: [
      { label: "What is MRR?", href: "/library/mrr" },
      { label: "ARR calculator", href: "/free-tools/arr-calculator" },
      {
        label: "How to calculate MRR from the Stripe API",
        href: "/blog/calculate-mrr-from-the-stripe-api",
      },
      { label: "Stripe MRR in the notch", href: "/sources/stripe/mrr" },
    ],
  },

  {
    slug: "arr-calculator",
    name: "ARR calculator",
    category: "saas",
    heading: "ARR calculator",
    description:
      "Convert monthly recurring revenue to annual recurring revenue, and see what a growth rate does to it over the next year.",
    lede: "Annual recurring revenue is monthly recurring revenue multiplied by twelve. Resisting the urge to make it more interesting is most of the discipline.",
    formula: "ARR = MRR × 12",
    fields: [
      { key: "mrr", label: "Current MRR", unit: "money", default: 291333, min: 0 },
      {
        key: "growth",
        label: "Monthly growth rate",
        unit: "percent",
        default: 6,
        min: -100,
        step: 0.1,
        help: "Compounded over twelve months for the projection below.",
      },
    ],
    outputs: [
      { key: "arr", label: "ARR", unit: "money", primary: true },
      {
        key: "projected",
        label: "ARR in twelve months",
        unit: "money",
        help: "At the growth rate above, compounded. A projection, not a commitment.",
      },
      { key: "added", label: "Net new ARR", unit: "money" },
    ],
    compute: (v) => {
      const arr = Math.round(v("mrr") * 12);
      const multiplier = Math.pow(1 + v("growth") / 100, 12);
      const projected = Number.isFinite(multiplier) ? Math.round(arr * multiplier) : null;
      return { arr, projected, added: projected === null ? null : projected - arr };
    },
    sections: [
      {
        heading: "ARR is MRR times twelve, and nothing else",
        paragraphs: [
          "The two carry identical information, so choosing between them is about audience rather than accuracy. MRR moves visibly week to week, which makes it the operating number. ARR is what investors, acquirers and benchmarks speak in.",
          "Use whichever your reader thinks in, and never put both on the same chart.",
        ],
      },
      {
        heading: "Three ways ARR gets inflated",
        paragraphs: [
          "Annualising a good month. Taking December's revenue and multiplying by twelve is a forecast, not a run rate, and December probably contained one-off sales that will not repeat.",
          "Counting one-off revenue. Setup fees, consulting, lifetime deals and one-time purchases are real money and they are not recurring.",
          "Counting bookings. A signed annual contract that starts next quarter is a booking. Adding it to ARR today reports revenue you have not begun to earn.",
          "The test is simple: if everything stopped changing today, would this amount arrive over the next twelve months? If not, it is not ARR.",
        ],
      },
      {
        heading: "ARR is not cash",
        paragraphs: [
          "A business at $120k ARR selling annual plans may have collected most of that already. The same business selling monthly has collected a twelfth of it.",
          "Identical ARR, completely different runway. ARR describes the book; it says nothing about when the money arrives, which is the thing that decides whether you make payroll.",
        ],
      },
      {
        heading: "About the projection",
        paragraphs: [
          "The twelve-month figure compounds your monthly growth rate, which is the right arithmetic and the wrong model for most businesses. Growth rates decay as the base grows, so a constant rate flatters the far end of any projection.",
          "Treat it as a sanity check on what a rate implies rather than as a plan. If the number looks implausible, the rate is probably not sustainable for twelve months.",
        ],
      },
    ],
    faq: [
      {
        question: "How do you calculate ARR?",
        answer:
          "Multiply monthly recurring revenue by twelve. Anything smoothed, forecast or annualised differently is not ARR, it is a projection wearing a metric's name.",
      },
      {
        question: "Is ARR just MRR times 12?",
        answer:
          "Yes. The two carry identical information, so the choice between them is about who is reading rather than about accuracy.",
      },
      {
        question: "Can I include one-off sales in ARR?",
        answer:
          "No. Setup fees, consulting, lifetime deals and one-time purchases are real money and they are not recurring. If everything stopped changing today and the amount would not arrive again over the next twelve months, it is not ARR.",
      },
      {
        question: "Is ARR the same as revenue?",
        answer:
          "No. ARR is the annualised value of the subscriptions you hold right now. Revenue is what actually arrived in a period, including one-off sales and excluding subscriptions that have not billed yet.",
      },
      {
        question: "Should I report ARR or MRR?",
        answer:
          "MRR while you are building, because it moves visibly week to week and you can act on it. ARR when talking to investors, acquirers or benchmarks, because that is the unit they think in.",
      },
    ],
    related: [
      { label: "What is ARR?", href: "/library/arr" },
      { label: "MRR calculator", href: "/free-tools/mrr-calculator" },
      { label: "Rule of 40 calculator", href: "/free-tools/rule-of-40-calculator" },
    ],
  },

  {
    slug: "churn-rate-calculator",
    name: "Churn rate calculator",
    category: "saas",
    heading: "Churn rate calculator",
    description:
      "Work out customer churn and retention from the customers you started with and the ones you lost, with the annual equivalent.",
    lede: "Churn is what you lose. The count is easy; the denominator is where everybody disagrees.",
    formula: "Churn rate = customers lost ÷ customers at the start of the period",
    fields: [
      { key: "start", label: "Customers at start of period", unit: "count", default: 500, min: 0 },
      { key: "lost", label: "Customers lost in the period", unit: "count", default: 15, min: 0 },
      {
        key: "gained",
        label: "New customers in the period",
        unit: "count",
        default: 60,
        min: 0,
        help: "Not used in the headline rate. Shown so you can see net movement.",
      },
    ],
    outputs: [
      { key: "churn", label: "Monthly churn rate", unit: "percent", primary: true },
      { key: "retention", label: "Retention rate", unit: "percent" },
      {
        key: "annual",
        label: "Annualised churn",
        unit: "percent",
        help: "Compounded over twelve months, not multiplied by twelve.",
      },
      { key: "net", label: "Net customer change", unit: "count" },
    ],
    compute: (v) => {
      const rate = safeDivide(v("lost"), v("start"));
      if (rate === null)
        return { churn: null, retention: null, annual: null, net: v("gained") - v("lost") };
      const churn = rate * 100;
      // Compounded, not multiplied: 5% a month is 46% a year, not 60%.
      const annual = (1 - Math.pow(1 - rate, 12)) * 100;
      return { churn, retention: 100 - churn, annual, net: v("gained") - v("lost") };
    },
    sections: [
      {
        heading: "The denominator is the argument",
        paragraphs: [
          "There is no single correct churn rate, because there is no agreed denominator. Customers at the start of the period is the classic, and it ignores anybody who joined and left inside the period. Start plus new counts those fast churners and always produces a lower number. Some people use the average of start and end, which is smoother and harder to explain.",
          "This calculator uses customers at the start, which is the most common. Pick one, write it down beside the number, and never change it quietly. A churn rate whose definition moved is worse than no churn rate, because the trend line still looks real.",
        ],
      },
      {
        heading: "Why annualised churn is not twelve times monthly",
        paragraphs: [
          "Losing 5% a month does not lose 60% a year. Each month's churn applies to a base that already shrank, so the right arithmetic compounds: one minus 0.95 to the twelfth power, which is about 46%.",
          "Multiplying by twelve overstates churn at every rate, and the error grows as the rate does. At 10% monthly the multiplied figure is 120%, which is not a number that can exist.",
        ],
      },
      {
        heading: "Customer churn against revenue churn",
        paragraphs: [
          "This calculator counts customers. Revenue churn counts money, and the two can point in opposite directions: losing ten customers on your cheapest plan is a bad month for customer churn and barely registers in revenue churn, while losing one enterprise account is the reverse.",
          "Net revenue retention goes further and subtracts expansion revenue from existing customers. If upgrades outweigh cancellations it goes above 100%, which is the shape every subscription business wants.",
        ],
      },
      {
        heading: "Voluntary and involuntary churn",
        paragraphs: [
          "Voluntary churn is somebody deciding to leave. Fixing it means fixing the product, the price or the fit, which is slow.",
          "Involuntary churn is a card expiring, a bank declining, a payment retrying until the provider gives up. The customer never decided anything. For many businesses it is between a fifth and two fifths of all churn, and most of it is recoverable with better dunning. It is worth measuring separately before you conclude anything about your product.",
        ],
      },
    ],
    faq: [
      {
        question: "How do you calculate churn rate?",
        answer:
          "Divide the customers you lost in a period by the customers you had at the start of it, then multiply by a hundred. Losing 15 of 500 customers is a 3% monthly churn rate.",
      },
      {
        question: "How do you annualise a monthly churn rate?",
        answer:
          "Compound it, do not multiply it. A 5% monthly churn rate is about 46% a year, not 60%, because each month's loss applies to a base that already shrank. Multiplying by twelve overstates churn at every rate.",
      },
      {
        question: "What is a good churn rate for SaaS?",
        answer:
          "It depends entirely on who you sell to. Businesses selling to other businesses on annual contracts often sit below 1% a month, while consumer and small-business products commonly run 3% to 7%. Compare yourself to your own trend before comparing to a benchmark.",
      },
      {
        question: "What is the difference between customer churn and revenue churn?",
        answer:
          "Customer churn counts people and revenue churn counts money, and they can move in opposite directions. Losing ten customers on your cheapest plan is high customer churn; losing one enterprise account is high revenue churn and barely shows in the other.",
      },
      {
        question: "What is involuntary churn?",
        answer:
          "Churn caused by a failed payment rather than a decision: an expired card, a declined bank, a retry schedule that gives up. It is often a fifth to two fifths of all churn and most of it is recoverable with better dunning.",
      },
    ],
    related: [
      { label: "What is churn rate?", href: "/library/churn-rate" },
      { label: "Customer lifetime value calculator", href: "/free-tools/ltv-calculator" },
      {
        label: "How to measure Stripe subscriber churn",
        href: "/blog/measure-stripe-subscriber-churn",
      },
    ],
  },

  {
    slug: "ltv-calculator",
    name: "LTV calculator",
    category: "saas",
    heading: "Customer lifetime value calculator",
    description:
      "Estimate customer lifetime value from average revenue per user, monthly churn and gross margin, with the expected lifetime in months.",
    lede: "Lifetime value is what an average customer is worth before they leave. It falls straight out of your churn rate, which is why churn is the number to fix.",
    formula: "LTV = ARPU × gross margin ÷ monthly churn rate",
    fields: [
      {
        key: "arpu",
        label: "Average revenue per user, monthly",
        unit: "money",
        default: 2900,
        min: 0,
      },
      {
        key: "churn",
        label: "Monthly churn rate",
        unit: "percent",
        default: 3,
        min: 0.01,
        step: 0.1,
      },
      {
        key: "margin",
        label: "Gross margin",
        unit: "percent",
        default: 80,
        min: 0,
        help: "Revenue left after the cost of serving the customer. Leave at 100 for a revenue-only figure.",
      },
    ],
    outputs: [
      { key: "ltv", label: "Lifetime value", unit: "money", primary: true },
      { key: "lifetime", label: "Expected lifetime", unit: "months" },
      { key: "revenueLtv", label: "Lifetime revenue, before margin", unit: "money" },
    ],
    compute: (v) => {
      const rate = v("churn") / 100;
      const lifetime = safeDivide(1, rate);
      if (lifetime === null) return { ltv: null, lifetime: null, revenueLtv: null };
      const revenueLtv = Math.round(v("arpu") * lifetime);
      return {
        ltv: Math.round(revenueLtv * (v("margin") / 100)),
        lifetime,
        revenueLtv,
      };
    },
    sections: [
      {
        heading: "Lifetime is one over churn",
        paragraphs: [
          "If 3% of customers leave each month, the average customer stays about 33 months. That is simply one divided by the churn rate, and it is the whole reason churn matters so much: halving churn doubles lifetime, and doubling lifetime doubles lifetime value.",
          "No marketing change moves LTV as much as a retention change does.",
        ],
      },
      {
        heading: "Use gross margin, not revenue",
        paragraphs: [
          "A lifetime value built on revenue tells you what a customer pays. A lifetime value built on gross margin tells you what they are worth, which is the number you can compare against what it cost to acquire them.",
          "Gross margin here means revenue minus the cost of serving that customer: hosting, payment fees, support, any third-party API you pay per seat. Software businesses commonly sit between 70% and 90%. Leave the field at 100% if you want the revenue figure and know that is what you have.",
        ],
      },
      {
        heading: "Where this estimate breaks down",
        paragraphs: [
          "It assumes churn is constant, and it is not. Churn is almost always highest in the first weeks and falls as a cohort matures, so a single blended rate understates the lifetime of customers who made it past the early cliff and overstates everybody else.",
          "It also ignores expansion. If customers upgrade over time, their revenue grows while they stay, and a flat ARPU misses that entirely. A business with real expansion should look at net revenue retention instead, where expansion is the point.",
          "For anything consequential, measure lifetime value by cohort against actual revenue collected. This formula is a planning estimate, not an accounting result.",
        ],
      },
      {
        heading: "The ratio that matters",
        paragraphs: [
          "LTV on its own means little. Divided by customer acquisition cost it becomes the number people actually use, and a widely repeated rule of thumb is that a healthy business wants LTV to be at least three times CAC.",
          "Treat that ratio as a prompt rather than a target. A ratio far above three often means you are underspending on acquisition rather than running a great business.",
        ],
      },
    ],
    faq: [
      {
        question: "How do you calculate customer lifetime value?",
        answer:
          "Divide average monthly revenue per user by your monthly churn rate, then multiply by gross margin. At $29 ARPU, 3% monthly churn and 80% margin, lifetime value is about $773 over an expected lifetime of 33 months.",
      },
      {
        question: "How is expected customer lifetime calculated?",
        answer:
          "One divided by the monthly churn rate. A 3% monthly churn rate implies an average lifetime of about 33 months. This is why halving churn doubles lifetime value.",
      },
      {
        question: "Should LTV use revenue or gross margin?",
        answer:
          "Gross margin, if you intend to compare it against acquisition cost. A revenue-based figure tells you what a customer pays, not what they are worth after hosting, payment fees and support.",
      },
      {
        question: "What is a good LTV to CAC ratio?",
        answer:
          "Three to one is the commonly repeated rule of thumb. Treat it as a prompt rather than a target: a ratio far above three often means you are underspending on acquisition rather than running an unusually good business.",
      },
      {
        question: "Why is my LTV estimate too optimistic?",
        answer:
          "Because the formula assumes constant churn, and churn is almost always highest in the first weeks and falls as a cohort matures. A single blended rate flatters customers who have not yet reached the early cliff. Measure by cohort for anything consequential.",
      },
    ],
    related: [
      { label: "Churn rate calculator", href: "/free-tools/churn-rate-calculator" },
      { label: "CAC payback calculator", href: "/free-tools/cac-payback-calculator" },
      { label: "What is churn rate?", href: "/library/churn-rate" },
    ],
  },

  {
    slug: "cac-payback-calculator",
    name: "CAC payback calculator",
    category: "saas",
    heading: "CAC payback period calculator",
    description:
      "Work out how many months it takes to earn back what you spent acquiring a customer, on gross margin rather than on revenue.",
    lede: "Payback is how long your money is tied up before a customer has paid for themselves. It decides how fast you can grow without running out of cash.",
    formula: "Payback months = CAC ÷ (ARPU × gross margin)",
    fields: [
      {
        key: "spend",
        label: "Sales and marketing spend in the period",
        unit: "money",
        default: 1200000,
        min: 0,
      },
      { key: "customers", label: "New customers acquired", unit: "count", default: 90, min: 0 },
      {
        key: "arpu",
        label: "Average revenue per user, monthly",
        unit: "money",
        default: 2900,
        min: 0,
      },
      { key: "margin", label: "Gross margin", unit: "percent", default: 80, min: 0 },
    ],
    outputs: [
      { key: "payback", label: "Payback period", unit: "months", primary: true },
      { key: "cac", label: "Customer acquisition cost", unit: "money" },
      { key: "monthly", label: "Gross profit per customer, monthly", unit: "money" },
    ],
    compute: (v) => {
      const cacRaw = safeDivide(v("spend"), v("customers"));
      if (cacRaw === null) return { payback: null, cac: null, monthly: null };
      const cac = Math.round(cacRaw);
      const monthly = Math.round(v("arpu") * (v("margin") / 100));
      return { payback: safeDivide(cac, monthly), cac, monthly };
    },
    sections: [
      {
        heading: "Why payback uses gross margin",
        paragraphs: [
          "A customer paying $29 a month does not give you $29 to recover your acquisition cost with. Hosting, payment fees and support come out first. At 80% gross margin they contribute $23.20 a month towards paying you back.",
          "Dividing acquisition cost by revenue rather than by gross profit understates payback by exactly the margin you forgot, which is usually a fifth.",
        ],
      },
      {
        heading: "What counts as acquisition cost",
        paragraphs: [
          "Everything you spent to get the customers, divided by the customers you got. That means advertising, content, sponsorships, tooling, and the salaries of everybody doing sales and marketing. Excluding salaries is the most common way to make this number look good, and it is the most expensive line in it for most teams.",
          "Fully loaded or not, be consistent. A payback period computed on ad spend alone is not comparable to one computed properly, including to your own figure from last quarter.",
        ],
      },
      {
        heading: "Why payback matters more than the LTV to CAC ratio",
        paragraphs: [
          "Lifetime value is a projection over years. Payback is a fact about the next few months, and it is the one that constrains how fast you can spend.",
          "A business with a twelve-month payback needs a year of cash for every cohort it buys. The same business at six months can reinvest twice as often from the same balance. Two businesses with identical LTV to CAC ratios can have completely different growth ceilings for this reason.",
        ],
      },
      {
        heading: "What is a good payback period",
        paragraphs: [
          "For businesses selling to other businesses, under twelve months is a common benchmark and under six is strong. Products sold to consumers or small businesses usually need to be faster, because churn is higher and a long payback may never actually complete.",
          "Sense-check it against your churn: if your average customer lifetime is shorter than your payback period, you are losing money on every customer you acquire, however good the ratio looks.",
        ],
      },
    ],
    faq: [
      {
        question: "How do you calculate CAC payback period?",
        answer:
          "Divide customer acquisition cost by monthly gross profit per customer, which is average revenue per user multiplied by gross margin. A $133.33 CAC against $23.20 of monthly gross profit is a payback period of about 5.8 months.",
      },
      {
        question: "Should CAC payback use revenue or gross margin?",
        answer:
          "Gross margin. A customer paying $29 a month does not hand you $29 towards recovering acquisition cost, because hosting, payment fees and support come out first. Using revenue understates payback by whatever your margin is.",
      },
      {
        question: "What should be included in customer acquisition cost?",
        answer:
          "Everything spent to acquire the customers in the period: advertising, content, sponsorships, tooling, and the salaries of everybody doing sales and marketing. Excluding salaries is the most common way to make the number look better than it is.",
      },
      {
        question: "What is a good CAC payback period?",
        answer:
          "For business-to-business products, under twelve months is a common benchmark and under six is strong. Consumer and small-business products usually need to be faster, because higher churn means a long payback may never complete.",
      },
      {
        question: "Why does payback matter more than LTV to CAC?",
        answer:
          "Because lifetime value is a projection over years and payback is a fact about the next few months. Payback decides how often you can reinvest the same cash, so two businesses with identical LTV to CAC ratios can have very different growth ceilings.",
      },
    ],
    related: [
      { label: "LTV calculator", href: "/free-tools/ltv-calculator" },
      { label: "Churn rate calculator", href: "/free-tools/churn-rate-calculator" },
    ],
  },

  {
    slug: "net-revenue-retention-calculator",
    name: "Net revenue retention calculator",
    category: "saas",
    heading: "Net revenue retention calculator",
    description:
      "Work out NRR and gross revenue retention from starting MRR, expansion, contraction and churn, with no new customers counted.",
    lede: "Net revenue retention is what last year's customers are worth this year. Above 100% means the business grows without selling to anybody new.",
    formula: "NRR = (starting MRR + expansion − contraction − churn) ÷ starting MRR",
    fields: [
      { key: "start", label: "MRR at start of period", unit: "money", default: 5000000, min: 0 },
      {
        key: "expansion",
        label: "Expansion MRR",
        unit: "money",
        default: 420000,
        min: 0,
        help: "Upgrades, extra seats and add-ons from existing customers.",
      },
      {
        key: "contraction",
        label: "Contraction MRR",
        unit: "money",
        default: 130000,
        min: 0,
        help: "Downgrades from customers who stayed.",
      },
      { key: "churned", label: "Churned MRR", unit: "money", default: 210000, min: 0 },
    ],
    outputs: [
      { key: "nrr", label: "Net revenue retention", unit: "percent", primary: true },
      {
        key: "grr",
        label: "Gross revenue retention",
        unit: "percent",
        help: "Expansion excluded. Never above 100%.",
      },
      { key: "ending", label: "Ending MRR from this cohort", unit: "money" },
    ],
    compute: (v) => {
      const ending = v("start") + v("expansion") - v("contraction") - v("churned");
      const nrr = safeDivide(ending, v("start"));
      const grr = safeDivide(v("start") - v("contraction") - v("churned"), v("start"));
      return {
        nrr: nrr === null ? null : nrr * 100,
        grr: grr === null ? null : grr * 100,
        ending,
      };
    },
    sections: [
      {
        heading: "New customers are deliberately excluded",
        paragraphs: [
          "Net revenue retention measures one cohort over time. Adding new customers to the numerator would let a good sales quarter hide a leaking product, which is exactly what the metric exists to prevent.",
          "That is why it is the number investors ask for. Growth can be bought; retention cannot.",
        ],
      },
      {
        heading: "Above 100% is the whole point",
        paragraphs: [
          "If expansion from existing customers outweighs what downgrades and cancellations took away, NRR goes above 100% and the business grows without selling to anybody new. That is sometimes called negative churn.",
          "It requires a product where customers naturally use more over time: more seats, more usage, more features. A flat single-price product essentially cannot get there, and that is a pricing decision rather than a retention failure.",
        ],
      },
      {
        heading: "Read it with gross revenue retention",
        paragraphs: [
          "Gross revenue retention excludes expansion, so it can never exceed 100%. It is the honest floor: what you keep before any upsell.",
          "The gap between the two tells you where your growth comes from. NRR at 110% with GRR at 85% means a lot of expansion papering over a lot of churn, which is a very different business from NRR at 110% with GRR at 97%, even though the headline is identical.",
        ],
      },
      {
        heading: "Pick a period and keep it",
        paragraphs: [
          "NRR is usually quoted annually, comparing a cohort to itself twelve months later. Monthly NRR is also used and is a much smaller number for the same business, because there has been less time for expansion.",
          "The two are not comparable. Label which one you are reporting, because a monthly figure quoted as if it were annual understates a business badly.",
        ],
      },
    ],
    faq: [
      {
        question: "How do you calculate net revenue retention?",
        answer:
          "Take starting MRR, add expansion, subtract contraction and churned MRR, then divide by starting MRR. New customers are excluded on purpose, because the metric measures one cohort over time.",
      },
      {
        question: "What is a good net revenue retention rate?",
        answer:
          "Above 100% means existing customers alone grow the business. Many strong business-to-business products sit between 110% and 130%. Products sold to consumers or small businesses rarely exceed 100% because there is less room to expand an account.",
      },
      {
        question: "What is the difference between NRR and gross revenue retention?",
        answer:
          "Gross revenue retention excludes expansion, so it can never exceed 100%. The gap between the two shows how much expansion is covering churn: NRR of 110% with GRR of 85% is a very different business from NRR of 110% with GRR of 97%.",
      },
      {
        question: "Why are new customers excluded from NRR?",
        answer:
          "Because including them would let a good sales quarter hide a leaking product. NRR measures what one cohort is worth over time, which is why growth can be bought and retention cannot.",
      },
      {
        question: "Is NRR measured monthly or annually?",
        answer:
          "Usually annually, comparing a cohort to itself twelve months later. Monthly NRR is also used and is a much smaller number for the same business, because there has been less time for expansion. The two are not comparable, so label which one you mean.",
      },
    ],
    related: [
      { label: "Churn rate calculator", href: "/free-tools/churn-rate-calculator" },
      { label: "MRR calculator", href: "/free-tools/mrr-calculator" },
      { label: "What is churn rate?", href: "/library/churn-rate" },
    ],
  },

  {
    slug: "rule-of-40-calculator",
    name: "Rule of 40 calculator",
    category: "saas",
    heading: "Rule of 40 calculator",
    description:
      "Add your growth rate to your profit margin and see whether a software business clears the Rule of 40 benchmark.",
    lede: "Growth rate plus profit margin. The idea is that a software business can trade one for the other, as long as the two together clear forty.",
    formula: "Rule of 40 = revenue growth rate % + profit margin %",
    fields: [
      {
        key: "growth",
        label: "Year-on-year revenue growth",
        unit: "percent",
        default: 45,
        min: -100,
        step: 0.1,
      },
      {
        key: "margin",
        label: "Profit margin",
        unit: "percent",
        default: -8,
        min: -100,
        step: 0.1,
        help: "Usually free cash flow margin or EBITDA margin. Negative is fine.",
      },
    ],
    outputs: [
      { key: "score", label: "Rule of 40 score", unit: "percent", primary: true },
      { key: "gap", label: "Distance from 40", unit: "percent" },
    ],
    compute: (v) => {
      const score = v("growth") + v("margin");
      return { score, gap: score - 40 };
    },
    sections: [
      {
        heading: "What the rule says",
        paragraphs: [
          "A software business growing 45% a year while burning 8% of revenue scores 37. One growing 15% with a 30% margin scores 45. The rule treats those as comparable, on the view that early growth is worth sacrificing profit for and that mature businesses should convert that growth into margin.",
          "The threshold of forty is a convention rather than a law. It became a benchmark because it is roughly where publicly traded software businesses separated into two groups.",
        ],
      },
      {
        heading: "Which margin to use",
        paragraphs: [
          "Free cash flow margin is the most common input, because it is hard to flatter. EBITDA margin is also used and usually produces a higher score for the same business, since it adds back costs that are genuinely cash leaving the building for most software companies.",
          "Net margin is rarely used, because non-cash charges swamp the signal at small scale. Whichever you pick, say which, and do not change it between quarters.",
        ],
      },
      {
        heading: "Where the rule misleads",
        paragraphs: [
          "It is designed for businesses at scale, and it breaks at small revenue. Growing from $100k to $300k is 200% growth, which clears forty while burning 160% of revenue. That is not a signal about anything.",
          "It also treats a point of growth as exactly equal to a point of margin, which the market plainly does not. High-growth businesses are usually valued well above a profitable slow-growing business with an identical score.",
          "And it says nothing about retention. A business can hit forty while losing customers fast, as long as it is replacing them faster. Read it alongside net revenue retention.",
        ],
      },
    ],
    faq: [
      {
        question: "What is the Rule of 40?",
        answer:
          "A benchmark for software businesses that adds the revenue growth rate to the profit margin. If the two together reach forty or more, the business is considered to be balancing growth and profitability well.",
      },
      {
        question: "Which margin should I use for the Rule of 40?",
        answer:
          "Free cash flow margin is the most common, because it is hard to flatter. EBITDA margin is also used and usually gives a higher score for the same business. Pick one, say which, and do not change it between quarters.",
      },
      {
        question: "Does the Rule of 40 apply to small startups?",
        answer:
          "Not usefully. At small revenue, growth percentages are enormous and clear forty while burning heavily. Growing from $100k to $300k is 200% growth, which passes while losing a lot of money and signals nothing.",
      },
      {
        question: "Is a high Rule of 40 score always good?",
        answer:
          "Not on its own. The rule treats a point of growth as equal to a point of margin, which the market does not, and it says nothing about retention. A business can clear forty while losing customers quickly, as long as it replaces them faster.",
      },
    ],
    related: [
      { label: "ARR calculator", href: "/free-tools/arr-calculator" },
      {
        label: "Net revenue retention calculator",
        href: "/free-tools/net-revenue-retention-calculator",
      },
    ],
  },
];
