export async function fetchMetric(ctx) {
  return { value: ctx.secrets.GITHUB_TOKEN ? 1 : 0 };
}
