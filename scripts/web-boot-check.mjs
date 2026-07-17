// Boots the deployed web client in headless Chromium and fails if it
// never reaches Main._ready, or if the console shows the parse-error
// cascade documented in CLAUDE.md ("Web Build Parse Errors").
//
// Why this exists: the curl-based web smoke in nightly-smoke.yml
// validates that the page is served, that GODOT_CONFIG was patched to
// absolute R2 URLs, and that the R2 heavies have CORS. It never
// executes the wasm. Every parse-error cascade we have hit would sail
// past it green. This check actually runs the client.
//
// The positive signal is window.__hopnbop_booted, set at the end of
// Main._ready (src/core/main.gd). Reaching it proves the engine
// started, GDScript compiled, the autoloads resolved, and
// settings.tres loaded.
//
// Usage:
//   node scripts/web-boot-check.mjs
//   WEB_CLIENT_URL=https://staging.example/ node scripts/web-boot-check.mjs

import { chromium } from "playwright";

const URL = process.env.WEB_CLIENT_URL || "https://hopnbop.net/";
// The wasm is ~38 MB and is fetched cross-origin from R2, then
// compiled, before any GDScript runs. CI runners are slow and cold;
// be generous. A real boot on a warm runner lands in ~15-25s.
const BOOT_TIMEOUT_MS = Number(process.env.BOOT_TIMEOUT_MS || 120_000);
const POLL_INTERVAL_MS = 500;

// Signatures of the parse-error cascade. The first two are the root
// cause the CLAUDE.md playbook says to look for; the rest are the
// downstream noise, matched so we still fail loudly if the root-cause
// line scrolls past or changes shape between Godot versions.
const FATAL_PATTERNS = [
  /Cannot get class ''/,
  /Parameter "obj" is null/,
  /Parse Error:/,
  /Compile Error:/,
  /Failed to load script/,
  /Cyclic reference/,
];

const logs = [];

function record(source, text) {
  logs.push({ source, text });
}

function findFatal() {
  return logs.filter((entry) =>
    FATAL_PATTERNS.some((pattern) => pattern.test(entry.text)),
  );
}

function dumpLogs(limit = 60) {
  if (logs.length === 0) {
    console.log("  (no console output captured)");
    return;
  }
  for (const entry of logs.slice(-limit)) {
    console.log(`  [${entry.source}] ${entry.text}`);
  }
}

const browser = await chromium.launch({
  // Godot's web export needs WebGL2. Headless Chromium has no real
  // GPU on a CI runner, so force the software rasterizer. Without
  // these the canvas init fails and the client never boots, which
  // would look identical to a parse-error regression.
  args: [
    "--use-gl=angle",
    "--use-angle=swiftshader",
    "--enable-unsafe-swiftshader",
  ],
});

let exitCode = 0;

try {
  const page = await browser.newPage();

  page.on("console", (message) => record(message.type(), message.text()));
  page.on("pageerror", (error) => record("pageerror", String(error)));
  page.on("requestfailed", (request) => {
    record(
      "requestfailed",
      `${request.url()} — ${request.failure()?.errorText ?? "unknown"}`,
    );
  });

  console.log(`Loading ${URL} ...`);
  const response = await page.goto(URL, {
    waitUntil: "domcontentloaded",
    timeout: 60_000,
  });
  if (!response || !response.ok()) {
    throw new Error(`page returned HTTP ${response ? response.status() : "?"}`);
  }

  const deadline = Date.now() + BOOT_TIMEOUT_MS;
  let booted = false;

  while (Date.now() < deadline) {
    // The client legitimately navigates on its own: a stale cached
    // build hard-refreshes itself via _web_hard_refresh(), which
    // tears down the execution context mid-poll. That is expected
    // behavior, not a failure, so swallow the race and re-poll
    // against the new context.
    try {
      booted = await page.evaluate(() => window.__hopnbop_booted === true);
    } catch (error) {
      if (!/Execution context was destroyed|frame was detached/i.test(error.message)) {
        throw error;
      }
      booted = false;
    }
    if (booted) break;

    // Fail fast on a cascade rather than burning the full timeout.
    // Once the parse errors start the client is never going to boot.
    if (findFatal().length > 0) break;

    await page.waitForTimeout(POLL_INTERVAL_MS);
  }

  const fatal = findFatal();

  if (fatal.length > 0) {
    console.error("::error::web client hit the parse-error cascade");
    console.error("Matched signatures:");
    for (const entry of fatal.slice(0, 10)) {
      console.error(`  [${entry.source}] ${entry.text}`);
    }
    console.error(
      "\nSee CLAUDE.md 'Web Build Parse Errors' — read the log " +
        "top-down; the first error is the root cause, the Parse " +
        "Error lines below it are downstream noise. Do NOT fix " +
        "this with .get() rewrites.",
    );
    console.error("\nFull console output:");
    dumpLogs();
    exitCode = 1;
  } else if (!booted) {
    console.error(
      `::error::web client did not reach Main._ready within ` +
        `${BOOT_TIMEOUT_MS}ms (no window.__hopnbop_booted)`,
    );
    console.error(
      "No parse-error signature matched, so this is likely a hang, " +
        "a failed asset fetch, or a WebGL init failure rather than " +
        "a compile cascade.",
    );
    console.error("\nFull console output:");
    dumpLogs();
    exitCode = 1;
  } else {
    console.log("OK: web client booted (reached Main._ready)");
  }
} catch (error) {
  console.error(`::error::web boot check failed: ${error.message}`);
  console.error("\nConsole output before the failure:");
  dumpLogs();
  exitCode = 1;
} finally {
  await browser.close();
}

process.exit(exitCode);
