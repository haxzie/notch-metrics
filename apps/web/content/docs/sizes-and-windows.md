---
title: Sizes and windows
description: The notch grid is six columns wide and four rows deep. How a tile spans it, and which windows a number answers.
summary: The six column grid, the four presets, and the five time windows.
section: widgets
order: 3
date: 2026-10-26
---

## The grid

The notch is six columns wide. It opens two rows deep and drags to four.

Six columns, so three tiles sit across the notch at two columns each. That is
the width a headline figure like $55,678 fits in.

A widget spans anything from one by one up to six by four. Drag the handle on
a tile's edge to resize it. Neighbours move along to make room.

## The presets

Four sizes are one click away in the widget's settings.

| Size | What it holds                                  |
| ---- | ---------------------------------------------- |
| 1x1  | A mark and a number                            |
| 2x1  | A name and a number                            |
| 2x2  | A name, a number and a chart                   |
| 6x2  | The full width, for a list or a long breakdown |

Every span in between is reachable by dragging.

## How size changes the layout

Size decides more than room.

A tile one row tall and three or more columns wide reads left to right. The
name sits on the left, the figure and the chart on the right. Stacked, that
tile left its right half empty.

Two columns stays stacked at one row tall. Side by side, a 2x1 truncates every
field to an ellipsis.

Distributions budget their rows against the tile height. A ranked tile two
rows tall shows three bars, and three rows shows six. What does not fit is
dropped from the tail, which is the part of a distribution nobody needs.

## The windows

Five windows: 24 hours, 7 days, 30 days, 90 days and 12 months.

Pick one per widget. Two tiles on the same metric can carry different windows,
so revenue over 7 days and revenue over 12 months sit side by side.

## When a window does nothing

Not every number depends on one.

A metric that answers a reading taken now ignores the window entirely. Your
current plan usage is the same number whichever window the widget carries, so
the tile does not print one.

A tile whose number does depend on the window prints it in the title, after
the name. Revenue over thirty days reads as "Revenue, 30d". That is how you
tell at a glance which of two tiles is the longer view.

## Granularity

How the window is bucketed: hour, day, week or month.

Notch Metrics picks the bucket that suits the window, so 24 hours buckets by
hour and 12 months buckets by month. A metric declares which buckets it can
answer, and the picker offers only those.
