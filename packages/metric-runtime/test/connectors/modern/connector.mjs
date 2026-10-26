// A connector in the current shape: each metric carries its own `fetch`.
//
// Deliberately written without importing `@notchmetrics/core`, because that
// is how a connector on somebody's Mac is written. The package types the
// authoring experience; nothing is imported at run time, so these objects
// are the plain shape `defineConnector` produces.
const openIssues = {
  descriptor: {
    id: "open_issues",
    label: "Open issues",
    shortLabel: "Open",
    unit: "count",
    shape: { kind: "scalar" },
    methodology: "Issues in an unfinished state.",
  },
  async fetch() {
    return { value: 12 };
  },
};

const completed = {
  descriptor: {
    id: "completed",
    label: "Completed",
    shortLabel: "Done",
    unit: "count",
    shape: { kind: "series", granularities: ["day"], compare: true },
    methodology: "Issues moved to done in the window.",
  },
  async fetch(ctx, request) {
    // Proves the request reaches the metric's own function rather than a
    // shared switch, which is the whole point of the shape.
    return { value: 7, previousValue: 4, note: request.metric };
  },
};

const explodes = {
  descriptor: {
    id: "explodes",
    label: "Explodes",
    shortLabel: "Boom",
    unit: "count",
    shape: { kind: "scalar" },
    methodology: "Always throws.",
  },
  async fetch() {
    throw new Error("the endpoint is down");
  },
};

const metrics = { open_issues: openIssues, completed, explodes };

export default {
  async verify(ctx) {
    if (!ctx.credentials.api_key) throw new Error("no key");
    return { accountLabel: "Acme" };
  },
  metrics,
  describe: () => Object.values(metrics).map((metric) => metric.descriptor),
};
