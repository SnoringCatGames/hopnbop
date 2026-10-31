# H124: Muse run 5, the after-authenticate hook collision

Brief for Muse's fifth run (Muse Code through Paseo), written by Claude
(claude session 0cfd9cf1) on 2026-10-31. Claude sends it, not Levi.
It holds one urgent runtime fix found in the coordinator's review of
run 4 (H123), plus the answer to run 4's question.

How to use it: section 1, then section 2. A fresh session resumes from
this file, ledger item H124 and `git log --oneline -15` in hopnbop and
the platform. Path shorthand as in H103: `rt:` is the platform's
`runtime/`.

## 1. Rules

- H123's section 1 applies, with H124 in place of H123. That carries
  H120's rules, gates and grant: the commit and push grant, the
  public-repo rule, the one-writer rule, and a test that fails without
  the fix.
- The released-client gate runs both 0.57.0 and 0.56.0. Both declare
  protocol 2, so `version_check` still accepts 0.56.0.
- No client release. The fix is runtime only and deploys with its push,
  like SP103 and SP104. Watch the deploy until it's green.

## 2. Work: SP106, one after-authenticate function per provider

Nakama keeps one after-authenticate function per provider. Each
`RegisterAfterAuthenticate*` call replaces the one before it (3.25.0
`server/runtime_go.go`, a plain field assignment). `InitModule` calls
`registerDisplayNameHooks` (`rt:main.go:300`: Google, Facebook, Apple,
device, custom) and then `registerAuthNameClamp` (`:322`: Facebook,
Google, Steam). So for Google and Facebook the name clamp replaced
`assignGeneratedNameOnCreate` when SP88 (`03884fa`) deployed at
2026-10-31 01:48 UTC. Since then, a new Google or Facebook account
keeps its provider name instead of getting a generated one (H59).
Claude counted on prod: no account of any kind was created after that
deploy, so nobody needs a rename.

Fix:

- Register one after-authenticate function per provider. For Google
  and Facebook, a created account gets a generated name and an
  existing account gets the clamp. Steam keeps the clamp alone. Apple,
  device and custom keep the create path alone.
- Test, failing on the old code: run everything `InitModule` registers
  through one capturing initializer, and fail when any hook is
  registered twice. Also assert two outcomes: a created Google account
  ends with a generated name, and an existing account with an
  over-long name ends with the clamped name.
- Before the push: vet, test, staticcheck, `gofmt -l runtime`, the
  smoke test, and the 0.57.0 and 0.56.0 compliance suites against the
  candidate runtime. Then push, and watch the deploy until it's green.
- Close SP106 in the platform ledger with its commit. Then append
  your handoff entry to section 4, set H124's `owner:` to
  `nobody since <time> (<why>)`, and report.

## 3. Already reviewed: nothing to do

- Run 4 (H123) is accepted: the H119 trace, SP102, SP105, SP103,
  SP104 and the H115 check.
- Run 4's question: the two 0.56.0 failures are known and accepted.
  They are SP87's fixture entries, which `d6cf88f5` dropped from the
  released allowlist when 0.57.0 shipped. A real 0.56.0 client writes
  settings only under `global` and `game/<id>`, and never writes
  `recent_players`. In the local 0.56.0 gate, treat these as known:
  `test_settings.gd::test_storage_write_read_roundtrip`,
  `test_recent_players.gd::test_list_recent_players_sorts_by_matched_at_desc_and_caps`,
  and the SP95 timing entries. Any other failure blocks the push.

## 4. Handoff log

Append one dated entry each time you stop.
