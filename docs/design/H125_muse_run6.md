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
