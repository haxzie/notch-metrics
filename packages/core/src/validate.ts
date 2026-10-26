import { z } from "zod";

/**
 * Validation an author can act on.
 *
 * Everything here was already checked. `createApp` parsed the manifest it
 * built, so a bad field did fail the build. What came out was the raw
 * `ZodError` array:
 *
 * ```
 * [{"code":"invalid_value","values":["string","secret",...],
 *   "path":["metrics",0,"params",0,"type"], ... }]
 * ```
 *
 * which names a position in an array rather than the metric somebody wrote,
 * and buries the one useful sentence in JSON. A connector author is usually
 * an agent or somebody doing this for the first time, and neither reads that
 * and knows which line to change.
 *
 * So this module does two things: it validates **early**, at the smallest
 * piece that can be wrong, and it formats what went wrong as a sentence
 * naming the field and the metric.
 */

/** One issue as a line: the path, then what was wrong with it. */
function line(issue: z.core.$ZodIssue): string {
  const path = issue.path.join(".");

  // `invalid_value` on an enum is the common case and its default message
  // ("Invalid option: expected one of ...") already reads well. The others
  // are improved by naming the path first, which Zod does not do.
  const where = path ? `${path}: ` : "";
  return `${where}${issue.message}`;
}

export function formatIssues(error: z.ZodError): string {
  return error.issues.map((issue) => `  ${line(issue)}`).join("\n");
}

/**
 * Parse, or throw with every problem listed and the subject named.
 *
 * Every problem, not the first. An author fixing one field at a time, with a
 * rebuild between each, is the experience this exists to avoid.
 */
export function assertValid<T extends z.ZodType>(
  schema: T,
  value: unknown,
  subject: string,
): z.infer<T> {
  const parsed = schema.safeParse(value);
  if (parsed.success) return parsed.data;

  throw new Error(`${subject} is not valid:\n${formatIssues(parsed.error)}`);
}
