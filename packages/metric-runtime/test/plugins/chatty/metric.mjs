export async function fetchMetric() {
  console.log("this must not reach stdout");
  console.log(JSON.stringify({ ok: true, result: { value: 999 } }));
  return { value: 7 };
}
