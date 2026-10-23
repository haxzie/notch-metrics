import { list } from "../define.ts";
import {
  CI_RUNS_LIMIT,
  branchFor,
  get,
  repoPath,
  repositoryFor,
  runState,
  type WorkflowRuns,
} from "../client.ts";
import { BRANCH_PARAM, REPOSITORY_PARAM } from "../params.ts";

export const ciRuns = list({
  id: "ci_runs",
  // `{branch}` drops out of the query when the widget does not name one,
  // which is what Actions itself shows for "every branch".
  linkTemplate: "https://github.com/{repository}/actions?query=branch%3A{branch}",
  label: "CI runs",
  shortLabel: "CI",
  // The rows are the widget. The headline figure is the count behind them,
  // which is what a tile too short for rows falls back to and what a
  // threshold notification would read — so `fetch` returns rows only and the
  // count is derived.
  unit: "count",
  // A feed of what just happened, like a payments list: the same ten runs
  // whatever the range says, so neither a chart nor a comparison applies.
  limit: CI_RUNS_LIMIT,
  keywords: ["ci", "build", "actions", "workflow", "pipeline", "checks"],
  // A minute, against the fifteen a daily bucket would otherwise hold it
  // for. This is the one metric here that is read to decide whether to go
  // and look at something, so being a quarter of an hour behind defeats
  // it. The notch polls every five minutes, so this mostly means the poll
  // is never served a cached answer rather than four requests a minute.
  freshnessSeconds: 60,
  methodology:
    "The ten most recent GitHub Actions runs, newest first. Private repositories included, " +
    "for the account this connection signed in as.",
  params: [REPOSITORY_PARAM, BRANCH_PARAM],

  async fetch(ctx, creds, request) {
    const repository = repositoryFor(creds, request);
    const branch = branchFor(request);
    const body = await get<WorkflowRuns>(
      ctx,
      creds,
      `${repoPath(repository)}/actions/runs?per_page=${CI_RUNS_LIMIT}` +
        (branch ? `&branch=${encodeURIComponent(branch)}` : ""),
    );
    const runs = body.workflow_runs ?? [];
    const items = runs.slice(0, CI_RUNS_LIMIT).map((run) => {
      const { state, status } = runState(run);
      return {
        id: String(run.id),
        // When it last moved, not when it was queued: a run that has been
        // going for an hour should not read as an hour old the moment it
        // finishes.
        t: new Date(run.updated_at || run.created_at),
        // The *workflow*, not the commit subject.
        //
        // One push starts every workflow that watches the branch, and all
        // of them carry the same `display_title` — so a list labelled by
        // the commit is five rows of the same sentence, at the same age,
        // which reads as the tile having failed to load rather than as
        // four jobs. The workflow names are what differ, and they are
        // short enough for a narrow tile; the commit goes to `detail`,
        // which a wide tile shows.
        label: run.name?.trim() || run.display_title?.trim() || `Run ${run.id}`,
        detail:
          [run.display_title?.trim(), branch ? null : run.head_branch?.trim()]
            .filter(Boolean)
            .join(" · ") || null,
        amount: null,
        currency: null,
        status,
        state,
      };
    });

    return {
      items,
      ...(items.length === 0
        ? {
            note: branch ? `No Actions runs on ${branch}.` : "No Actions runs on this repository.",
          }
        : {}),
    };
  },
});
