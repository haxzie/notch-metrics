import type { Metadata } from "next";
import { LegalPage, LegalSection } from "@/components/marketing/LegalPage";

export const metadata: Metadata = {
  title: "Privacy",
  description: "What Notch Metrics collects, why, where it lives, and how to get rid of it.",
};

const CONTACT = "support@notchmetrics.com";

/**
 * Written from what the code actually does, not from a template. Every
 * claim here has a counterpart in apps/api or apps/mac; when one of those
 * changes, this page is part of the change.
 */
export default function Privacy() {
  return (
    <LegalPage
      title="Privacy policy"
      summary="Notch Metrics shows your business numbers in your Mac's notch. To do that it holds the keys to the services those numbers come from, so this page is specific about what it keeps, where, and for how long."
      updated="2026-10-09"
    >
      <LegalSection title="Who we are">
        <p>
          Notch Metrics is operated by Notch Metrics (&ldquo;we&rdquo;). This policy covers the
          website at notchmetrics.com, the API that serves it, and the Notch Metrics app for macOS.
          Questions about it go to <a href={`mailto:${CONTACT}`}>{CONTACT}</a>.
        </p>
      </LegalSection>

      <LegalSection title="What we collect">
        <p>
          <strong>Your account.</strong> You sign in with Google or GitHub. From that we keep the
          email address, display name and profile picture the sign-in provider gives us, the time
          zone and preferred currency you choose, and your plan and trial dates. We do not keep a
          password.
        </p>
        <p>
          <strong>Your devices.</strong> Each Mac you sign in from gets a device token so the app
          can talk to the API. We store only a hash of that token, with the device&rsquo;s label and
          when it was last used. You can revoke any device from the app at any time.
        </p>
        <p>
          <strong>Your connections.</strong> When you connect a service, we store the credential
          that lets us read from it: an API key you paste, or the access and refresh tokens the
          service issues after you authorise us. Each one is encrypted with a key unique to that
          connection, bound to your account, before it is written anywhere. We also keep the
          service&rsquo;s name for the account, its currency, which metrics it offers, and when it
          last worked.
        </p>
        <p>
          <strong>Your numbers.</strong> The figures we fetch for your widgets are cached on our
          servers for a short time, from minutes to an hour depending on the metric, so the notch
          opens instantly and we do not hammer the services you connected. Some widgets list recent
          events rather than a figure, such as recent payments. Those rows can include your own
          customers&rsquo; names or email addresses as the payment provider reports them, and they
          sit in the same short-lived cache.
        </p>
        <p>
          <strong>Billing.</strong> Subscriptions are sold by Dodo Payments as merchant of record.
          We receive and store the subscription status, its identifiers and its renewal dates. Card
          details go to Dodo Payments and never reach us.
        </p>
        <p>
          <strong>Operational logs.</strong> Our hosting provider records requests to the API and
          the website, and our error logs record failures with credentials and secrets redacted
          before they are written. These are kept briefly and used only to keep the service running.
        </p>
        <p>
          <strong>What we do not collect.</strong> There are no third-party analytics or advertising
          trackers on the website or in the app. The app does not record what you do on your Mac.
          Custom metrics you write run on your own machine, and any secrets you give them stay
          there.
        </p>
      </LegalSection>

      <LegalSection title="Why we collect it">
        <p>
          Everything above exists to do one thing: fetch the numbers you asked for from the services
          you connected, and show them to you. We also use it to run your subscription, to keep the
          service secure, and to answer you when you write to us. We do not sell it, rent it, or use
          it to build advertising profiles.
        </p>
      </LegalSection>

      <LegalSection title="Google user data">
        <p>
          Connecting Google Analytics or Google Search Console asks for read-only access to those
          products. We use that access only to read the reports behind the widgets you add, and to
          list your properties so you can choose one. We do not transfer Google user data to anyone
          else except as needed to provide the service, and we do not use it for advertising or to
          train machine-learning models.
        </p>
        <p>
          Notch Metrics&rsquo; use and transfer of information received from Google APIs adheres to
          the{" "}
          <a
            href="https://developers.google.com/terms/api-services-user-data-policy"
            target="_blank"
            rel="noreferrer"
          >
            Google API Services User Data Policy
          </a>
          , including the Limited Use requirements. You can withdraw that access at any time from
          your Google account&rsquo;s connected apps, or by disconnecting the connection in Notch
          Metrics.
        </p>
      </LegalSection>

      <LegalSection title="Where it lives">
        <p>
          The API, its database and the download mirror run on Cloudflare. Data is encrypted in
          transit everywhere. Credentials are encrypted at rest as described above, with the
          encryption keys held as secrets separate from the database, so a copy of the database
          alone does not reveal a single key.
        </p>
        <p>
          The services you connect — Stripe, Dodo Payments, Google, GitHub and the others listed on
          the site — receive requests from us carrying your credential for that service and nothing
          about your other connections.
        </p>
      </LegalSection>

      <LegalSection title="How long we keep it">
        <ul>
          <li>
            <strong>Cached numbers:</strong> minutes to hours, then replaced or swept.
          </li>
          <li>
            <strong>Connection credentials:</strong> until you disconnect the connection, which
            deletes them, or delete your account.
          </li>
          <li>
            <strong>Device tokens:</strong> until you revoke the device or delete your account.
          </li>
          <li>
            <strong>Account and billing records:</strong> for as long as you have an account, and
            afterwards only what we must keep for tax and accounting.
          </li>
          <li>
            <strong>Logs:</strong> briefly, on a rolling basis.
          </li>
        </ul>
      </LegalSection>

      <LegalSection title="Your choices">
        <p>
          You can disconnect any service, revoke any device, and change your time zone and currency
          from inside the app. To export or delete your account and everything attached to it, email{" "}
          <a href={`mailto:${CONTACT}`}>{CONTACT}</a> from the address you signed in with and we
          will do it promptly. Depending on where you live, you may also have rights to access,
          correct, restrict or object to our use of your data, and to complain to a supervisory
          authority. Writing to us is the fastest way to exercise any of them.
        </p>
      </LegalSection>

      <LegalSection title="Children">
        <p>
          Notch Metrics is a business tool and is not directed at anyone under 16. We do not
          knowingly collect data from children; if you believe we have, tell us and we will delete
          it.
        </p>
      </LegalSection>

      <LegalSection title="Changes">
        <p>
          When this policy changes we update the date at the top. If a change is material to how we
          treat your data, we will say so in the app or by email before it takes effect.
        </p>
      </LegalSection>
    </LegalPage>
  );
}
