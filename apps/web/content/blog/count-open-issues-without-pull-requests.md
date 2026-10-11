---
title: "How to count open issues without counting pull requests"
description: "GitHub's open_issues_count includes pull requests. Here is why, what it does to your backlog number, and the query that fixes it."
date: 2026-10-11
author: Notch Metrics
tags: [github, issues, api]
pillar: github-stars-in-your-notch
faq:
  - question: Why does GitHub open_issues_count include pull requests?
    answer: >-
      Because in GitHub's data model a pull request is an issue. It shares the
      numbering sequence with issues and carries an extra pull_request object,
      which is also why issue and pull request numbers never collide in a
      repository.
  - question: How do I count only open issues on GitHub?
    answer: >-
      Use the search API: GET /search/issues?q=repo:owner/name+is:issue+is:open
      with per_page=1 and read total_count. is:issue excludes pull requests by
      type, so the figure matches the Issues tab.
  - question: Does the GitHub issues list endpoint return pull requests?
    answer: >-
      Yes. GET /repos/{owner}/{repo}/issues returns both. The documented
      workaround is to filter client-side on the presence of a pull_request
      field, which means paging everything to count anything.
  - question: What is the GitHub search API rate limit?
    answer: >-
      30 requests per minute authenticated and 10 unauthenticated, separate from
      the 5,000 per hour that covers the rest of the REST API. Exceeding it
      returns 403s that look like permission problems.
  - question: Should I watch open issues or open pull requests?
    answer: >-
      Both, as a pair. Issues flat while pull requests climb is a review
      bottleneck, and that is the one that loses contributors: people will wait
      for a bug fix, but they do not submit a second pull request after the
      first sat for a month.
---

## Why does my GitHub issue count look wrong?

Because `open_issues_count` on the repository object includes open pull
requests.

```bash
curl -s https://api.github.com/repos/facebook/react | jq '.open_issues_count'
```

That number is issues plus pull requests. On a repository with an active
contribution flow it can be nearly double the backlog you see on the Issues
tab, and nothing in the field name warns you.

## The reason, which is not a bug

In GitHub's data model a pull request **is** an issue. It has an issue
number, it shares the numbering sequence with issues, it has comments and
labels and assignees like an issue, and it carries an extra `pull_request`
object with the branch details.

That is why issue numbers and pull request numbers never collide in a
repository: they come from one counter. It is also why the REST issues list
returns pull requests:

```bash
# Returns issues AND pull requests.
curl -s 'https://api.github.com/repos/facebook/react/issues?state=open'
```

The documented workaround for that list is to filter client-side on the
presence of `pull_request`:

```js
const realIssues = items.filter((item) => !item.pull_request);
```

Which works, and means paging everything to count anything.

## The query that just answers it

The search API understands the distinction natively.

```bash
curl -s 'https://api.github.com/search/issues?q=repo:facebook/react+is:issue+is:open&per_page=1' \
  -H 'Accept: application/vnd.github+json' \
  -H 'Authorization: Bearer <token>' | jq '.total_count'
```

`per_page=1` because you want `total_count`, not the rows. One request, no
paging, regardless of backlog size.

`is:issue` excludes pull requests by type rather than by filtering them out
afterwards, so the figure matches what the Issues tab shows.

## The search API has its own rate limit

Worth knowing before you build on it. Search is limited separately from the
rest of the REST API: 30 requests per minute authenticated, 10
unauthenticated, against 5,000 per hour for everything else.

For one number refreshed every few minutes that is plenty. For a dashboard
polling fifty repositories every thirty seconds it is not, and you will get
403s that look like permission problems.

`total_count` is also capped at 1,000 for results you page through, though
the count itself is reported accurately above that.

## Reading the number

A backlog climbing steadily is triage falling behind, which is not the same
as quality falling. A figure that drops in one step is almost always a bulk
close rather than a productive afternoon.

The pair worth placing is open issues against open pull requests. Issues flat
and pull requests climbing is a review bottleneck, and that is the one that
loses contributors: people will wait for a bug to be fixed, but they do not
submit a second pull request after the first one sat for a month.

## In the notch

Notch Metrics counts
[GitHub open issues](/sources/github/open-issues) through the search API with
`is:issue is:open`, so the figure is the backlog rather than the backlog plus
the contribution queue. The page says so, because a number that disagrees
with the obvious API field needs to explain itself.

[Open pull requests](/sources/github/open-pull-requests) is the other half.
[Everything GitHub reports](/sources/github), or
[download Notch Metrics](/download).
