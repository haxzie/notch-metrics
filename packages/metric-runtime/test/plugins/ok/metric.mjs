export async function fetchMetric(ctx) {
  ctx.log("working");
  return { value: 42, unit: "count" };
}
