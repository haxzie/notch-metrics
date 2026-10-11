import { Hono } from "hono";
import { eq } from "drizzle-orm";
import { MetricBatchRequest, MetricQuery } from "@notch/schemas";
import { getAdapter } from "@notch/integrations";
import { integration as integrationTable } from "@notch/db";
import { authenticate, rateLimited, requireAccess, type AppContext } from "../middleware.ts";
import { queryMetric, queryMetrics, sweepCache } from "../lib/metrics.ts";
import { loadUser } from "../lib/identity.ts";

export const metrics = new Hono<AppContext>();

metrics.use("*", authenticate, requireAccess, rateLimited({ limit: 120, windowSeconds: 300 }));

metrics.get("/query", async (c) => {
  const parsed = MetricQuery.safeParse({
    integrationId: c.req.query("integrationId"),
    metric: c.req.query("metric"),
    granularity: c.req.query("granularity") || undefined,
    range: c.req.query("range") ?? "30d",
    series: c.req.query("series") !== "0",
    // `?p.repository=owner/name`. A prefix rather than a JSON blob in a query
    // string: this route is reached by hand and from a preview, and one
    // readable pair per parameter is easier to get right than nested encoding.
    params: Object.fromEntries(
      Object.entries(c.req.queries() ?? {})
        .filter(([key]) => key.startsWith("p."))
        .map(([key, values]) => [key.slice(2), values[0] ?? ""]),
    ),
  });
  if (!parsed.success) return c.json({ code: "BAD_REQUEST", message: "Invalid query." }, 400);

  const db = c.get("db");
  const user = await loadUser(db, c.get("identity").userId);
  if (!user) return c.json({ code: "NOT_FOUND", message: "No such account." }, 404);

  const result = await queryMetric(
    {
      db,
      env: c.env,
      userId: user.id,
      timeZone: user.timezone,
      preferredCurrency: user.preferredCurrency,
    },
    parsed.data,
  );

  c.executionCtx.waitUntil(sweepCache(db));
  return c.json(result, 200, { "cache-control": "private, max-age=30" });
});

/**
 * The hot path. One round trip for the whole notch.
 *
 * Results are index-aligned with the request array and partial success is the
 * normal case: an HTTP status cannot be per-item, and one broken provider must
 * not blank a dashboard that has four working widgets on it.
 */
metrics.post("/batch", async (c) => {
  const parsed = MetricBatchRequest.safeParse(await c.req.json().catch(() => ({})));
  if (!parsed.success) return c.json({ code: "BAD_REQUEST", message: "Invalid request." }, 400);

  const db = c.get("db");
  const user = await loadUser(db, c.get("identity").userId);
  if (!user) return c.json({ code: "NOT_FOUND", message: "No such account." }, 404);

  const options = {
    db,
    env: c.env,
    userId: user.id,
    timeZone: user.timezone,
    preferredCurrency: user.preferredCurrency,
  };

  const results = await queryMetrics(options, parsed.data.requests);

  c.executionCtx.waitUntil(sweepCache(db));
  return c.json({ results });
});

/** What this user can actually ask for: their integrations crossed with the registry. */
metrics.get("/catalog", async (c) => {
  const rows = await c
    .get("db")
    .select()
    .from(integrationTable)
    .where(eq(integrationTable.userId, c.get("identity").userId));

  const entries = rows.flatMap((row) => {
    const manifest = getAdapter(row.provider).manifest;
    const available = new Set(row.availableMetrics ?? []);
    return manifest.metrics
      .filter((m) => available.has(m.id))
      .map((m) => ({
        integrationId: row.id,
        provider: row.provider,
        accountLabel: row.accountLabel,
        metric: m.id,
        label: m.label,
        shortLabel: m.shortLabel,
        unit: m.unit,
        currency: row.accountCurrency,
        granularities: m.granularities,
        supportsSeries: m.supportsSeries,
      }));
  });

  return c.json(entries);
});
