# H125: Muse run 6, the SP106 follow-ups

Brief for Muse's sixth run (Muse Code through Paseo), written by Claude
(claude session 0cfd9cf1) on 2026-10-31. Claude sends it, not Levi.
It holds the follow-ups from the coordinator's review of run 5 (H124):
two things the H124 brief got wrong, and one gap in SP106's new test.

How to use it: section 1, then section 2's items in order. A fresh
session resumes from this file, ledger item H125 and
`git log --oneline -15` in hopnbop and the platform. Path shorthand as
in H103: `rt:` is the platform's `runtime/`.

## 1. Rules

- H123's section 1 applies, with H125 in place of H123. That carries
  H120's rules, gates and grant: the commit and push grant, the
  public-repo rule, the one-writer rule, and a test that fails without
  the fix.
- The released-client gate runs 0.57.0 and 0.56.0. Known failures:
  H124's section 3, and the two SP106 entries in
  `.github/compliance/released-known-failures.txt`. A new failure is
  acceptable only when the fixture itself models a nameless account,
  as SP106's two did, so that a real released client is unaffected.
  Give it a dated allowlist entry that says so. Any other failure
  blocks the push.
- No client release. The fixes are runtime only and deploy with their
  push. Watch each deploy until it's green. No prod requests: Claude
  does the prod checks.

## 2. Work

Run 5 is accepted: SP106 (`8363d0c`) is right for Google, Facebook,
Apple, device and custom, and its deploy is green.

1. **SP107, Steam's generated name.** The H124 brief said Steam keeps
   the clamp alone. That was wrong: before SP106,
   `registerDisplayNameHooks` also gave a created Steam account a
   generated name (H59: every account gets one, never a provider
   name). Make Steam do all three, like Google and Facebook. Test: a
   created Steam account ends with a generated name.
2. **SP108, the nameless accounts.** The damage started well before
   SP88. H59's naming hooks (`886aa10`) reached prod on 2026-10-20,
   and privacy's after-authenticate hooks, registered after them in
   InitModule, replaced them from that deploy on. Claude's read-only
   prod count on 2026-10-31: no account created since then got a
   generated name. Apart from accounts pending deletion, all of them
   have no display name, and a few older accounts are nameless too.
   The public leaderboard hides a nameless account. No provider name
   was exposed: no Google or Facebook account was created after June.
   Fix: an existing account whose stored display name is empty gets a
   generated name when it signs in, for every provider that generates
   one, and when it refreshes its session. The SDK resumes a saved
   session through a refresh (its `core/auth_api_client.gd`,
   `_do_session_refresh`; refresh tokens last 7 days), which runs no
   after-authenticate hook, so without the refresh path a returning
   player could stay nameless. Put the refresh naming inside the
   after-session-refresh function privacy already registers
   (`rt:privacy.go`), never in a second registration: that is SP106's
   bug class. A stored name, the deletion marker included, is never
   replaced. These accounts then heal at their next sign-in or
   refresh, with no prod script.
   Tests: an existing account with an empty name ends with a generated
   name after a sign-in and after a session refresh (both fail on the
   current code); an existing account with a valid name keeps it; a
   Google account with a pending deletion that signs in ends with the
   deletion marker. That last one matters because the SP88 clamp now
   runs on live sign-ins for the first time, before privacy's
   re-clear. Use unit tests, or a check against the candidate stack
   if the database path can't be faked.
3. **SP109, one registration list.** `TestNoHookRegisteredTwice`
   (`rt:after_auth_hooks_test.go`) runs a hand-kept copy of
   InitModule's registrar list, so a registrar added to InitModule
   alone would escape it. Make InitModule call one function that
   registers every hook, and have the test call that same function.

Closing: close SP107, SP108 and SP109 in the platform ledger with their
commits. Then append your handoff entry to section 3, set H125's
`owner:` to `nobody since <time> (<why>)`, and report.

## 3. Handoff log

Append one dated entry each time you stop.

### 2026-10-31, muse 01a1908a (run 6, SP107-SP109 complete)

Done, one runtime push each, every deploy watched green
(platform SHAs are that repo's; hopnbop bumps follow):

- SP107 (platform `29e01f9`, ledger `525d045`; hopnbop
  `3eb31ce0`; deploy 41183479787). Steam does all three
  after-sign-in behaviors again, so a created Steam
  account gets a generated name. The created-Steam test
  fails on the old code (no name written) and passes
  with the fix.
- SP108 (platform `c48ab05`, ledger `32e515e`; hopnbop
  `62eee887`; deploy 41184907191). An existing account
  whose stored display name is empty gets a generated
  one at sign-in (Apple, device and custom here; the
  clamp already did this for Google, Facebook and
  Steam) and inside the after-session-refresh function
  privacy already registers, so a resumed session heals
  too. A stored name is never replaced; the
  delete-then-sign-in compliance case still ends with
  the `[deleted]` marker, which is the candidate-stack
  check for the pending-deletion case. Both healing
  tests fail on the old code and pass with the fix, so
  the nameless accounts from the SP106 window heal at
  their next sign-in or refresh with no prod script.
- SP109 (platform `457bd23`, ledger `66fd4fc`; hopnbop
  `c2fa0aa0`; deploy 41186305806). `InitModule` calls
  one `registerHooks`; `TestNoHookRegisteredTwice`
  calls that same function, so no registrar can be
  added to production without the duplicate check
  seeing it. No behavior change.

Gates per item: Go vet, test, staticcheck and
`gofmt -l runtime` pass; smoke green; the 0.57.0 suite
shows only the two SP106 allowlist entries; the
0.56.0 suite shows its classified set (the SP95
friends-delete timing case flipped once, as
documented). Full per-file GUT passes on each hopnbop
bump and every hopnbop CI run is green. No client
release and no prod actions beyond the three
sanctioned runtime deploys.

Not done: nothing in section 2. H119 still waits on
Levi's playtest log (H123 handoff), unchanged.
