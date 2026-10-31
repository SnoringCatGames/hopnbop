# H108: released client (0.56.0) against the HEAD runtime

Run 2026-10-29 by muse 01a189f7. Method: a worktree of hopnbop
`ddd8bd88` ("Release 0.56.0", platform pin `9139b38`, netcode
`33fb3138`) under `.claude/probes/H108/client-0.56.0`, submodules
initialized, its `setup-platform-addon.ps1` run. HEAD's stack came
from `scripts/local-smoke-test.ps1 -KeepStack` (HEAD suite 80/80
green in the same run), and 0.56.0's compliance suite then ran in
the worktree project against that stack with the environment the
smoke script gives the suite (including `PLATFORM_GAME_ID=hopnbop`).

Result: 80 tests, 76 passing, 4 failing. Every failure is an
intended change from run 1 (H103); no break a live 0.56.0 player
can hit was found, so nothing went under Urgent and no runtime
code changed.

## The four failures

1. `test_account_delete.gd::test_delete_clears_identifying_data_at_once`
   and 3. `test_data_export.gd::test_export_includes_every_category`:
   "profile update failed". Both fixtures set an avatar at
   `https://example.invalid/...` through `PUT /v2/account`. SP42
   (platform `d37393f`) rejects non-https or off-allowlist avatar
   hosts; the allowlist is the provider hosts
   (googleusercontent.com, fbcdn.net, fbsbx.com, steamstatic.com).
   The HEAD suite's fixtures moved to an allowlisted host in the
   same commit. A real 0.56.0 client only writes provider picture
   URLs (see `_apply_provider_profile` in the released SDK, which
   also only warns on failure), so no player flow sends an
   off-allowlist host. Intended.

2. `test_account_delete_cascade_surfaces.gd::test_delete_account_clears_all_state_surfaces`:
   the seed writes two rows to a custom storage collection as the
   client (now 403, "storage collection is not client-writable",
   SP59's allowlist in platform `3c65a1e`), and its pre-cascade
   check reads the presence row back as the client (SP36,
   platform `475d22a`, made presence rows server-only, read
   through the RPC; the test's RPC seed in step 1 passed). The
   collections a real 0.56.0 client writes are the allowlisted
   ones; the custom collection and the direct presence read are
   test-only seeding. Intended.


4. `test_party_to_matchmaking.gd::test_party_pair_matched_into_same_mock_deploy`:
   `party_start_matchmaking` returns 400 "not all party members
   are ready" (SP33's server gate, platform `0499a41`). The gate
   enforces what the 0.56.0 lobby already required: the released
   SDK has `party_set_ready` (party_api_client.gd) and
   PartyManager refuses to start while a member is unready; the
   old test simply started without readying because the server
   never checked. HEAD's suite readies both members. Intended.

5. `test_friends_account_delete_cascade.gd::test_delete_account_removes_deleter_from_other_friend_lists`
   (added 2026-10-30, SP84): step 6 asserts the deleter's
   pre-delete access token still authorizes reads ("A's session
   token from pre-delete still works"). SP84 (platform
   `5d0adce`) ends every session at delete time, which is the
   intended behavior; a fresh sign-in works, and the released
   client was driven through delete + grace-window cancel
   against that runtime with no player-visible problem (shots:
   `.claude/probes/SP84/`). Whether the released fixture fails
   on a given run depends on Nakama's issue-second revocation
   boundary, so it is listed even though it passes when sign-in
   and delete land in the same second. Intended.
## CI axis

`compliance-matrix.yml` gains a `compliance-released` job that
repeats this run on every push: it derives the released commit
from history (the newest commit whose subject starts with
`Release <x.y.z>`, so it follows the next release with no hand
edit), checks that commit out as a worktree with its own
platform pin, starts HEAD's stack via the smoke script, and runs
the released suite against it. The failures above are the
allowlist in `.github/compliance/released-known-failures.txt`;
the job fails on any other failure, and warns when an allowlist
entry stops failing (the next release's suite carries the fixed
fixtures).

## Tier C gate

Before each Tier C runtime push in H109, rerun this released
suite against the candidate runtime (the local procedure above,
or the CI job's latest run). A new failure blocks the push.
