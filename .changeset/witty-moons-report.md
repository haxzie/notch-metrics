---
"@notch/integrations": minor
---

Implement the GitHub connector: stars, forks, open issues and open pull
requests from one repository, connected over OAuth.

It is the first connector to use the OAuth leg of the connect flow, which was
scaffolded but had no consumers — authorize, callback, and a post-grant
selection step, with the access token held under the same envelope encryption
a finished integration uses while the user picks a repository.

Open issues are counted through search rather than taken from the repository
object's `open_issues_count`, which includes pull requests and therefore reads
high by exactly the number of open PRs.
