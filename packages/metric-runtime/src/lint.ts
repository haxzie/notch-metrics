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

export function lintSource(source: string): LintFinding[] {
  const findings: LintFinding[] = [];

  for (const { pattern, what } of SECRET_SHAPES) {
    if (pattern.test(source)) {
      findings.push({
        severity: "error",
        message: `This looks like ${what} written into the file. Declare it in manifest.secrets and set the value with set_metric_secret — the app keeps it in the macOS Keychain and hands it to the runner on stdin, so it never touches disk.`,
      });
    }
  }

  if (!/export\s+(async\s+)?function\s+fetchMetric/.test(source)) {
    findings.push({
      severity: "error",
      message: "The entry file must `export async function fetchMetric(ctx)`.",
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
