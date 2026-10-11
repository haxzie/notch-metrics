---
title: "What is ARR?"
description: "Annual recurring revenue is MRR times twelve, and nothing else. What it is useful for, and the three ways people quietly inflate it."
date: 2026-10-11
author: Notch Metrics
tags: [arr, glossary, saas]
kind: glossary
term: Annual recurring revenue
faq:
  - question: What does ARR stand for?
    answer: >-
      Annual recurring revenue. It is monthly recurring revenue multiplied by
      twelve, and nothing else. The two carry identical information, so the
      choice between them is about audience rather than accuracy.
  - question: Is ARR just MRR times 12?
    answer: >-
      Yes. Anything smoothed, forecast or annualised differently is not ARR, it
      is a projection wearing a metric's name.
  - question: Can I include one-off sales in ARR?
    answer: >-
      No. Setup fees, consulting, lifetime deals and one-time purchases are real
      money and they are not recurring. The test is whether the amount would
      arrive over the next twelve months if everything stopped changing today.
  - question: Is ARR the same as cash in the bank?
    answer: >-
      No. A business at $120k ARR selling annual plans may have collected most
      of it already; the same business selling monthly has collected a twelfth.
      Identical ARR, completely different runway.
  - question: Should I report ARR or MRR?
    answer: >-
      MRR while you are building, because it moves visibly week to week. ARR
      when talking to investors, acquirers or benchmarks, because that is the
      unit they think in. Never put both on the same chart.
---

**Annual recurring revenue is monthly recurring revenue multiplied by
twelve.** That is the entire definition, and resisting the urge to make it
more interesting is most of the discipline.

## Why bother with it at all

ARR and [MRR](/library/mrr) carry exactly the same information, so the choice
between them is about audience rather than accuracy.

MRR is the operating number. It moves visibly week to week, which makes it
the one to watch while you are building.

ARR is the conversational number. Investors, acquirers and benchmarks all
speak in it, and "we are at $480k ARR" lands differently from "we are at
$40k MRR" despite being identical.

Use whichever your reader thinks in. Never put both on the same chart.

## The three ways ARR gets inflated

ARR is easy to overstate without saying anything untrue, which is why it is
worth knowing the moves.

**Annualising a good month.** Taking December's revenue, multiplying by
twelve, and calling it ARR. December included Black Friday one-off sales,
which are not recurring, and the figure is a forecast rather than a run rate.

**Counting one-off revenue.** Setup fees, consulting, lifetime deals and
one-time purchases are real money and they are not recurring. An ARR that
includes them is answering a different question.

**Counting bookings as revenue.** A signed annual contract starting next
quarter is a booking. Adding it to ARR today reports revenue you have not
begun to earn.

All three produce a number that is bigger and less useful. The test is
simple: if everything stopped changing today, would this amount arrive over
the next twelve months? If not, it is not ARR.

## ARR and cash are different things

A business at $120k ARR selling annual plans may have collected most of that
already. The same business selling monthly has collected a twelfth of it.

Identical ARR, completely different runway. ARR describes the book. It says
nothing about when the money arrives, which is the thing that decides whether
you make payroll.

## Why Notch Metrics reports MRR

Every revenue connector reports [MRR](/library/mrr) rather than ARR:
[Stripe](/sources/stripe/mrr), [Polar](/sources/polar/mrr),
[Paddle](/sources/paddle/mrr), [Dodo Payments](/sources/dodopayments/mrr),
[Lemon Squeezy](/sources/lemonsqueezy/mrr) and
[RevenueCat](/sources/revenuecat/mrr).

The reason is that MRR moves at a speed you can see. In the notch, a figure
that changes visibly during a good week is worth more than one that needs a
calculator to feel different. Multiply by twelve when somebody asks.
