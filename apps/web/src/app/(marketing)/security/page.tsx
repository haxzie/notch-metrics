import type { Metadata } from "next";
import Link from "next/link";
import { JsonLd } from "@/components/JsonLd";
import { LegalPage, LegalSection } from "@/components/marketing/LegalPage";
import { FaqSection, type FaqEntry } from "@/lib/faq";
import { faqPageJsonLd, graph } from "@/lib/jsonld";
import { LEGAL_UPDATED } from "@/lib/legal";
import { absoluteUrl } from "@/lib/site";

export const metadata: Metadata = {
  title: "Security",
  description:
    "How Notch Metrics encrypts your provider keys, what the Mac app can and cannot see, and what a custom metric is allowed to reach.",
  alternates: { canonical: "/security" },
  openGraph: { url: absoluteUrl("/security"), title: "Security" },
};

const CONTACT = "security@notchmetrics.com";

const FAQ: FaqEntry[] = [
  {
    question: "Does the Notch Metrics Mac app hold my Stripe key?",
    answer:
      "No. The Mac app never receives a provider credential. Notch Metrics calls Stripe from its server and hands your Mac a normalised series of numbers, so a stolen Mac yields no key.",
  },
  {
    question: "What happens to my API key if the database leaks?",
    answer:
      "Nothing readable. Every credential is encrypted with its own data key, which is itself wrapped by a key-encryption key held outside the database. A full database dump contains ciphertext and wrapped keys, and nothing that can unwrap them.",
  },
  {
    question: "Can one Notch Metrics user decrypt another user's credentials?",
    answer:
      "No. Your user id, the integration, the provider and the key version are bound into each ciphertext as additional authenticated data. A row copied between accounts fails to decrypt rather than decrypting into somebody else's dashboard.",
  },
  {
    question: "Are custom metrics sandboxed?",
    answer:
      "No, and Notch Metrics says so plainly. A custom metric is contained: it declares the hosts it may call and nothing else is reachable. It still runs as you, like a script you wrote. Read what your agent writes before you enable it.",
  },
  {
    question: "What permissions does a read-only key need?",
    answer:
      "The least that returns your numbers. Stripe needs a restricted key with read access to Charges and Subscriptions, not a full secret key. Each connector's page on notchmetrics.com/sources names what its own key has to reach.",
  },
  {
    question: "How do I report a security problem in Notch Metrics?",
    answer:
      "Email security@notchmetrics.com with enough detail to reproduce it. Reports are read by a person, and a fix ships as a signed, notarised update rather than waiting for a release window.",
  },
];

/**
 * Written from what the code actually does, not from a template.
 *
 * Every claim here has a counterpart in `apps/api` or `apps/mac`. The
 * containment wording in the custom-metrics section is deliberate and
 * required: calling that a sandbox would be the one false sentence on the
 * page, and it is the sentence somebody would act on.
 */
export default function Security() {
  return (
    <>
      <JsonLd data={graph(faqPageJsonLd(FAQ, "/security"))} />
      <LegalPage
        title="Security"
        summary="To show your MRR, Notch Metrics has to hold a key that can read your Stripe account. There is no version of this product that avoids that, so this page is specific about what is held, how it is wrapped, and which attacks the design actually stops."
        updated={LEGAL_UPDATED.security}
      >
        <LegalSection title="One key per connection">
          <p>
            Credentials are never encrypted with a single site-wide key. Each connection, meaning
            one row for one provider belonging to one user, gets its own data key. That key encrypts
            the credential. A key-encryption key, held as a platform secret entirely outside the
            database, encrypts the data key.
          </p>
          <p>
            The database stores the ciphertext and the wrapped key, and nothing that can unwrap it.
            A leaked database dump is inert: there is no key material in it.
          </p>
        </LegalSection>

        <LegalSection title="A row copied between users does not decrypt">
          <p>
            Your user id, the integration, the provider and the key version are bound into every
            ciphertext as additional authenticated data. Change any of them and decryption fails
            rather than succeeding against the wrong account.
          </p>
          <p>
            That is what turns a database write into a dead end. An attacker who can insert rows
            still cannot move one credential onto another account and read it back.
          </p>
        </LegalSection>

        <LegalSection title="Your Mac never sees a provider key">
          <p>
            Metrics are cloud-proxied. The server calls Stripe, Polar, Shopify or whichever provider
            you connected, normalises the result, and sends the Mac app a series of numbers. The app
            holds no provider credential, so a lost or stolen Mac yields none.
          </p>
          <p>
            Remove an integration and its encrypted credential is deleted with it. There is no
            second copy anywhere to clean up afterwards.
          </p>
        </LegalSection>

        <LegalSection title="Ask for the smallest key that works">
          <p>
            Every connector page names the least access its key needs. Stripe works from a
            restricted key with read access to Charges and Subscriptions, which cannot move money
            even if it leaked. Each connector declares the hosts it is allowed to call, and the
            server refuses anything outside that list.
          </p>
          <p>
            <Link href="/sources">Every source and what its key has to reach</Link>.
          </p>
        </LegalSection>

        <LegalSection title="Custom metrics are contained, not sandboxed">
          <p>
            A custom metric is one JavaScript module in Application Support, run by a runner built
            into the app. It declares the hosts it may call, and nothing else is reachable. Its
            secrets live in the macOS Keychain and reach the runner on stdin, and a metric with a
            key written into it is refused.
          </p>
          <p>
            It still runs as you, with your permissions, like a script you wrote. That is
            containment, and it is not a sandbox. Read what your agent writes before you enable it.
          </p>
        </LegalSection>

        <LegalSection title="Updates are verified twice">
          <p>
            The app checks a downloaded update against both its SHA-256 and its Developer ID
            signature before installing it. The hash alone proves only that the file matches what
            the manifest said, and the manifest arrives from the same place the file does.
          </p>
          <p>
            Every build is signed and notarised. A release that turns out to be bad is withheld
            server-side with one deploy, rather than waiting for anyone to notice.
          </p>
        </LegalSection>

        <LegalSection title="Reporting a problem">
          <p>
            Email <a href={`mailto:${CONTACT}`}>{CONTACT}</a> with enough detail to reproduce the
            issue. Reports are read by a person. A fix ships as a signed, notarised update rather
            than waiting for a release window.
          </p>
        </LegalSection>

        <FaqSection entries={FAQ} />
      </LegalPage>
    </>
  );
}
