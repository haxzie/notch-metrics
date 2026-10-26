export async function verify(ctx) {
  if (!ctx.credentials.api_key) throw new Error("no key");
  return { accountLabel: "Acme", currency: null, unavailableMetrics: [] };
}

export async function fetchMetric(ctx, request) {
  switch (request.metric) {
    case "open_issues":
      return { value: 12 };
    case "completed":
      return {
        value: 7,
        previousValue: 4,
        points: [
          { t: "2026-10-23T00:00:00.000Z", v: 3 },
          { t: "2026-10-24T00:00:00.000Z", v: 4 },
        ],
      };
    case "recent":
      return {
        value: 2,
        items: [
          {
            id: "ENG-1",
            t: "2026-10-24T09:00:00.000Z",
            label: "Fix the notch",
            state: "succeeded",
          },
          { id: "ENG-2", t: "2026-10-24T08:00:00.000Z", label: "Ship it", state: "running" },
        ],
      };
    case "explodes":
      throw new Error("the endpoint is down");
    // Reports the credential keys visible to this connector, so a test can
    // assert what the filter let through without the value leaving here.
    case "echo_credentials":
      return {
        value: Object.keys(ctx.credentials).length,
        items: Object.keys(ctx.credentials).map((key) => ({
          id: key,
          t: "2026-10-25T00:00:00.000Z",
          label: key,
        })),
      };
    default:
      throw new Error(`unhandled ${request.metric}`);
  }
}
