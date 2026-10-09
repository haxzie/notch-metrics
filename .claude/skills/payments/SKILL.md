---
name: payments
description: Set up, change or debug DodoPayments billing — product ids, API and webhook keys, the checkout and portal routes, the subscription webhook, the trial and grace windows, and changing a price. Use when a checkout returns 503, a webhook is rejected with 401 or silently ignored, somebody paid but is still on the trial plan, or a plan's price needs to change.
---

# Billing

Two plans, both the same product tier. Prices live in `packages/schemas/src/billing.ts`
as `PLANS`, in **integer minor units**, and the website, the billing pane and
the desktop upsell all read them from there.

| Plan    | `id`         | Price | Dodo var                         |
| ------- | ------------ | ----- | -------------------------------- |
| Monthly | `pro`        | $14   | `DODOPAYMENT_MONTHLY_PRODUCT_ID` |
| Yearly  | `pro_annual` | $79   | `DODOPAYMENT_YEARLY_PRODUCT_ID`  |

Seven-day trial, no card, then payment. There is no free tier.

## First-time setup

1. In the Dodo dashboard create **two subscription products** — one monthly at
   $14, one yearly at $79. Copy both product ids.
2. Put them in `apps/api/wrangler.jsonc`. They are **not secret** — they appear
   in every checkout URL — so they are `vars`, and the `production` env needs
   its own copy because named environments inherit nothing.
3. Put the two secrets in `apps/api/.dev.vars` for local work and in the Worker
   for production:

   ```bash
   wrangler secret put DODOPAYMENT_API_KEY --env production
   wrangler secret put DODOPAYMENT_WEBHOOK_SECRET --env production
   ```

   The webhook secret is the `whsec_…` **signing** key under Developer →
   Webhooks, not the API key. Mixing them up gives a 401 on every delivery.

4. Point the Dodo webhook at `https://api.notchmetrics.com/v1/webhooks/dodo`
   and subscribe to `subscription.active`, `subscription.renewed`,
   `subscription.on_hold`, `subscription.failed`, `subscription.cancelled` and
   `subscription.expired`.
5. Leave `DODOPAYMENT_MODE` as `test` until a real card has gone through once.

**`DODOPAYMENT_MODE` is explicit, never inferred from the key.** A live key
against the test host answers `401`, which reads as a bad key and costs an
hour before anyone suspects the host.

## Changing a price

Change `PLANS` **and** the product in Dodo, in the same change. Dodo holds the
authoritative amount; `PLANS` is what we quote. If they disagree, the user
reads one number and is charged another.

Existing subscribers keep the price they signed up at — Dodo does not reprice
an active subscription — so a change only affects new checkouts. Say so in the
changelog rather than letting somebody discover it in a support thread.

## The one thing that writes a plan

`apps/api/src/routes/webhooks/dodo.ts`, and nothing else. Not the checkout
route, not `/v1/me`, not a migration. If a user's plan is wrong, the question
is always "what did the webhook do", and the answer is in `webhook_event`.

Three properties worth not breaking:

- **The `webhook_event` insert _is_ the idempotency check**, and it happens
  strictly after signature verification. Reversed, an unsigned POST could
  insert an id and suppress the real delivery that follows it.
- **The signature is over the raw bytes.** Never `JSON.parse` then
  re-stringify before verifying — key order and whitespace change and every
  delivery fails.
- **A failed apply deletes the event row before returning 500**, otherwise
  Dodo's retry is swallowed as a duplicate and the plan never lands.

## Symptom → cause

| Symptom                                     | Cause                                                                                                                                                                                                                                                     |
| ------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Checkout button returns **503**             | A product id var is empty. That is deliberate — a checkout against a missing id is a 404 on Dodo's side that reads to the user as a broken product.                                                                                                       |
| Checkout 503s and the log says **422**      | Dodo rejected the payload, not the id. Its body names the offending field and `call()` now carries it into the error. `billing.country` is required on every subscription — omitting it gives a 422 whose message is only "a field has an invalid value". |
| Every webhook **401**s                      | `DODOPAYMENT_WEBHOOK_SECRET` is the API key, or the body was re-serialised before verifying.                                                                                                                                                              |
| Webhook returns `{ok: true, ignored: true}` | The event carried no `metadata.userId`. Only subscriptions created through our checkout have it — one created by hand in the dashboard never will.                                                                                                        |
| Paid, but still on `trial`                  | Check `webhook_event` for the delivery. No row means it never arrived: the endpoint URL or the event subscriptions are wrong.                                                                                                                             |
| Access continues after cancelling           | Correct. `subscription.cancelled` sets the status but not the plan — access runs to `currentPeriodEnd`, because cutting it at the moment of cancellation is a refund request.                                                                             |
| Access continues after a failed payment     | Correct, for `GRACE_DAYS`. A card expiring on a Friday should not blank a dashboard over the weekend.                                                                                                                                                     |

## Testing locally

`wrangler dev` has no public URL, so a real delivery cannot reach it:

```bash
cloudflared tunnel --url http://localhost:8787
```

Point a test-mode webhook at the tunnel. The alternative is meeting the
signature path for the first time in production.

`apps/api/test/dodo-webhook.test.ts` covers the parts worth pinning: a bad
signature writes **no** `webhook_event` row, a replay is a duplicate, and skew
beyond five minutes is rejected.
