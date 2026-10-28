import { env } from "cloudflare:test";
import { describe, expect, it, vi } from "vitest";
import { sendWelcome } from "../src/lib/email.ts";
import type { Env } from "../src/env.ts";

/** A stand-in for the Email Sending binding, recording what it was handed. */
function recorder() {
  const sent: EmailMessageBuilder[] = [];
  const EMAIL = {
    send: async (message: EmailMessageBuilder) => {
      sent.push(message);
      return { messageId: "msg_1" };
    },
  } as unknown as SendEmail;
  return { sent, env: { ...env, EMAIL } as Env };
}

describe("the welcome email", () => {
  it("comes from the address that answers replies", async () => {
    const { sent, env: configured } = recorder();
    await sendWelcome(configured, { email: "jane@example.com", name: "Jane Doe" });

    const message = sent[0];
    expect(message?.to).toBe("jane@example.com");
    expect(message?.from).toEqual({
      email: "musthaq@notchmetrics.com",
      name: "Musthaq from Notch Metrics",
    });
    // The email asks for a reply, so a no-reply sender would make it a lie.
    expect(message?.replyTo).toBe("musthaq@notchmetrics.com");
  });

  it("greets by first name only, and copes with no name at all", async () => {
    const { sent, env: configured } = recorder();
    await sendWelcome(configured, { email: "jane@example.com", name: "Jane Doe" });
    await sendWelcome(configured, { email: "no-name@example.com", name: null });
    await sendWelcome(configured, { email: "blank@example.com", name: "   " });

    expect(sent[0]?.text).toContain("Hi Jane,");
    // The product is "Notch Metrics". "NotchMetrics" appears nowhere else a
    // user can read, and an email is the one place nobody proofreads twice.
    expect(sent[0]?.text).not.toContain("NotchMetrics");
    // Google hands over a full name; "Hi Jane Doe," reads like a bank.
    expect(sent[0]?.text).not.toContain("Doe");
    // Email signup supplies no name, and "Hi ," is worse than no name.
    expect(sent[1]?.text).toContain("Hi there,");
    expect(sent[2]?.text).toContain("Hi there,");
  });

  it("carries both a text and an HTML body", async () => {
    // HTML-only scores worse with spam filters, and some clients show only
    // the text part.
    const { sent, env: configured } = recorder();
    await sendWelcome(configured, { email: "jane@example.com", name: "Jane" });

    expect(sent[0]?.text).toBeTruthy();
    expect(sent[0]?.html).toBeTruthy();
    expect(sent[0]?.subject).toBe("A quick hello");
  });

  it("keeps the subject out of marketing register", async () => {
    // "Welcome to <product>" is the subject line of every onboarding sequence
    // ever sent, and an email asking for a reply cannot read like one.
    const { sent, env: configured } = recorder();
    await sendWelcome(configured, { email: "jane@example.com", name: "Jane" });

    const subject = sent[0]?.subject ?? "";
    expect(subject).not.toMatch(/welcome|notch metrics|free|trial|get started/i);
    expect(subject.length).toBeLessThan(40);
  });

  it("keeps the copy inside the rules for anything a user reads", async () => {
    const { sent, env: configured } = recorder();
    await sendWelcome(configured, { email: "jane@example.com", name: "Jane" });

    // No exclamation check: the welcome line carries one on purpose. Em
    // dashes and American spellings are still wrong in anybody's voice.
    const body = `${sent[0]?.subject} ${sent[0]?.text}`;
    expect(body).not.toContain("—");
    expect(body).not.toMatch(/organiz|customiz|behavior|normaliz/i);
  });

  it("signs off with the name and the title as one block", async () => {
    const { sent, env: configured } = recorder();
    await sendWelcome(configured, { email: "jane@example.com", name: "Jane" });

    expect(sent[0]?.text).toContain("Musthaq\nCreator of Notch Metrics");
    // A newline inside a block has to survive as a `<br />`. Left as a bare
    // newline, HTML collapses it and the sign-off runs onto one line.
    expect(sent[0]?.html).toContain("Musthaq<br />Creator of Notch Metrics");
  });

  it("escapes a display name, so a name cannot inject markup", async () => {
    const { sent, env: configured } = recorder();
    await sendWelcome(configured, { email: "x@example.com", name: "<script>alert(1)</script>" });

    expect(sent[0]?.html).not.toContain("<script>");
    expect(sent[0]?.html).toContain("&lt;script&gt;");
  });

  it("does nothing at all when the binding is absent", async () => {
    // The state of every test run and of a dev stack. Signup must not fail
    // and nothing must be logged as an error.
    const errors = vi.spyOn(console, "error").mockImplementation(() => {});
    await expect(
      sendWelcome({ ...env, EMAIL: undefined } as Env, { email: "jane@example.com" }),
    ).resolves.toBeUndefined();
    expect(errors).not.toHaveBeenCalled();
    errors.mockRestore();
  });

  it("swallows a send failure, because a signup must not fail with it", async () => {
    const errors = vi.spyOn(console, "error").mockImplementation(() => {});
    const broken = {
      ...env,
      EMAIL: { send: async () => Promise.reject(new Error("unverified sender")) },
    } as unknown as Env;

    await expect(sendWelcome(broken, { email: "jane@example.com" })).resolves.toBeUndefined();
    expect(errors).toHaveBeenCalled();
    errors.mockRestore();
  });

  it("says so in production when the binding never made it into the config", async () => {
    // Otherwise the failure is completely silent: signups keep working and
    // nobody is ever greeted.
    const errors = vi.spyOn(console, "error").mockImplementation(() => {});
    await sendWelcome(
      { ...env, EMAIL: undefined, API_URL: "https://api.notchmetrics.com" } as Env,
      {
        email: "jane@example.com",
      },
    );

    expect(errors).toHaveBeenCalledOnce();
    errors.mockRestore();
  });
});
