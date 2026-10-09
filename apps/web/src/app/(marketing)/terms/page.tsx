import type { Metadata } from "next";
import { LegalPage, LegalSection } from "@/components/marketing/LegalPage";
import { LEGAL_UPDATED } from "@/lib/legal";

export const metadata: Metadata = {
  title: "Terms",
  description: "The terms you agree to when you use Notch Metrics.",
  alternates: { canonical: "/terms" },
};

const CONTACT = "support@notchmetrics.com";

export default function Terms() {
  return (
    <LegalPage
      title="Terms of service"
      summary="The agreement between you and Notch Metrics when you create an account, install the app, or subscribe. It is short because the product is."
      updated={LEGAL_UPDATED.terms}
    >
      <LegalSection title="The service">
        <p>
          Notch Metrics (&ldquo;we&rdquo;) provides a macOS app and an accompanying web service that
          read figures from business tools you connect and display them on your Mac. By creating an
          account or using the app you agree to these terms. If you are using Notch Metrics on
          behalf of a company, you confirm you can bind that company to them.
        </p>
      </LegalSection>

      <LegalSection title="Your account">
        <p>
          You sign in with a Google or GitHub account and are responsible for what happens under
          yours. Keep your sign-in secure, and revoke any device you no longer control from the app.
          One account is for one person; a team needs one account per member.
        </p>
      </LegalSection>

      <LegalSection title="Your connections and data">
        <p>
          When you connect a service you are giving us permission to read from it on your behalf,
          and you confirm you are allowed to do that. Use read-only or restricted keys wherever the
          service offers them. We only ever read; nothing we do writes to, changes or spends from a
          connected service. You can disconnect any service at any time, which deletes the
          credential.
        </p>
        <p>
          The numbers remain yours. We take no rights over them beyond what is needed to fetch,
          cache and show them to you, as described in our <a href="/privacy">privacy policy</a>.
        </p>
      </LegalSection>

      <LegalSection title="Trial, subscription and billing">
        <p>
          New accounts get a seven-day trial of everything. After that, Notch Metrics is a paid
          subscription, billed monthly or yearly at the price shown on the site when you subscribe.
          There is no free tier.
        </p>
        <p>
          Subscriptions are sold by Dodo Payments, our merchant of record. Dodo Payments handles the
          charge, applicable taxes, invoices and refunds under{" "}
          <a href="https://dodopayments.com/terms" target="_blank" rel="noreferrer">
            its own terms
          </a>
          . Your subscription renews automatically until you cancel it, which you can do from the
          billing portal at any time; cancelling stops the next renewal and keeps access to the end
          of the period already paid for. If a renewal fails, access continues for a short grace
          period while the payment is retried, then pauses until it succeeds.
        </p>
        <p>
          We may change prices. A change applies to you from your next renewal after we have given
          you at least thirty days&rsquo; notice.
        </p>
      </LegalSection>

      <LegalSection title="Custom metrics and the MCP server">
        <p>
          You can write your own metrics, by hand or with an AI agent through our MCP server. These
          run on your own Mac, with the network access and secrets you give them. They are your
          code: we are not responsible for what they do, what they fetch, or what they cost you at
          the services they call. Contain them accordingly; they are not sandboxed.
        </p>
      </LegalSection>

      <LegalSection title="Acceptable use">
        <p>You agree not to:</p>
        <ul>
          <li>connect a service or account you do not have the right to read from;</li>
          <li>
            use Notch Metrics to probe, overload or interfere with our service or anyone
            else&rsquo;s;
          </li>
          <li>reverse-engineer the app or the API beyond what the law allows;</li>
          <li>resell access to Notch Metrics, or share one account between several people.</li>
        </ul>
        <p>We may suspend an account that does any of these, after warning you where we can.</p>
      </LegalSection>

      <LegalSection title="The app">
        <p>
          We grant you a personal, non-transferable licence to install and use the Notch Metrics app
          on Macs you control, for as long as your account is in good standing. The app checks for
          updates automatically and we recommend installing them; older versions may stop working as
          the service changes.
        </p>
      </LegalSection>

      <LegalSection title="Third-party services">
        <p>
          The services you connect are not ours. Their availability, accuracy and terms are theirs.
          A figure we show is only as right as the service that gave it to us, and we describe how
          each one is calculated in the app so you can judge it. We are not liable for decisions you
          make on the basis of a number shown in the notch.
        </p>
      </LegalSection>

      <LegalSection title="Warranty and liability">
        <p>
          Notch Metrics is provided as is. We work to keep it accurate and available, but we do not
          promise that it will be uninterrupted or error-free. To the fullest extent the law allows,
          our total liability to you for anything arising from these terms or the service is limited
          to the amount you paid us in the twelve months before the claim, and we are not liable for
          indirect or consequential loss, including lost profits or lost data. Nothing here limits
          liability that cannot be limited by law.
        </p>
      </LegalSection>

      <LegalSection title="Ending things">
        <p>
          You can stop using Notch Metrics at any time; cancel your subscription and, if you want
          your data gone, email <a href={`mailto:${CONTACT}`}>{CONTACT}</a> and we will delete your
          account. We may end or suspend the service for an account that breaches these terms, and
          may discontinue the service as a whole with at least thirty days&rsquo; notice, refunding
          any prepaid period that we do not deliver.
        </p>
      </LegalSection>

      <LegalSection title="Changes to these terms">
        <p>
          We may update these terms. The date at the top shows the current version. For a material
          change we will tell you in the app or by email before it applies; continuing to use Notch
          Metrics after that is acceptance.
        </p>
      </LegalSection>

      <LegalSection title="Law and contact">
        <p>
          These terms are governed by the laws of India, and any dispute goes to the courts there,
          unless the consumer law where you live gives you something better, in which case it
          applies. Write to us at <a href={`mailto:${CONTACT}`}>{CONTACT}</a>.
        </p>
      </LegalSection>
    </LegalPage>
  );
}
