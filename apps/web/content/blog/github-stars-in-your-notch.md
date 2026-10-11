---
title: "GitHub stars in your MacBook notch"
description: "Stars, forks, open issues and pull requests from GitHub, in the strip of glass around your Mac's camera. Hover to look, move away and it is gone."
date: 2026-10-11
author: Notch Metrics
tags: [github, stars, mac]
faq:
  - question: How do I see GitHub stars on my Mac?
    answer: >-
      Install Notch Metrics, connect GitHub over OAuth, and place the stars
      widget in the MacBook notch with the repository in owner/name form. Hover
      the camera housing and the count is there.
  - question: Can I track more than one GitHub repository?
    answer: >-
      Yes. Each of the repository widgets asks which repository to count, so one
      GitHub connection covers as many repositories as you place widgets for.
  - question: Does Notch Metrics count pull requests as open issues?
    answer: >-
      No. GitHub's own open_issues_count includes pull requests because a pull
      request is an issue in its data model. Notch Metrics counts issues through
      the search API with is:issue is:open, so the figure matches the Issues
      tab.
  - question: Why do the GitHub widgets have no sparkline?
    answer: >-
      Because GitHub returns only the current count. There is no endpoint for a
      star count on a past day, and reconstructing one means paging the entire
      stargazer history on every refresh.
  - question: What GitHub permissions does Notch Metrics ask for?
    answer: >-
      Read access to public repositories you can see, and your name and avatar.
      That is the whole grant, and nothing is typed in because GitHub connects
      over OAuth.
---

If you maintain anything open source you know the refresh. Open the
repository, look at the star count, close the tab. Nothing changed. Do it
again in an hour.

## How do you watch a repository without the tab?

Notch Metrics puts the counts in the MacBook notch. Collapsed, a thin strip.
Hover the camera housing and it expands. Move away and it folds back to the
shape it had.

## What GitHub reports

| Number                                                   | What it is                          |
| -------------------------------------------------------- | ----------------------------------- |
| [Stars](/sources/github/stars)                           | The repository's current star count |
| [Forks](/sources/github/forks)                           | Direct forks, not forks of forks    |
| [Open issues](/sources/github/open-issues)               | Issues only, pull requests excluded |
| [Open pull requests](/sources/github/open-pull-requests) | Including drafts                    |
| [Followers](/sources/github/followers)                   | On the account, not a repository    |

The first four ask which repository to count, in `owner/name` form, because
one GitHub connection usually covers several. Add a widget per repository.
Followers belongs to the account, so it asks for nothing.

## Open issues, counted properly

GitHub's own `open_issues_count` on the repository object includes pull
requests, because in GitHub's data model a pull request is an issue. A
project with an active contribution flow reads as though its backlog doubled
overnight.

Notch Metrics counts issues through the search API with `is:issue is:open`,
so [the number in your notch](/sources/github/open-issues) is the backlog you
would see on the Issues tab. That is the kind of difference worth a sentence
on the page rather than a surprise in the figure.

## Why none of these have sparklines

GitHub returns the current count. There is no endpoint for the star count on
an arbitrary past day, and reconstructing one means paging the entire
stargazer history on every refresh. So the widgets show figures rather than
charts, which is honest about what the API gives.

## OAuth, no key to paste

GitHub connects over OAuth. You approve a prompt that asks to read public
repositories you can see and your name and avatar, and that is the whole
grant. [What the GitHub connector asks for](/sources/github).

No token is typed in anywhere, and the token that results is encrypted on the
server. The Mac app never holds it.

## Alongside everything else

Revenue from [Stripe](/sources/stripe) and
[Polar](/sources/polar), traffic from [Plausible](/sources/plausible),
search from [Search Console](/sources/google-search-console).
[Every source](/sources).

Apple silicon, macOS 14 and later. Seven days with no card, then $14 a month
or $79 a year. [Download Notch Metrics](/download).
