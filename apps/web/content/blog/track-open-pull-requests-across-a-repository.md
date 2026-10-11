---
title: "How to track open pull requests on a repository"
description: "Counting open pull requests, whether drafts belong in the number, and why review latency matters more than the count itself."
date: 2026-10-11
author: Notch Metrics
tags: [github, pull-requests, api]
pillar: github-stars-in-your-notch
faq:
  - question: How do I count open pull requests on GitHub?
    answer: >-
      Use the search API with q=repo:owner/name+is:pr+is:open and per_page=1,
      then read total_count. The pulls endpoint returns rows instead and makes
      you page them to count them.
  - question: Should draft pull requests count as open?
    answer: >-
      Usually yes. A draft is open and it is work in flight. Excluding drafts
      means the number only moves when work is finished, which is when you no
      longer need a leading indicator. Use draft:false if you disagree, and keep
      the choice consistent.
  - question: How do I find GitHub pull requests nobody has reviewed?
    answer: >-
      Search with is:pr is:open review:none. A pull request with no review is
      not slow, it is ignored, and the difference matters to whoever wrote it.
  - question: Is a high open pull request count bad?
    answer: >-
      Not on its own. Fifty open on a project merging thirty a week is healthy;
      twelve on a project merging one a month is a graveyard. Divide the open
      count by the weekly merge rate to get a rough queue time.
  - question: How do I tell internal from external GitHub contributions?
    answer: >-
      Read head.repo.full_name on the pull request. Outside contributions arrive
      from a fork, and a project whose external pull requests are all old is
      short of reviewers rather than contributors.
---

## How do you count open pull requests?

The search API, same as issues, with the type flipped.

```bash
curl -s 'https://api.github.com/search/issues?q=repo:owner/name+is:pr+is:open&per_page=1' \
  -H 'Authorization: Bearer <token>' | jq '.total_count'
```

One request, `total_count`, no paging. The alternative is
`/repos/{owner}/{repo}/pulls?state=open`, which returns the rows and makes
you page them to count them. Use that when you need the pull requests
themselves.

## Do drafts count?

Yes, and the argument for it is simple: a draft is open and it is work in
flight. Somebody is building something and has shown you. Excluding drafts
means your number only moves when work is finished, which is exactly when you
no longer need a leading indicator.

If you disagree, `is:pr is:open draft:false` excludes them. What matters is
picking one and not changing it quietly, because the series is only useful
compared against itself.

## The number that actually matters

The open count is a stock. What you usually want is the flow, and
specifically how long things sit.

```bash
# Open, and not touched in a fortnight.
q=repo:owner/name+is:pr+is:open+updated:<2026-09-27
```

Search supports date qualifiers on `created`, `updated`, `merged` and
`closed`, which makes a surprising amount of analysis a single query:

| Query                         | What it tells you        |
| ----------------------------- | ------------------------ |
| `is:pr is:open created:<DATE` | How much is old          |
| `is:pr is:open review:none`   | Nothing has looked at it |
| `is:pr is:open draft:false`   | Ready and waiting        |
| `is:pr merged:>DATE`          | Throughput               |

`review:none` is the sharpest of those. A pull request with no review is not
slow, it is ignored, and the difference matters to the person who wrote it.

## Open against merged is the real health signal

The open count alone says nothing. Fifty open pull requests on a project
merging thirty a week is healthy. Twelve on a project merging one a month is
a graveyard.

Query both and divide: open count over weekly merge rate gives you a rough
queue time in weeks. That single number tells a contributor whether their
work will be looked at, and it is the one that decides whether they come
back.

## Rate limits

The search API is 30 requests per minute authenticated, separate from the
5,000 per hour the rest of REST gets. Each of the queries above is one
request, so a handful of repositories is fine and a polling loop over fifty
is not.

Cache. A pull request queue does not change in seconds.

## Forks, and where contributions come from

Most outside contributions arrive as a pull request from a fork. The pull
request lives on your repository, so it is counted here regardless of where
the branch is, and `head.repo.full_name` tells you whether it came from
inside or outside.

Splitting internal from external is worth doing once. A project whose
external pull requests are all old is not short of contributors, it is short
of reviewers.

## In the notch

Notch Metrics reports
[GitHub open pull requests](/sources/github/open-pull-requests) as a count,
drafts included, with the repository picked per widget. Place it beside
[open issues](/sources/github/open-issues) and the two say whether the
project is blocked on maintainers or on contributors.

[Everything GitHub reports](/sources/github), or
[download Notch Metrics](/download).
