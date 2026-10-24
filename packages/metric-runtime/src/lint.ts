/**
 * Refuses a plugin source that contains something shaped like a credential.
 *
 * This is the highest-leverage safety check in the whole custom-metric design,
 * because the natural thing for an agent to do with an API key it was just
 * given is to paste it into the file it is writing. The manifest's `secrets`
 * declaration plus `set_metric_secret` exist precisely so it does not have to,
 * and a refusal here is what makes an agent discover that.
 */
export interface LintFinding {
  severity: "error" | "warning";
  message: string;
}

const SECRET_SHAPES: { pattern: RegExp; what: string }[] = [
  { pattern: /\b(sk|rk)_(live|test)_[A-Za-z0-9]{8,}/, what: "a Stripe key" },
  { pattern: /\bwhsec_[A-Za-z0-9+/=]{8,}/, what: "a webhook signing secret" },
  { pattern: /\b(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{16,}/, what: "a GitHub token" },
  { pattern: /\bAKIA[0-9A-Z]{12,}/, what: "an AWS access key id" },
  { pattern: /\bxox[baprs]-[A-Za-z0-9-]{10,}/, what: "a Slack token" },
  {
    // A long opaque literal assigned to something that calls itself a secret.
    pattern:
      /\b(?:const|let|var)?\s*\w*(?:key|token|secret|password|auth)\w*\s*[:=]\s*["'`][A-Za-z0-9+/_=-]{24,}["'`]/i,
    what: "a hardcoded credential",
  },
];

/**
 * What is being linted, which only changes the remedy in the message.
 *
 * The check is identical either way; the instruction is not. Telling an agent
 * writing a connector to "declare it in manifest.secrets and set it with
 * set_metric_secret" names a field and a tool that do not exist for it, and an
 * agent follows instructions — so it would go and look for them.
 */
export type LintTarget = "metric" | "connector";

export function lintSource(source: string, target: LintTarget = "metric"): LintFinding[] {
  const remedy =
    target === "connector"
      ? "Declare it in the manifest's `auth` and set the value with set_connector_credential"
      : "Declare it in manifest.secrets and set the value with set_metric_secret";
  const findings: LintFinding[] = [];

  for (const { pattern, what } of SECRET_SHAPES) {
    if (pattern.test(source)) {
      findings.push({
        severity: "error",
        message: `This looks like ${what} written into the file. ${remedy} — the app keeps it in the macOS Keychain and hands it to the runner on stdin, so it never touches disk.`,
      });
    }
  }

  if (!exportsFetchMetric(source)) {
    findings.push({
      severity: "error",
      message: "The entry file must export a `fetchMetric(ctx)` function.",
    });
  }

  if (/\bprocess\.env\b/.test(source)) {
    findings.push({
      severity: "warning",
      message:
        "`process.env` is empty in the runner by design. Use `ctx.secrets.<KEY>` for declared secrets.",
    });
  }

  if (/\brequire\s*\(|from\s+["']node:(child_process|net|dgram)["']/.test(source)) {
    findings.push({
      severity: "error",
      message: "A metric is one ES module with no dependencies and no subprocesses.",
    });
  }

  if (/\bfetch\s*\(/.test(source) && !/ctx\.http|\bhttp\s*\(/.test(source)) {
    findings.push({
      severity: "warning",
      message:
        "`fetch` is not available in the runner. Use `ctx.http`, which enforces the manifest's allowedHosts.",
    });
  }

  return findings;
}

/**
 * Whether the source exports `fetchMetric` in any of the spellings a real
 * toolchain emits.
 *
 * It used to be one regex for `export async function fetchMetric`, which is
 * what a person writes by hand and *not* what a bundler emits. esbuild turns
 * exactly that source into:
 *
 *     async function fetchMetric(ctx) { … }
 *     export { fetchMetric };
 *
 * — so anyone who built their metric from a TypeScript project had it refused
 * at `create_metric` for "missing export", while the same file ran perfectly.
 * The runtime check never agreed with this one: `executeMetric` asks
 * `typeof module.fetchMetric === "function"`, which is the truth.
 *
 * This stays a text check despite that, because it is the only one that can
 * fail *before* a staged run and so produce an error that names the problem.
 * The staged run remains the real gate; this is the better message.
 */
function exportsFetchMetric(source: string): boolean {
  // `export function` / `export async function` / `export const fetchMetric =`
  if (/export\s+(async\s+)?(function\s+|const\s+|let\s+|var\s+)fetchMetric\b/.test(source)) {
    return true;
  }
  // `export { fetchMetric }`, `export { a as fetchMetric }`, across newlines
  // and alongside other names.
  //
  // Narrower than "fetchMetric appears between the braces", which would also
  // pass `export { fetchMetric as somethingElse }` — that exports the function
  // under a name the runtime does not look for, so it is exactly as broken as
  // no export at all.
  for (const clause of source.matchAll(/export\s*\{([^}]*)\}/g)) {
    const names = clause[1] ?? "";
    if (/\bas\s+fetchMetric\b/.test(names)) return true;
    if (/(^|,)\s*fetchMetric\s*(,|$)/.test(names)) return true;
  }
  // `export default { fetchMetric }` is not supported and deliberately not
  // matched: `executeMetric` reads a named export off the module namespace.
  return false;
}
