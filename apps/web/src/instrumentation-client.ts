import posthog from "posthog-js";

/**
 * PostHog, started before the app hydrates.
 *
 * `instrumentation-client.ts` rather than a provider component in the root
 * layout: Next runs this ahead of hydration, so the first pageview is not
 * racing React, and the whole tree stays a server component. A provider would
 * have made the root layout a client boundary for the sake of one `useEffect`.
 *
 * Absent key is a no-op rather than an error. That is every local run and
 * every preview build, and a site that will not boot without an analytics
 * token is worse than one that is not measured.
 */
const key = process.env.NEXT_PUBLIC_POSTHOG_KEY;

if (key) {
  posthog.init(key, {
    api_host: process.env.NEXT_PUBLIC_POSTHOG_HOST ?? "https://us.i.posthog.com",
    /*
     * Stated outright rather than inherited from a dated `defaults` preset.
     * The preset is a moving target by design, and the one behaviour this
     * integration depends on is worth reading off the call.
     *
     * `history_change` follows App Router navigation through the history API.
     * The hand-rolled alternative is a `useSearchParams` effect, and on this
     * site that is a trap: reading search params opts a route into dynamic
     * rendering, and almost every page here is statically generated.
     * Measuring the site would have quietly stopped it being a static site.
     */
    capture_pageview: "history_change",
    /*
     * No person record for somebody who only ever reads the marketing pages.
     * They become a person when they sign in, which is where
     * `app/layout.tsx` identifies them by the same user id the Worker uses.
     */
    person_profiles: "identified_only",
  });
}
