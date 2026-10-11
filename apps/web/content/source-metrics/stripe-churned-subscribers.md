---
lede: >-
  Churned subscribers are cancellations in the window, counted by when the subscription ended rather than when somebody clicked cancel.
---

## Cancelled, not expiring

Stripe has two shapes of cancellation. One ends the subscription immediately.
The other sets `cancel_at_period_end`, leaving the subscription active until
the paid period runs out. Notch Metrics counts a subscription when it
actually ends, so somebody who cancels today on an annual plan appears in
this number next year.

That is the honest bucket for a churn figure, and it is the one that lines up
with the active subscribers widget. It also means today's churn count tells
you nothing about today's cancellations, which is a real limitation.

## A count, not a rate

This is the number of subscriptions lost, not a percentage. For a churn rate,
divide by the active subscribers at the start of the window, which is a
calculation the notch deliberately does not do: the denominator everybody
means by "churn rate" differs by company, and guessing which one you meant
would produce a number you could not defend.
