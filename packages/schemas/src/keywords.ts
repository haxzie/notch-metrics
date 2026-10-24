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

  orders: ["sales", "purchases", "transactions", "checkouts", "volume", "store"],
  average_order_value: ["aov", "basket", "cart", "average order", "order size", "spend"],
  customers: ["buyers", "shoppers", "people", "store", "accounts"],
  new_customers: ["first time", "buyers", "acquisition", "growth", "signups", "store"],

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

  subscribers: ["subs", "audience", "channel", "youtube", "followers", "fans"],
  views: ["plays", "watches", "youtube", "video", "traffic"],
  watch_time: ["watched", "minutes watched", "hours", "youtube", "retention"],
  average_view_duration: ["avd", "retention", "youtube", "how long"],
  likes: ["thumbs up", "reactions", "engagement"],
  comments: ["replies", "engagement", "discussion"],
  ad_revenue: ["adsense", "ads", "earnings", "payout", "monetisation", "monetization"],
  rpm: ["revenue per mille", "per thousand", "earnings", "cpm", "monetisation"],

  tokens: ["llm", "ai", "usage", "consumption", "context", "prompt"],
  input_tokens: ["prompt", "llm", "ai", "context", "usage"],
  output_tokens: ["completion", "generated", "llm", "ai", "usage"],
  api_requests: ["calls", "requests", "llm", "ai", "volume", "traffic"],
  api_spend: ["cost", "bill", "burn", "llm", "ai", "spend", "inference"],

  stars: ["github", "stargazers", "popularity", "repo"],
  forks: ["github", "repo", "clones"],
  open_issues: ["github", "bugs", "tickets", "repo"],
  open_pull_requests: ["github", "prs", "reviews", "repo"],
  ci_runs: ["ci", "build", "builds", "actions", "workflow", "pipeline", "checks", "green", "red"],
};
