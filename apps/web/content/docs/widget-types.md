---
title: The widget types
description: Seven shapes a tile draws its number with, what each one needs, and when it suits the metric.
summary: Sparkline, bars, gauge, split, ranked, ring and plain. What each needs.
section: widgets
order: 2
date: 2026-10-26
---

Seven shapes. Which ones a widget offers depends on what its metric answers,
so a tile never offers a shape it has no data for.

## Plain

The figure on its own, with the change beneath it.

Right for a number with no history worth drawing. A gauge needs a ceiling and
a sparkline needs points. A plain tile needs neither, so it is the shape that
always works.

## Sparkline

A line under the figure, one point per bucket across the window.

This is the default for a metric that answers a series. The line carries the
direction of travel, which the figure on its own cannot.

## Bars

One bar per bucket, over the same points a sparkline would use.

Suits a count that lands in discrete lumps. Deploys per day read as bars. A
balance over time reads as a line.

## Gauge

The figure inside a filled arc, drawn as a share of its maximum.

Only for a ratio, where the ceiling is 1.0 by definition. An arc on a count
would be filled to an arbitrary fraction of nothing. Cache hit rate and plan
usage are gauges.

A gauge needs no history, so it draws on a metric with no series at all.

## Split

One bar divided into coloured segments, with a key underneath.

For a breakdown that adds up to a whole. Spend by model, revenue by plan.
The key names as many segments as the tile has room for, with a dot in each
segment's colour. What does not fit is still in the bar.

## Ranked

A bar per category, largest first, each with its name above it.

The same data a split bar carries, read as a list. Pick this when the names
matter more than the proportions. Taller tiles show more rows.

## Ring

A ring with the total in the hole, one arc per category.

A ring carries the breakdown and the total in one shape. Slices too thin to
draw at their true width are widened to the smallest readable arc, so a
category that exists is always visible.

## Which shapes a metric offers

A metric declares one of four answers, and that decides the shapes.

| The metric answers       | Shapes offered         |
| ------------------------ | ---------------------- |
| One number for now       | Plain, gauge           |
| A number per bucket      | Sparkline, bars, plain |
| One total for the window | Plain, gauge           |
| Rows of categories       | Split, ranked, ring    |

Notch Metrics picks the suggested shape when you add the widget. A ratio
starts as a gauge, a list starts as ranked bars, anything with points starts
as a sparkline. Change it in the widget's settings whenever you like.
