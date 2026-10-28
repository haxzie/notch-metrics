import { logError } from "./redact.ts";
import { isProduction, type Env } from "../env.ts";

/**
 * Transactional email, sent through the Cloudflare Email Sending binding.
 *
 * A binding rather than a vendor SDK: this is one POST from inside the Worker,
 * and the binding needs no API key, so there is no secret to rotate and
 * nothing to leak.
 *
 * Nothing here is allowed to affect a request, for the same reason as
 * `slack.ts`: every call resolves, never rejects. A send that fails must cost
 * somebody a welcome email, never their account.
 *
 * The `from` domain has to be onboarded onto Email Sending before a single
 * message leaves — `wrangler email sending enable notchmetrics.com` — or every
 * send comes back as a 4xx naming an unverified sender.
 */

/** Replies are the point of the welcome email, so this must be a real inbox. */
const FROM = { email: "musthaq@notchmetrics.com", name: "Musthaq from Notch Metrics" } as const;

/**
 * Welcomes one new account.
 *
 * Deliberately plain text with a bare HTML twin: no logo, no template, no
 * tracking pixel. It asks for a reply, and a message that looks hand-typed
 * gets one. The HTML twin exists because an HTML-only message scores worse
 * with spam filters and a text-only one renders as a wall in some clients.
 */
export async function sendWelcome(
  env: Env,
  recipient: { email: string; name?: string | null },
): Promise<void> {
  const binding = env.EMAIL;
  if (!binding) {
    // Absent is the normal state of a test run and of a dev stack, and must
    // not be an error there. In production it means the binding never made it
    // into wrangler.jsonc, which is otherwise silent: signups keep working and
    // nobody is ever greeted.
    if (isProduction(env)) {
      logError("email.welcome", new Error("no EMAIL binding; welcome emails are not being sent"));
    }
    return;
  }

  const { subject, text, html } = welcome(firstName(recipient.name));

  try {
    await binding.send({
      to: recipient.email,
      from: FROM,
      replyTo: FROM.email,
      subject,
      text,
      html,
    });
  } catch (error) {
    logError("email.welcome", error);
  }
}

/**
 * The copy. British spelling, short sentences, no em dashes: `apps/web/COPY.md`
 * governs anything a user reads, and an email is read by a user.
 *
 * First person, because it is signed by a person and answered by one.
 *
 * The subject names no product and makes no offer. "Welcome to Notch Metrics"
 * is the subject line of every onboarding sequence ever sent, and it gets read
 * as one: archived unopened, or answered by nobody. The sender name carries
 * the context in the inbox row, so the subject does not have to. The body is
 * free to say welcome, because by then the message is open.
 *
 * The exclamation mark and the "we" are deliberate and are Musthaq's own
 * words. `COPY.md` bans both, and that ban holds for the site, where Notch
 * Metrics is the speaker. Here a person is, and a founder's note that obeys a
 * marketing style guide reads like marketing.
 */
function welcome(name: string): { subject: string; text: string; html: string } {
  const greeting = name === "" ? "Hi there," : `Hi ${name},`;
  const lines = [
    greeting,
    "Welcome to Notch Metrics! Super excited to have you as one of our early users.",
    "If you hit a bug, or you need a connector that is not there yet, just reply to this email. It comes to me.",
    // One block, broken by a single newline. A blank line between the name and
    // the title would read as two paragraphs, which is a letterhead; a sign-off
    // is one unit.
    "Musthaq\nCreator of Notch Metrics",
  ];
  return {
    subject: "A quick hello",
    // Blocks are separated by a blank line in text and by a `<p>` in HTML. A
    // newline *inside* a block has to become a `<br />`, or HTML collapses it
    // to a space and the sign-off runs onto one line.
    text: lines.join("\n\n"),
    html: lines.map((line) => `<p>${escapeHtml(line).replace(/\n/g, "<br />")}</p>`).join("\n"),
  };
}

/**
 * The first word of a display name, or "".
 *
 * Google hands over a full name and "Hi Musthaq Ahamad," reads like a bank.
 * A name can also be absent (email signup supplies none) or whitespace, and
 * "Hi ," is worse than no name at all.
 */
function firstName(name: string | null | undefined): string {
  return (name ?? "").trim().split(/\s+/)[0] ?? "";
}

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}
