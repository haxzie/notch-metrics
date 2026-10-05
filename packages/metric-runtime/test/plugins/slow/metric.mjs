export async function fetchMetric() {
  // Ignores the abort signal entirely, which is exactly the case the parent's
  // hard kill exists for.
  await new Promise((resolve) => setTimeout(resolve, 5000));
  return { value: 1 };
}
