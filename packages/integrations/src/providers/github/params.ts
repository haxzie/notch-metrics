import type { AuthField } from "@notch/schemas";

/**
 * The repository a tile is about, asked for when the widget is configured.
 *
 * `pattern` is prevalidation only — the app greys out Done on a malformed
 * name, and `fetchMetric` checks it again, because a manifest is a hint and
 * the server is where it has to be true.
 */
export const REPOSITORY_PARAM: AuthField = {
  key: "repository",
  label: "Repository",
  type: "string",
  required: true,
  placeholder: "owner/name",
  help: "Which repository this tile counts.",
  pattern: "^[\\w.-]+/[\\w.-]+$",
};

/**
 * Which branch's runs a CI tile lists.
 *
 * Optional, and empty means every branch: a repository with one active branch
 * reads the same either way, and demanding a branch name before the tile can
 * show anything would make the common case the fiddly one.
 */
export const BRANCH_PARAM: AuthField = {
  key: "branch",
  label: "Branch",
  type: "string",
  required: false,
  placeholder: "main",
  help: "Leave empty for every branch.",
  // A ref can hold almost anything a path can, so this only rules out what
  // would change the request rather than the branch: a slash is legal in a
  // branch name and `feature/x` must stay askable.
  pattern: "^[^\\s?&#]+$",
};
