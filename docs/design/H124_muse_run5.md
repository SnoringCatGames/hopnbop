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

### 2026-10-31, muse 01a1908a (run 5, SP106 complete)

Done (platform SHAs are that repo's):

- SP106 (platform `8363d0c`, ledger `82adcbf`; hopnbop
  bump `0c62694a`). One after-authenticate function per
  provider now runs all three behaviors:
  `registerAfterAuthenticateHooks` assigns a generated
  name to a created account, clamps an existing
  Google/Facebook/Steam account's name, and runs
  sign-in privacy on every sign-in.
  `registerDisplayNameHooks` and `registerAuthNameClamp`
  are gone; `registerPrivacyHooks` keeps its link,
  refresh and delete hooks. The runtime deploy
  (run 41180324301) and both hopnbop CI runs on the
  bump (PR Validate 41181122235, Compliance Matrix
  41181122244) are green.
- One correction to section 2's account of the bug: a
  counting probe against the old code shows three
  registrars, not two. Privacy is called after the
  clamp in `InitModule`, so its hooks were the actual
  survivors (Google, Facebook and Steam registered
  three times each, Apple and Device twice, Custom
  once). Generated names at creation and the clamp
  were shadowed for every provider privacy covers,
  not only Google and Facebook. The fix therefore
  merges privacy's sign-in work too, which the brief's
  outcome for Steam ("the clamp alone") requires to
  be registered anywhere at all. A live probe against
  the candidate stack confirms the restored behavior:
  a fresh device account came back with the generated
  name `LuckyStoat_5159`.
- Tests: `TestNoHookRegisteredTwice` runs every hook
  registration `InitModule` makes through one capturing
  initializer and fails on any duplicate; outcome tests
  assert a created Google account ends with a
  generated name and an existing one ends clamped.
  Go vet, test, staticcheck and `gofmt -l runtime`
  pass. Smoke is 95/95: the two fixtures that modeled
  a nameless account now clear the generated name
  through the console. The 0.57.0 suite reports 94
  with only the two released-fixture failures, which
  earned dated allowlist entries in hopnbop (they come
  out with the next client release). The 0.56.0 suite
  shows its classified set: the four documented
  intended failures, the two SP87 fixture drifts from
  section 3, and the same two SP106 fixture failures.
  Full per-file GUT passes on the hopnbop bump.
- Production: no account was created between the SP88
  deploy and this fix (the coordinator's count), so
  no existing account carries a provider name and no
  retroactive rename or migration is needed; the fix
  covers new sign-ups only. No client release and no
  prod actions beyond the sanctioned runtime deploy.

Not done: nothing in section 2. H119 still waits on
Levi's playtest log (H123 handoff), unchanged.
