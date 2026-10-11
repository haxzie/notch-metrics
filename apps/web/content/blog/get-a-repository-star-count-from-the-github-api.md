---
title: "How to get a repository's star count from the GitHub API"
description: "One field, and then the hard part: why star history needs a different endpoint, a preview header, and more patience than it is worth."
date: 2026-10-11
author: Notch Metrics
tags: [github, stars, api]
pillar: github-stars-in-your-notch
faq:
  - question: Which GitHub API field is the star count?
    answer: >-
      stargazers_count on the repository object. Note that watchers_count is a
      duplicate of the star count for historical reasons, and the actual watcher
      count is subscribers_count.
  - question: Can I get GitHub star history from the API?
    answer: >-
      Not directly. There is no history endpoint. The stargazers list returns
      starred_at only if you send the Accept header
      application/vnd.github.star+json, and it pages at 100 with a 400-page cap,
      so repositories past 40,000 stars cannot be fully walked.
  - question: Why is starred_at missing from the GitHub stargazers response?
    answer: >-
      Because the preview media type is not set. Send Accept:
      application/vnd.github.star+json. Without it the call still succeeds and
      returns plain user objects with no timestamp, which is a quiet failure.
  - question: What is the GitHub API rate limit for star counts?
    answer: >-
      60 requests per hour unauthenticated, 5,000 with a token. Any polling
      needs a token. A fine-grained token with public repository read access is
      enough; a classic token with repo scope grants far more than reading a
      public count requires.
  - question: Does a GitHub star mean somebody uses the project?
    answer: >-
      No. A star is a bookmark, not a download, an install or a user. Read it as
      attention rather than adoption.
---

## How do you get a repository's star count?

One call, one field.

```bash
curl -s https://api.github.com/repos/vercel/next.js \
  -H 'Accept: application/vnd.github+json' | jq .stargazers_count
```

`stargazers_count` is the current total. There is also `watchers_count` on
the same object, which for historical reasons is a duplicate of the star
count and not the number of watchers. If you want actual watchers, that is
`subscribers_count`.

Three fields, two of which mean something other than their name. It catches
everybody once.

| Field               | What it actually is |
| ------------------- | ------------------- |
| `stargazers_count`  | Stars               |
| `watchers_count`    | Stars, again        |
| `subscribers_count` | Watchers            |

## Authentication, and why you want it even for public data

The endpoint works unauthenticated at 60 requests per hour per IP. With a
token it is 5,000. Any polling at all needs the token, and the call is the
same with an `Authorization: Bearer` header added.

A fine-grained token with public repository read access is enough. Do not use
a classic token with `repo` scope to read a public star count: that scope
grants write access to every private repository you can see, for a number
anybody can read logged out.

## Star history is the hard part

The current count is trivial. "Stars per day for the last month" is not, and
this is what most people are actually asking for.

There is no endpoint for it. What exists is the stargazers list with a
preview media type that adds the timestamp:

```bash
curl -s 'https://api.github.com/repos/vercel/next.js/stargazers?per_page=100&page=1' \
  -H 'Accept: application/vnd.github.star+json'
```

Without `application/vnd.github.star+json` you get user objects with no
`starred_at`, which is the quiet failure here: the call succeeds and the
field you need is simply absent.

The real problem is volume. The list pages at 100 and GitHub caps pagination
at 400 pages, so a repository past 40,000 stars cannot be fully walked at
all. Even below that, 40,000 stars is 400 requests for one chart.

That is why every star history site you have used is a service that has been
recording the number daily since before you needed it. They are not reading
history, they are replaying their own.

## If you only need recent history

Page the stargazers list from the end. Stars are returned oldest first, so
the last page holds the newest, and `Link: rel="last"` tells you where that
is.

```js
const res = await fetch(`https://api.github.com/repos/${repo}/stargazers?per_page=100`, {
  headers: { Accept: "application/vnd.github.star+json", Authorization: `Bearer ${token}` },
});
// Parse the Link header to find rel="last", then walk backwards from there.
```

A handful of calls gets you the last few hundred stars with timestamps, which
is enough for a recent trend and costs nothing like a full walk.

## What a star is not

A star is a bookmark. It is not a download, not an install and not a user. A
project with ten thousand stars may have a hundred people running it, and a
tool with four hundred stars may be in production at four hundred companies.

Read it as attention. If you want adoption, that number is somewhere else
entirely.

## In the notch

Notch Metrics reports
[GitHub stars](/sources/github/stars) as the current count, with the
repository picked per widget. No sparkline, because the API does not offer
one without paging the full history on every refresh, and inventing a chart
from a single number would be worse than not drawing one.

[Forks](/sources/github/forks),
[open issues](/sources/github/open-issues) and
[open pull requests](/sources/github/open-pull-requests) sit beside it.
[Everything GitHub reports](/sources/github), or
[download Notch Metrics](/download).
