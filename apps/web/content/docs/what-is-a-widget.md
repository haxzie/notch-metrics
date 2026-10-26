---
title: What a widget is
description: A widget is one tile in the notch. It carries a number, a window and one shape that draws it.
summary: One tile, one number, and the four parts every widget is made of.
section: widgets
order: 1
date: 2026-10-26
---

A widget is one tile in the notch. Hover the camera housing and the notch
opens. Move away and it looks untouched.

Every widget carries four things. Change any one of them and the tile changes.

## The metric

The number itself, and the definition behind it. Stripe revenue is a different
metric from Stripe MRR, and both come from the same connection.

Each metric declares how it is calculated. You can read that sentence on the
[sources pages](/sources) before you add the tile.

## The window

How far back the number looks. Notch Metrics offers five windows: 24 hours,
7 days, 30 days, 90 days and 12 months.

Not every number uses one. A gauge showing your current plan usage is a
reading taken now, so the window does nothing and the tile does not show one.
A tile whose number depends on the window prints it in the title, next to the
name.

## The shape

How the tile draws the number. A sparkline under a figure, a filled arc, a
divided bar, a ring. There are seven shapes and the next page covers all of
them.

The shape is yours to pick. Notch Metrics suggests one when you add a widget,
based on what the metric answers, and you can change it afterwards.

## The size

How much of the grid the tile takes. The notch is six columns wide and opens
up to four rows deep. A tile spans anything that fits.

Size is not only room. A one by one tile shows a mark and a number. Give the
same widget three columns and it reads left to right, with the name on one
side and the figure and the chart on the other.

## Where the numbers come from

Sixteen services are connected server side. Your provider API keys are held
encrypted and never reach the Mac.

For anything else you write a custom app. That is one directory on your Mac
holding a manifest and a JavaScript file, running against your own key. The
second half of these docs covers how to build one.
