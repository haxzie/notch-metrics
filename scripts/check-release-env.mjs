#!/usr/bin/env node
/**
 * Refuses to cut a release that would ship pointing at a development server.
 *
 * Runs from release-mac.yml and from `pnpm mac:ship` — never from a plain
 * build. A compile has no business caring which server it would have talked
 * to, and a check that fires on every local build gets disabled.
 *
 * This is the one bug class that only surfaces *after* shipping: a notarised,
 * stapled, perfectly valid disk image whose Sign In button opens localhost.
 */
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const mac = join(root, "apps", "mac");

const problems = [];
const note = (message) => problems.push(message);

const LOCAL = /^https?:\/\/(localhost|127\.0\.0\.1|0\.0\.0\.0|\[::1\])(:|\/|$)/i;

// 1. The URLs the app will be built with.
const config = (() => {
  try {
    return readFileSync(join(mac, "Config", "Config.xcconfig"), "utf8");
  } catch {
    return "";
  }
})();

for (const key of ["NM_API_URL", "NM_APP_URL", "NM_ASSETS_URL"]) {
  const match = new RegExp(`^${key}\\s*=\\s*(.+)$`, "m").exec(config);
  // The xcconfig escapes `//` as `/$()/` because `//` starts a comment there.
  const value = match?.[1]?.replace("/$()/", "//").trim();
  if (!value) {
    note(`${key} is not set. Run: node scripts/sync-mac-config.mjs`);
  } else if (LOCAL.test(value)) {
    note(`${key} is ${value}, which is a development server.`);
  }
}

// 2. The version the app will report matches the package it came from.
const { version } = JSON.parse(readFileSync(join(mac, "package.json"), "utf8"));
const versionConfig = readFileSync(join(mac, "Config", "Version.xcconfig"), "utf8");
if (!versionConfig.includes(`MARKETING_VERSION = ${version}`)) {
  note(`Config/Version.xcconfig does not say ${version}. Run: node scripts/sync-mac-version.mjs`);
}

// 3. The tag matches that version.
//
// Without this, a release ends up full of files named after the *previous*
// version — which looks exactly like the wrong build was published, and cannot
// be told apart from it after the fact.
const tag = process.env.GITHUB_REF_NAME;
if (tag?.startsWith("mac-v")) {
  const tagged = tag.slice("mac-v".length);
  if (tagged !== version) {
    note(`the tag ${tag} does not match apps/mac/package.json (${version}).`);
  }
}

// 4. Hardened runtime and a real signing identity, read back from Xcode
//    rather than assumed from the xcconfig.
try {
  const settings = execFileSync(
    "xcodebuild",
    [
      "-project",
      join(mac, "NotchMetrics.xcodeproj"),
      "-scheme",
      "NotchMetrics",
      "-configuration",
      "Release",
      "-showBuildSettings",
    ],
    { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] },
  );

  if (!/ENABLE_HARDENED_RUNTIME = YES/.test(settings)) {
    note("ENABLE_HARDENED_RUNTIME is not YES; notarisation will be rejected.");
  }
  if (/CODE_SIGN_IDENTITY = -\s*$/m.test(settings)) {
    note("CODE_SIGN_IDENTITY is ad-hoc. Such a build can never update itself in place.");
  }
} catch {
  note("could not read the build settings. Run: pnpm mac:gen");
}

// 5. A development ATS shim is exactly the sort of thing that ships.
const plist = readFileSync(join(mac, "App", "Info.plist"), "utf8");
if (plist.includes("NSAllowsArbitraryLoads")) {
  note("Info.plist contains NSAllowsArbitraryLoads.");
}

if (problems.length === 0) {
  console.log(`Release checks passed for ${version}.`);
  process.exit(0);
}

const prefix = process.env.GITHUB_ACTIONS ? "::error::" : "  • ";
console.error("This build is not safe to release:\n");
for (const problem of problems) console.error(`${prefix}${problem}`);

if (process.env.NOTCH_ALLOW_LOCAL_URLS === "1") {
  console.error("\nNOTCH_ALLOW_LOCAL_URLS=1 is set; continuing anyway.");
  process.exit(0);
}
console.error("\nSet NOTCH_ALLOW_LOCAL_URLS=1 to override the URL checks.");
process.exit(1);
