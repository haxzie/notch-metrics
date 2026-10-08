import type { MetricId } from "./ids.ts";

/**
 * Search synonyms shared by every provider that offers a metric.
 *
 * Held centrally rather than repeated in seventeen manifests: "recurring
 * revenue" means the same thing whether it came from Stripe or Paddle, and
 * seventeen copies drift. A provider can still add its own in the manifest.
 */
export const METRIC_KEYWORDS: Partial<Record<MetricId, string[]>> = {
  mrr: ["recurring", "revenue", "monthly", "subscription", "arr", "run rate"],
  arr: ["annual", "recurring", "revenue", "run rate"],
  revenue: ["sales", "income", "earnings", "gross", "money", "turnover"],
  refunds: ["chargeback", "returned", "refunded", "credit"],
  active_subscribers: ["customers", "subscriptions", "paying", "members", "seats"],
  new_subscribers: ["signups", "new customers", "growth", "acquisition"],
  churned_subscribers: ["churn", "cancellations", "lost", "attrition"],
  trials: ["free trial", "trialling", "evaluating"],
  recent_payments: ["payments", "transactions", "orders", "charges", "latest", "list", "feed"],

  visitors: ["users", "traffic", "uniques", "audience", "people"],
  pageviews: ["views", "hits", "traffic", "impressions"],
  sessions: ["visits", "traffic"],
  active_users: ["dau", "mau", "engagement", "usage", "retention"],
  new_users: ["signups", "registrations", "acquisition", "growth"],
  events: ["actions", "tracking", "telemetry"],
  bounce_rate: ["bounces", "engagement", "quality"],
  conversion_rate: ["conversions", "funnel", "signup rate"],

  clicks: ["traffic", "search", "seo", "ctr"],
  impressions: ["reach", "search", "seo", "visibility"],
  ctr: ["click through", "clickthrough", "search", "seo"],
  average_position: ["ranking", "rank", "search", "seo", "serp"],
  backlinks: ["links", "seo", "referring domains", "authority"],
  domain_rating: ["authority", "seo", "dr", "domain authority"],
  organic_keywords: ["seo", "search terms", "rankings", "queries"],
  ad_spend: ["budget", "cost", "advertising", "marketing spend", "ppc"],
  ad_conversions: ["advertising", "roas", "campaign", "ppc"],

  contacts: ["crm", "leads", "people", "customers"],
  new_contacts: ["leads", "crm", "acquisition", "signups"],
  open_deals: ["pipeline", "opportunities", "crm", "sales"],
  won_deals: ["closed", "sales", "crm", "revenue"],
  pipeline_value: ["pipeline", "forecast", "crm", "sales"],
  open_conversations: ["support", "tickets", "inbox", "chats"],

  stars: ["github", "stargazers", "popularity", "repo"],
  forks: ["github", "repo", "clones"],
  open_issues: ["github", "bugs", "tickets", "repo"],
  open_pull_requests: ["github", "prs", "reviews", "repo"],
};
