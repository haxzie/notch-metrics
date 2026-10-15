import { PLANS, annualSavingPercent, formatPrice } from "@notch/schemas";
import { Check, Plus } from "./icons";
import { PlanPicker } from "./PlanPicker";

const INCLUDED = [
  "Every connector, with no per-integration charge",
  "As many widgets as fit, in the notch and in list view",
  "Custom metrics authored by your own coding agent over MCP",
  "Every Mac you sign in to, with your layout synced between them",
  "Signed, notarised updates for as long as you subscribe",
];

const FAQ: { q: string; a: string }[] = [
  {
    q: "How does the trial work?",
    a: "Sign in and you have seven days of everything, with no card on file. When the trial ends, your widgets stop updating until you subscribe. Nothing is deleted.",
  },
  {
    q: "Is there a free tier?",
    a: "No. Each metric is fetched and normalised by our servers on a schedule, and that costs money to run per account. The trial is there so you can decide with real numbers in your notch.",
  },
  {
    q: "Can I use it on more than one Mac?",
    a: "Yes. A subscription is per account, not per machine. Sign in on another Mac and your connections and layout are already there.",
  },
  {
    q: "What happens if I cancel?",
    a: "You keep access until the end of the period you have paid for. After that the app returns to the same state as an expired trial: installed, connected, and waiting.",
  },
  {
    q: "What happens if a payment fails?",
    a: "You keep access for a grace period while the card is retried. If it still fails after that, the plan drops to expired until billing is sorted out.",
  },
  {
    q: "Who handles payment?",
    a: "Checkout and your subscription are run by Dodo Payments. We never see your card number, and you can manage or cancel from the billing page at any time.",
  },
];

/**
 * The same questions, as structured data.
 *
 * Built from `FAQ` rather than written out again: a hand-kept copy of the
 * answers is a copy that eventually contradicts the page, and contradicting
 * the page is what gets structured data treated as spam rather than ignored.
 */
const FAQ_JSON_LD = {
  "@context": "https://schema.org",
  "@type": "FAQPage",
  mainEntity: FAQ.map((item) => ({
    "@type": "Question",
    name: item.q,
    acceptedAnswer: { "@type": "Answer", text: item.a },
  })),
};

/**
 * Pricing as a section of the home page rather than a page of its own. One
 * plan does not need a destination; it needs to be a scroll away from the
 * reason to buy it. `/pricing` still resolves, by redirecting here.
 */
export function PricingSection() {
  return (
    <section id="pricing" className="mx-auto max-w-5xl scroll-mt-28 px-6 pt-28">
      <header className="mx-auto max-w-2xl text-center">
        <p className="eyebrow">Pricing</p>
        <h2 className="mt-4 text-balance text-[2.5rem] font-bold leading-[1.02] tracking-[-0.03em] sm:text-[3.25rem]">
          Every connector. One <span className="accent">price</span>.
        </h2>
        <p className="text-ink/55 mx-auto mt-5 max-w-xl text-pretty text-[17px] leading-relaxed">
          Try it for a week with your real numbers, no card. Then{" "}
          {formatPrice(PLANS.pro.amount, "USD")} a month, or{" "}
          {formatPrice(PLANS.pro_annual.amount, "USD")} a year and keep {annualSavingPercent()}% of
          it.
        </p>
      </header>

      <div className="mx-auto mt-12 max-w-3xl">
        <PlanPicker />
      </div>

      <div className="mx-auto mt-14 max-w-3xl">
        <p className="eyebrow text-center">Every plan includes</p>
        <ul className="mt-6 grid gap-x-10 gap-y-3 sm:grid-cols-2">
          {INCLUDED.map((item) => (
            <li key={item} className="text-ink/75 flex items-start gap-3 text-[15px]">
              <Check className="mt-0.5 h-4 w-4 shrink-0 text-emerald-400" />
              {item}
            </li>
          ))}
        </ul>
        <p className="text-ink/35 mt-8 text-center text-xs">
          Prices in USD. Tax may apply at checkout. Payment handled by Dodo Payments.
        </p>
      </div>

      <div className="mx-auto mt-20 max-w-2xl">
        <script
          type="application/ld+json"
          // Our own strings, from the array above — not user input.
          dangerouslySetInnerHTML={{ __html: JSON.stringify(FAQ_JSON_LD) }}
        />
        <h3 className="text-center text-2xl font-semibold tracking-tight">Questions</h3>
        <div className="divide-ink/[0.07] border-ink/[0.07] mt-6 divide-y border-y">
          {FAQ.map((item) => (
            <details key={item.q} className="group">
              <summary className="text-ink/85 hover:text-ink flex cursor-pointer items-center justify-between gap-6 py-5 text-[15px] font-medium transition">
                {item.q}
                <Plus className="text-ink/40 h-4 w-4 shrink-0 transition group-open:rotate-45" />
              </summary>
              <p className="text-ink/55 text-pretty pb-6 text-[15px] leading-relaxed">{item.a}</p>
            </details>
          ))}
        </div>
      </div>
    </section>
  );
}
