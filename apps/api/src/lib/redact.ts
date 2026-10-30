import { redactCredentials } from "@notch/integrations";

/**
 * Scrubs anything that looks like a credential out of a string before it is
 * logged.
 *
 * A thrown provider error often quotes the request that failed, and a Worker's
 * `console.error` goes to a log sink that outlives the request. This is the
 * last line of defence rather than the first: nothing should be putting a key
 * into an error message in the first place.
 *
 * The pattern list lives in `@notch/integrations` because the same scrub now
 * guards a user-visible surface there: `errorForResponse` quotes a provider's
 * explanation into an error message. One list, so a prefix added for that
 * reason also covers this one.
 */
export function redact(value: string): string {
  return redactCredentials(value);
}

/**
 * One JSON object per line, rather than a prefixed string.
 *
 * Workers Logs and anything downstream of Logpush parse a JSON `console`
 * argument into queryable fields, so this is the difference between
 * `scope:"oauth.refresh.int_abc"` as a filter and a regex over a message
 * body. The scope keeps its dotted shape because the prefix before the first
 * dot — `oauth`, `cron`, `metrics` — is how you narrow to a subsystem.
 */
export function logError(scope: string, error: unknown): void {
  const message = error instanceof Error ? (error.stack ?? error.message) : String(error);
  console.error(
    JSON.stringify({
      level: "error",
      scope,
      subsystem: scope.split(".")[0] ?? scope,
      message: redact(message),
    }),
  );
}

/**
 * A structured line for something that is not an error — a sweep's counts, a
 * decision worth seeing in aggregate.
 *
 * Kept separate from `logError` so a dashboard counting errors is not
 * counting these, and so the two cannot drift into one function with a level
 * argument that callers get wrong.
 */
export function logInfo(scope: string, fields: Record<string, unknown>): void {
  console.log(
    JSON.stringify({
      level: "info",
      scope,
      subsystem: scope.split(".")[0] ?? scope,
      ...fields,
    }),
  );
}
