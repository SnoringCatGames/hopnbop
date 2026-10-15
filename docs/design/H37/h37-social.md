# H37 social audit

Started 2026-10-14 09:34:16 -07:00. Repos at: hopnbop 9bbaa7ee (the
brief's 44f0093e plus one ledger-only commit), platform 8e85e8a,
netcode 7d6ebd9. Agent h37-social (Opus); coordinator claude session
40ecd3b7. Read-only: nothing tracked was edited. The early working
notes are kept in `h37-social/working-notes.md`; this file supersedes
them.

**Status legend.**
- Verified: a run I did, or a cited test that covers the case.
- Believed: code reading, including reading Nakama's own source.
- Suspect: code reading points to a bug that no run has confirmed.
- Broken: a run or a test shows it failing.

Citation prefixes:
- `platform:` is `third_party/snoringcat-platform/`.
- `sdk:` is `addons/snoringcat_platform_client/core/`.
- `nakama:` is the Nakama v3.25.0 source, fetched read-only with
  `gh api` into `h37-social/nakama-src/`. Production runs
  `heroiclabs/nakama:3.25.0`
  (`platform:infra/remote/nakama/docker-compose.yml:49`).

## Evidence index (runs)

- **R1: runtime Go tests.** `go test -count=1 -run <friend, party,
  presence, block and recent-player test names>` in
  `platform:runtime`. 26 tests pass, and `go vet .` is clean. They are
  all pure-function tests: codes, keys, alphabets, the limiter window,
  the presence TTL and the blocked-pair finder. No runtime test drives
  a social RPC or hook end to end.
- **R2: probe Go test.** `h37-social/runtime/probe_social_test.go`
  runs in a copy of the runtime package, with a fake initializer that
  captures `BeforeAddFriends` and a fake `FriendsList` that returns N
  outgoing (state 1) edges. Two tests, both pass:
  - with 50 outgoing requests pending, an ids-only add is refused
    ("too many pending friend requests; resolve some before sending
    more"); with 49 it passes. An ids-only add is exactly what the
    SDK's accept sends (`sdk:friends_api_client.gd:200-210`);
  - 30 ids-only adds in a row all pass the rate limit, while 2 of 12
    username adds are refused.
- **R3: GUT.** The 8 social files under `test/unit/platform/`, each run
  alone with the Godot 4.7.2 console exe and a throwaway APPDATA
  (`h37-social/run-gut.ps1`, logs in `h37-social/gut/`). All pass,
  110 tests in total:

  | File | Tests |
  |---|---|
  | friends_api_client | 13 |
  | notification_contract | 4 |
  | notification_poller | 26 |
  | poller_lifecycle | 12 |
  | party_api_client | 11 |
  | party_leave_contract | 2 |
  | party_manager | 31 |
  | party_matchmaking_context | 11 |

  They cover caches, dedup, the poller lifecycle, context building and
  leave handling. None sends a request to a backend. H35's file passes
  11/11 alone.
- **R4: harness scenario `i18n-party-strings`.** One lobby-mode run:
  single process, no port, sandboxed APPDATA, backend blackholed
  (`h37-social/harness-i18n/`). It passed, with 10 screenshots. It
  opens the party lobby panel without a session in five locales (ja,
  ru, de, zh, ar). Observed:
  - every open toasts "Not authenticated" as an error, in English, in
    all five locales (5 of 5 in `process.log`). That is H18;
  - the empty panel's two forward rows, Friends and Join with code,
    show no chevron, and Join with code uses a check-mark icon;
  - in Arabic the side panel moves to the left edge, but its rows are
    not mirrored: icons stay left and labels are left-aligned.
- **Cited: the compliance suite.** h37-exec-a ran it against a local
  Nakama 3.25.0 and got 80/80 (`h37-exec-a.md`, section 5). The social
  tests in it are listed below. Per h37-exec-a's H11 finding, the suite
  runs in CI only when someone dispatches it by hand.

  | File | Tests |
  |---|---|
  | `test_friends` | `list_returns_well_formed`, `add_nonexistent_friend_returns_known_error` |
  | `test_friends_multiuser` | `friend_request_then_accept_makes_mutual` |
  | `test_friends_block` | `block_list_lifecycle_bidirectional_add_rejection`, `blocked_pair_aborts_matchmaker_fanout` |
  | `test_presence*` | `write_returns_well_formed_response`, `rejects_unauthenticated_call`, `only_mutual_friends_appear_in_presence`, `in_match_friend_stays_visible_with_status`, `explicit_offline_hides_friend` |
  | `test_socket_presence` | `update_status_succeeds`, `follow_users_returns_snapshot` |
  | `test_recent_players` | two tests |
  | `test_party` | `party_create_and_leave_roundtrip`, solo only |
  | `test_party_invite_flow` | `invite_lifecycle_lands_invitee_as_member` |
  | `test_party_to_matchmaking` | `party_pair_matched_into_same_mock_deploy`, which uses the legacy path without `rt_party_id` |
- **Nakama source** (`h37-social/nakama-src/`): `core_group.go`,
  `core_friend.go` and `core_notification.go` at v3.25.0. Reading it is
  primary source but not a run, so claims that rest on it are
  "Believed", not inferences about Nakama.

## Summary (top findings, ordered)

1. **A party invite is a forced join.** Severity high. Believed;
   Nakama source plus code. Details: F7.
   - `party_invite` adds the target with `nk.GroupUsersAdd`
     (`platform:runtime/party.go:716-732`). Nakama inserts that edge as
     state 2, a full member (`nakama:core_group.go:687`), so no
     invitation is ever created.
   - Any active member can add any user id: there is no consent,
     friendship check, block check or rate limit.
   - The target is never asked. The accept/decline UI never runs for
     these invites, and the target can end up in two parties.
   - Each add leaves a persistent group-add notification in the
     target's inbox.
   - There are no group before-hooks, so the raw Nakama group API
     allows the same adds (F7).
   - The compliance test accepts state 2 or state 3, so it cannot
     catch this.
2. **Any member can pull everyone into a match load.** Severity
   medium-high. Believed. Details: F11.
   - `party_start_matchmaking` has no server-side ready check
     (`party.go:265-453`), and any active member may call it.
   - Each member's client then runs `client_load_game()` from wherever
     it is (`src/core/party_manager.gd:787-846`). It checks only that
     no game is loading or active: not readiness, and not which party
     the start is for.
   - With finding 1, anyone can drag any user id into a matchmaking
     load.
3. **The party creator cannot leave while anyone else is in the
   party.** Severity high. Believed; Nakama source. Details: F8.
   - Nakama refuses a leave by the last superadmin
     (`nakama:core_group.go:476-517`).
   - Transferring leadership only promotes the new leader to admin.
   - Nothing disbands a party.
   - The rejoin dialog's Leave fails the same way. The player sees the
     error as a raw toast and stays in the party.
   - A transferred leader cannot kick the creator or an earlier
     leader; the kick is a silent no-op (`core_group.go:1030-1048`).
4. **The notification poll is frozen on the oldest 50 rows, and
   nothing deletes rows.** Severity medium-high. Believed. Details: F6.
   - Every 10 s the poll lists 50 rows from a blank cursor
     (`src/core/friends_notification_poller.gd:149-153`). Nakama
     returns the oldest first (`nakama:core_notification.go:205-237`).
   - SP14 adds a row for every match, plus friend events, group adds
     and blocked-pair aborts. After about 50 matches, friend events
     that arrived while the player was offline never toast.
   - Every launch toasts old friend events again.
5. **One absent member stalls the party.** Severity medium-high.
   Believed. Details: F10 and F11.
   - Party membership survives sign-out and quit
     (`src/core/sign_out_router.gd:111` resets only local state), and
     ready rows outlive the session.
   - Start then stays disabled, or it aborts after 20 s with
     `members_never_joined`.
   - The only remedy is a kick, which fails against the creator
     (finding 3).
6. **H23 is still true, and the poll can't cover for it.** Severity
   medium. Believed. Details: F6.
   - Any failed auth result stops the socket until the next successful
     sign-in (`sdk:notification_socket_client.gd:321-327`).
   - Party start is transient-only, so the poll never sees it.
7. **50 outgoing friend requests block every accept.** Severity
   medium. Verified at the runtime-unit layer (R2). Details: F3.
8. **Friend adds by id are not rate limited** (Verified, R2), and
   party invites are not either (Believed). Severity medium. Every add,
   cancel and invite writes a persistent row and shows a toast, which
   feeds finding 4. Details: F3.
9. **Blocking stops friend requests and nothing else.** Severity
   medium. Believed. Details: F4.
   - A blocked user can still add you to a party.
   - They can read your presence row, which is public-read
     (`platform:runtime/presence.go:205-215`).
   - A blocked pair cancels whole matches for everyone in them, and
     tells all players why through a persistent `match_failed`
     notification. Shared with h37-matchmaking.
10. **Raw error text reaches players (H18 and H21, both still true),
    and in more places.** Severity medium-low. H18 is reproduced in R4:
    the party panel toasts an English "Not authenticated" in every
    locale. Details: F12.
    - The background poll reports its failures on the shared
      `request_failed` signal. While the friends panel is open, an
      outage therefore toasts a raw error every 10 s
      (`src/ui/settings_panel/friends_panel.gd:342-354`).
11. **Kick does not keep anyone out.** The party's invite code is
    reused, so a kicked member rejoins at once
    (`party.go:2129-2228, 2288-2440`). Severity medium-low. Believed.
    Details: F8.
12. **Client races.** Severity low-medium. Suspect. Details: F11 and
    F9.
    - A follower who started matchmaking cannot abort it for the
      party.
    - Two members pressing Start together split the party.
    - `fetch_party_status` responses can apply out of order.
13. **A controller-only player can't enter codes.** There is no
    on-screen keyboard (`src/` has no virtual-keyboard call), so
    friend and party codes can't be typed. Forward rows in the social
    panels also lack the chevron that `.claude/rules/ui.md:76-83`
    requires; R4 shows two of them. Severity low-medium. Believed.
    Details: F12.

## Flows

Every flow below needs the same case list. Only the cases that apply
are listed under each flow's status:
- the happy path;
- failures: offline, timeouts, an expired or revoked session, a server
  restart;
- concurrency: two devices, races, retries, idempotency;
- abuse: spoofed ids, rate limits;
- anonymous versus linked accounts;
- web versus native.

Two facts hold for every flow:
- **Anonymous players are local-only.** They have no Nakama session.
  Friends and Party are hidden from the main menu
  (`src/ui/settings_panel/main_menu_panel.gd:76-91`), and the poller,
  the socket and the party manager skip them
  (`friends_notification_poller.gd:144-145`,
  `sdk:notification_socket_client.gd:330-336`,
  `party_manager.gd:569`). For every flow, the anonymous case is
  therefore "feature absent". That is Believed, and correct.
- **Every social RPC takes its caller from the session.**
  `requireClientSession` (`platform:runtime/auth.go:39`) is called in
  each one:
  - the party RPCs (`party.go:272, 517, 653, 871, 1446, 1655, 1765,
    2056, 2295`);
  - presence (`presence.go:180`);
  - block (`block_list.go:137, 248, 317`);
  - friend codes (`friend_code.go:284, 327`).

  A spoofed caller id is therefore not possible (Believed). User ids
  in a payload are always the target, and that is by design.

### F1. Friend codes

- Implementation:
  - Game: `friends_panel.gd` builds the code row at 173-205 and copies
    it at 197-202. `add_friend_panel.gd` takes typed input through a
    `TextInputRow`.
  - Game and SDK: `src/core/backend_api_client.gd:330-350` calls
    `Platform.friends.get_my_friend_code()`, which calls the
    `get_friend_code` RPC. Adding goes through the
    `add_friend_by_code` RPC.
  - Runtime (`friend_code.go`):
    - `getOrCreateFriendCode`, 69-153;
    - the 32-symbol alphabet without I, O, 0 or 1, 36-55;
    - the generator, 253-263;
    - `resolveFriendCode`, 161-203. It normalizes with
      `ToUpper(TrimSpace)` and falls back to the Nakama username at
      191-202. The username is this project's friend code
      (`friends_notification_poller.gd` comment above
      `_resolve_sender_display_name`);
    - `add_friend_by_code`, 314-410: rate limit at 345-349, self-add
      check at 361-363, pending cap at 366-376.
- Coverage:
  - R1 covers the alphabet, the generator and normalization.
  - The compliance test `add_nonexistent_friend_returns_known_error`
    covers an unknown code.
  - Nothing covers the code row, copying, or the first-call race.
- Status:
  - Format, alphabet and normalization: Verified (R1).
  - The generator is unbiased: Believed, since 256 % 32 == 0.
  - Unknown code returns a known error: Verified (compliance, cited).
  - Add by code, happy path: Believed. I did not confirm which add path
    `test_friends_multiuser` uses.
  - Self-add is rejected: Believed.
  - Guessing a code: Believed impractical. 32^8 codes against 10 adds
    per minute per account.
  - The add always answers `request_sent` (398-408), whether the users
    were already friends, the add auto-accepted an incoming request,
    or the target had blocked the caller. Believed. This hides blocks,
    which is good, but the UI can never say "you are now friends".
  - A failure returns raw text, "failed to add friend: " + err
    (386-396). Believed; H18 class.
  - If the profile fetch fails, the code label stays "..." for as long
    as the panel is open: no retry, no error. Believed (low).
  - Two concurrent first calls can each create a forward row; the last
    reverse write wins and the loser's code still resolves. That leaves
    an orphan second code and does no other harm. Suspect (low).
  - Web clipboard: not checked.
  - Stale comment: `friends_limits.go:21-31` says codes are 6 chars;
    they are 8.
- Testability: a Go fake-`nk` harness. Extend R2's fake with
  `FriendsAdd`, `StorageRead`/`StorageWrite` and `UsersGetUsername`,
  about 1-2 h; each RPC case after that is a short unit test.

### F2. Friend requests: send, accept, decline, cancel, remove

- Implementation:
  - SDK: `friends_api_client.gd`. The add helpers pass a `source`.
    `accept_request` (200-210) re-sends `add_friends_async(ids)`.
    Reject, cancel and remove (213-222) all go through
    `_delete_friend`.
  - Game:
    - `friend_request_panel.gd`: accept and reject at 111-126; the
      panel pops on either response (82-90) and re-enables its rows on
      any `request_failed` (138-147);
    - `friends_panel.gd`: cancel at 646-657;
    - `friend_details_panel.gd`: remove and block;
    - the post-match add on `game_over_screen.gd`;
    - `recent_players_panel.gd`.
  - Runtime: the `BeforeAddFriends` hook (`friends_limits.go:144-205`).
    Nakama's AddFriends and DeleteFriends do the rest.
- Coverage:
  - Compliance `friend_request_then_accept_makes_mutual`.
  - R3 `friends_api_client` (13 tests): signal shapes and caches.
- Status:
  - Request then accept makes the pair mutual: Verified (compliance,
    cited).
  - Decline, cancel and remove: Believed. No two-user test.
  - Re-sends from two devices or retries: Believed idempotent. Nakama
    treats an add on a mutual edge as a no-op.
  - Accepting a request the sender has just cancelled: Suspect (low).
    The accept is an add, so it creates a new outgoing request. The SDK
    still emits `friend_request_accepted`, and the panel pops as if it
    succeeded.
  - Accepting from a sender who has since blocked you: Nakama silently
    does nothing and the UI shows success. Believed (low).
  - Cancel has no confirmation; the row trigger cancels at once
    (`friends_panel.gd:646-657`). Believed (low).
  - A background poll failure re-enables the accept and reject rows
    while the real request is still in flight (cross-talk, see F12).
    Believed (low).
  - Requests and accepts write persistent notifications
    (`nakama:core_friend.go:512-524`), which feed F6.
  - Accept with 50 outgoing requests pending: refused. See F3.

### F3. Limits and request abuse

- Implementation (runtime):
  - `friends_limits.go`: the sliding-window limiter, 10 adds per 60 s
    per account, in memory (79-136). The before-hook (144-205) rate
    limits only usernames and caps pending requests at 50: it counts
    `len(ids)+len(usernames)` (196) and rejects above 50 (197-201).
    `countOutgoingPending` is at 215-237.
  - `add_friend_by_code` repeats both checks itself (345-349,
    366-376), because runtime `nk.*` calls do not fire hooks.
  - `party_invite` and `party_join_by_code` have no limit.
  - `party_set_level_prefs` stores an opaque, unbounded blob
    (`party.go:1823-1860`).
- Coverage: R1 tests the limiter window; R2 tests the hook.
- Status:
  - Username adds are limited to 10 per 60 s: Verified (R1, R2).
  - Ids-only adds are not rate limited: Verified (R2).
    - Each add-and-cancel cycle by id writes a new persistent request
      row for the target and toasts them again; the toast dedup is per
      notification id. Believed.
    - Ids-only is how the SDK adds from recent players and the
      game-over screen.
  - With 50 outgoing requests pending, no incoming request can be
    accepted: Verified (R2).
    - The accept is an ids-only add, and the cap counts it as a new
      request.
    - The player sees the raw runtime message in the friends panel.
  - The limiter is in memory: Believed.
    - A deploy or restart wipes it.
    - It is per node, which is fine on prod's single node.
    - It is per Nakama account. Anonymous players have none, so a fresh
      budget needs a new linked account.
    - (The working notes' "fresh anonymous device account" line was
      wrong.)
  - Party invite spam: Believed. There is no limit, and every invite
    writes a persistent group-add row for the target (F7).
  - Guessing join codes: 32^6 codes and no limit. Believed low risk.
    Code reuse is the real issue (F8).
  - The level-prefs blob is forwarded to the game server's environment
    by the allocator. Believed (low): only the leader can set it, so it
    harms only their own party.
- Testability: R2's fake already covers the hook. A compliance case
  for "accept with 50 pending" needs 51 throwaway users on a local
  Nakama: cheap for h37-exec-a/b.

### F4. Block list

- Implementation:
  - Runtime (`block_list.go`):
    - `block_user`, 130-220. It rejects a self-block by id
      (155-158). Blocking uses Nakama's native state 3.
    - `unblock_user`, 241-290. It calls `FriendsDelete` whatever the
      edge state.
    - `list_blocked_users`, about 317 on. It reads at most 10 pages of
      100 and sets `truncated`.
  - Runtime (`fleet_allocator.go`):
    - The blocked-pair check, 807-840. It fails open when the read
      fails (821-826), which is right.
    - `abortBlockedPair`, 1670-1704. It sends a persistent
      `match_failed` with `reason=blocked_pair` to every matched
      player (1697).
  - UI: `friend_details_panel.gd` (block, with a confirm) and
    `blocked_users_panel.gd` (unblock; raw error at 122-132).
- Coverage:
  - Compliance `block_list_lifecycle_bidirectional_add_rejection` and
    `blocked_pair_aborts_matchmaker_fanout`.
  - R1 tests the pair finder.
- Status:
  - Block, add rejection in both directions, and unblock: Verified
    (compliance, cited).
  - A blocked pair aborts the match: Verified (compliance, cited).
    Its side effects are Suspect, shared with h37-matchmaking:
    - the whole match is cancelled for the bystanders too;
    - the persistent row tells everyone, the blocked player included,
      why;
    - at low population the same pair can be matched again and again;
    - two party members who block each other make every party queue
      abort.
  - A blocked user can still add you to their party (F7), with no
    check in `party.go` (grep). Believed. Combined with F11 they can
    pull you into a match load, which the blocked-pair check then
    aborts. That is a harassment loop, and every add leaves a
    persistent row.
  - A blocked user can read your presence (F5). Believed.
  - Party chat does not filter blocked users. Believed (low): it is
    party-scoped.
  - Unblocking a friend would unfriend them, but the UI offers unblock
    only on the blocked list, where every edge is a block. Believed; no
    impact.
  - A list past 1,000 blocks is truncated. Believed (low).

### F5. Presence

- Implementation:
  - Runtime (`presence.go`):
    - `update_and_get_presence`, from 180. It writes the caller's row
      with PermissionRead 2 (public) and PermissionWrite 1 (owner) at
      205-215, then reads `FriendsList(..., 100, nil, "")`, the first
      100 edges in any state, at 221-226.
    - The TTL is 90 s (73). `isPresenceVisible` is at 82-90.
  - SDK: `presence_api_client.gd`, including `announce_offline` at
    107-124.
  - Game:
    - the poller's 30 s presence poll
      (`friends_notification_poller.gd:155-160`), which sets
      `rich_presence` at 119 and 129;
    - `friends_panel.gd:586-590` shows it;
    - quit announces offline (`src/core/main.gd:428`), and so does
      sign-out (`sign_out_router.gd:73-76`).
- Coverage: the 5 presence and 2 socket-presence compliance tests, and
  R1 for the TTL.
- Status:
  - Online, in-match, explicit offline and the mutual-only filter:
    Verified (compliance, cited).
  - Staleness after a crash, a closed web tab or a lost network is
    bounded by the 90 s TTL plus the 30 s poll, so about 2 min.
    Believed. Quit's offline write is fire-and-forget, and a closed web
    tab sends nothing.
  - **The rows are public-read.** Any signed-in user can read anyone's
    presence row by user id through the storage API, blocked users and
    strangers included. Suspect (medium, privacy).
  - **The rows are owner-writable.** A client can write a future
    `updated_at` and stay "online" forever, and `rich_presence` is
    unbounded free text shown to friends. It is rendered in a plain
    Label, so there is no markup injection. Suspect (low).
  - Friends past the first 100 edges get no presence. Believed (low).
  - `rich_presence` is written already translated into the sender's
    locale, so friends see the sender's language. Believed (low, i18n).
  - Sign-out writes offline first and waits for it (H22): related, not
    re-checked.
- Testability:
  - A compliance case in which user B reads A's presence row through
    `read_storage_objects` without being A's friend. It would fail
    today, so it pins the privacy fix.
  - A GUT case for the locale.

### F6. Notification socket and HTTP poll

- Implementation:
  - SDK `notification_socket_client.gd`:
    - `start` (95) and `stop` (108);
    - backoff from 1 s up to 30 s (63, 189-194);
    - `_on_auth_completed` (321-336): on `success == false` it stops,
      and the socket stays down until the next successful
      `auth_completed`.
  - SDK `friends_api_client.gd:250-290`: `fetch_notifications(limit=50,
    cacheable_cursor="")`. On failure it emits the shared
    `request_failed` (265-267). It returns a `cacheable_cursor` that no
    caller stores.
  - Game `friends_notification_poller.gd`:
    - the 10 s poll (149-153), whether or not the socket is up;
    - dedup maps keyed by notification id (36-50);
    - the friend toasts (`_queue_friend_toast`, 254-271);
    - the first-poll flush (395-421).
  - The party manager's 60 s catch-up and its refetch on reconnect
    cover the party state.
- Coverage:
  - R3: the poller (26 tests), its lifecycle (12) and the contract (4).
    These cover dedup across socket and HTTP, start, stop and reset on
    sign-out, and the first-poll presence suppression.
  - No test runs the notification socket against a backend.
- Status:
  - Dedup across the two paths, and the poller's reset on sign-out:
    Verified (R3).
  - Live delivery over the socket: Believed. The compliance socket
    tests cover status and follow only.
  - **H23:** any failed auth result, transient refresh failures
    included, stops the socket until the next successful refresh
    (321-327). Believed. Party start, state-changed and abort (codes
    100, 101 and 102) are transient, so the poll can never deliver
    them. A follower whose socket is down misses the start, and the
    leader aborts after 20 s.
  - **The poll is frozen on the oldest 50 rows.** Believed, high
    confidence.
    - The poll lists from a blank cursor, and Nakama orders by
      `create_time ASC` (`nakama:core_notification.go:205-237`).
    - Rows are deleted only on request (308-311), and nothing in the
      SDK or the game asks (grep `delete_notifications`).
    - Persistent rows include one per match (SP14), friend requests and
      accepts, a group-add per party invite, and blocked-pair aborts.
      Once there are 50, the poll returns the same rows forever.
    - Events that arrived while the player was offline reach the
      client only through this list, since the socket pushes only new
      events. So after about 50 matches, those "request received" and
      "accepted" toasts never show. The pending-request badge still
      comes from the friends list.
    - The comment at 41-43 knows the poll re-lists from a blank cursor,
      but it assumes rows live "until read". Nakama has no read state.
  - **Every launch toasts old friend events again.** Believed.
    `_known_friend_event_ids` is in memory (44). The first poll's batch
    is shown after a delay (399-421) for every sender who is still a
    friend or pending. So "X accepted your friend request" comes back
    on every launch while that row is among the oldest 50.
  - The poll runs every 10 s even with the socket up. Each run is a
    50-row query per signed-in player, kept as a backstop. Believed.
  - The poll's `party_matchmaking_start` route
    (`_dispatch_notification`, after `_on_notifications_received`) is
    dead: party start is transient now.
  - On web, the socket is a browser WebSocket and the same code path.
    Web and native differences were not checked.
- Testability:
  - GUT, with a fake Nakama client that returns 60 notifications.
    Assert that the second poll passes the stored cursor, and that a
    relaunch does not toast rows it has already seen (fails today).
    About 30 min.
  - A compliance case that writes 51 persistent notifications and
    checks that the newest one is listed (h37-exec-a/b).
  - An H23 GUT case: emit `auth_completed(false)` while the token is
    still valid, and assert that the socket keeps reconnecting.

### F7. Party create, invite and join

- Implementation:
  - Game:
    - `src/ui/party/party_lobby_panel.gd`: the friends row (200), the
      join-by-code row (215), the invite row, shown to every member
      (393-400), and the share-code row (437);
    - `src/core/party_manager.gd`: `invite_friend` (229-266).
  - SDK (`sdk:party_api_client.gd`):
    - create calls the raw `create_group_async` (70). The group is
      closed, its size of 4 is hardcoded, and its name is `party-`
      plus `_short_id` (61-80, 617-618). The busy flag guards create
      only (54-72);
    - invite calls the `party_invite` RPC (87-94);
    - join calls the raw `join_group_async` (112);
    - join by code calls the `party_join_by_code` RPC.
  - Runtime (`platform:runtime/party.go`):
    - `party_invite` (646-752) refuses a self-invite (669) and a full
      party (686), then calls `nk.GroupUsersAdd` (716-732);
    - `resolveOrCreatePartyInviteCode` (2129-2228) makes one 6-symbol
      code per party and reuses it for the party's whole life;
    - `party_join_by_code` (2288-2440);
    - only after-hooks are registered (1184-1206): AddGroupUsers,
      JoinGroup, LeaveGroup and KickGroupUsers. Each sends a transient
      code 101 to the members; all but the add hook also clear ready
      rows.
  - Nakama (`nakama:core_group.go`): `AddGroupUsers` writes the edge
    at state 2 (687), promotes an existing state 3 edge to 2, and
    sends a persistent group-add notification (751).
- Coverage:
  - compliance `party_create_and_leave_roundtrip`, solo only;
  - compliance `invite_lifecycle_lands_invitee_as_member`. It accepts
    state 2 or state 3 (`platform:` compliance
    `test_party_invite_flow` 132-150), so it passes whichever
    semantics the server has;
  - GUT `party_api_client` (11) and `party_manager` (31): caches and
    signal plumbing (R3).
- Status:
  - Create, solo: Verified (compliance, cited).
  - Invite lands the target as a member: Verified (compliance, cited).
    That is the bug, not the feature:
    - the target is never asked. Nakama writes state 2 directly, so
      the accept and decline UI for invites never runs for RPC
      invites. Believed (Nakama source);
    - the RPC checks only self and full. There is no friendship check,
      no block check, no rate limit, and no check that the target is
      already in another party (grep of `party.go`). Believed;
    - an invited player who is offline is a member at once. On their
      next sign-in the rejoin dialog (`party_manager.gd:872-912`)
      offers to "rejoin" a party they never chose. Believed.
  - A player can be in two parties at once. The SDK keeps the first
    party it finds (`sdk:party_api_client.gd:147-170`), so the player
    sees one, while the other party lists them as an active member and
    its starts pull them in (F11). Believed.
  - The raw group API bypasses the RPC. There is no
    `BeforeCreateGroup` and no `BeforeAddGroupUsers` hook (1184-1206),
    so a modified client can:
    - create a `party-*` group of any size and openness;
    - add any user ids to it as members.

    `afterAddGroupUsersHook` (1210-1228) only notifies the members. Fixing the invite RPC alone therefore does not close the
    hole. Believed.
  - A stale one-shot invite (`party_manager.gd:229-266`). When the
    player is not in a party, `invite_friend` creates one and connects
    a one-shot lambda to `party_created` that invites the friend. If
    the create fails, the lambda stays connected. The next party the
    player creates, by any route, then invites that earlier friend too,
    and since invites are forced joins, the friend is pulled in.
    Suspect (low-medium).
  - Create a second party while the first still exists: the name comes
    from the creator's id and Nakama group names are unique, so the
    second create fails. The creator can't leave the first one either
    (F8). Two players whose ids share the first 8 hex characters also
    collide. Believed (low).
  - Join by code: Believed to work.
    - There is no friendship or block check and no rate limit.
    - It accepts a caller who holds a state 3 edge (2386-2400) and
      clears the party's ready rows (2424).
    - The code is reused for the party's life (F8).
  - Double taps: the busy flag covers create only. A repeated invite
    or join is idempotent in Nakama. Believed (low).
  - Stale comment: `party_manager.gd:615` says the leader's
    `add_group_users_async` call landed. Invites go through the RPC
    now.
- Testability:
  - Two-user compliance cases (h37-exec-a/b, local Nakama, about
    30 min each). Both fail today:
    - after an invite, the target's edge is exactly state 3, or, with
      a consent RPC, nothing changes until the target accepts;
    - a raw `AddGroupUsers` into a `party-*` group is refused.
  - A GUT case for the stale lambda: fail one create, succeed the
    next, and assert that one invite was sent.

### F8. Leave, kick, disband and leadership

- Implementation:
  - Game:
    - `party_manager.gd`: `leave_current_party` (299-302), a plain
      leave;
    - `party_lobby_panel.gd`: the leave (445, 746), kick (756) and
      transfer (769) rows, each with a confirm.
  - SDK: leave calls the raw `leave_group_async`
    (`sdk:party_api_client.gd:118-127`), and kick calls the raw
    `kick_group_users_async` (340).
  - Runtime (`party.go`):
    - `party_transfer_leadership` (864-1023) writes the leader override
      row and promotes the target one rank. It never demotes anyone
      (988-1001);
    - the LeaveGroup after-hook clears ready rows, calls
      `autoTransferIfLeaderDeparted` (from 1040; it promotes at 1123)
      and notifies;
    - `resolvePartyLeader` (800-814) returns the override row, else the
      creator.
  - Nakama (`core_group.go`):
    - `LeaveGroup` (476-517) refuses the last superadmin while other
      members remain, and deletes the group when the last superadmin
      leaves alone;
    - a kick by an admin removes only edges with state above 1, and
      silently skips the rest (1030-1048);
    - a promote moves one rank (1179-1181).
- Coverage:
  - compliance `party_create_and_leave_roundtrip`, solo;
  - GUT `party_leave_contract` (2): the client side of a leave (R3).
  - No test has two or more users leave, kick or transfer.
- Status:
  - Solo leave deletes the party: Verified (compliance, cited).
  - A member leaves: Believed to work. Ready rows are cleared and the
    members notified.
  - A leader who is not the creator leaves: Believed to work.
    Leadership passes automatically to the first active member.
  - **The creator leaves while others remain: refused.** Believed
    (Nakama source).
    - Nakama returns `ErrGroupLastSuperadmin`. The SDK emits it as a
      raw `request_failed`, and the player stays in the party.
    - This holds even after the creator hands leadership over, because
      a transfer only makes the new leader an admin. The comment above
      `autoTransferIfLeaderDeparted` ("the original creator left long
      ago") assumes a creator can leave.
    - The only ways out: every other member leaves, or the creator
      kicks them all first.
  - Disband: there is none. No RPC or UI deletes a party. Believed.
  - Kick:
    - the creator, a superadmin, can kick anyone. Believed;
    - a transferred leader, an admin, can kick members. Kicking the
      creator or an earlier leader, who are superadmin and admins, is
      a silent no-op: no error, so the UI looks done until the next
      fetch shows them still there. Believed;
    - after a transfer the creator is still superadmin, so a modified
      client can kick the current leader through the raw API. The UI
      offers kick to the leader only. Believed (low).
  - **A kick does not keep anyone out.** The invite code is reused
    (2129-2228), `party_join_by_code` has no kicked or banned list, and
    a Nakama kick deletes the edge rather than banning. A kicked member
    who has the code rejoins at once. Believed (medium-low).
  - Transfer: Believed to move the leader flag. By design (comment at
    988-994), every former leader stays an admin, so they keep the
    raw-API power to kick members and add users.
  - The rejoin dialog's Leave (`party_manager.gd:872-912`) fails for a
    creator in the same way. Believed.
- Testability: two- and three-user compliance cases. All of them fail
  or are absent today:
  - the creator leaves with a member present;
  - kick, then rejoin by code;
  - a transferred leader kicks the creator.

  `autoTransferIfLeaderDeparted` would be a short Go unit test on the
  fake `nk` harness (F1).

### F9. Party state sync and chat

- Implementation:
  - Runtime: `notifyPartyMembers` (`party.go:1346-1390`) sends a
    transient code 101 to every member listed, state 3 edges included,
    plus extra ids such as the leaver.
  - Game: the party manager refetches on code 101, every 60 s as a
    catch-up, and when the socket reconnects. `fetch_party_status`
    (`sdk:party_api_client.gd:132-170`) has no single-flight guard.
    `set_ready` patches the local member first and then calls the RPC
    (`party_manager.gd:340-347`).
  - Chat: `join_chat_group`
    (`sdk:notification_socket_client.gd:204-217`) joins the Nakama
    group channel, with persistence on.
- Coverage: GUT `party_manager` (31) covers patching, caches and
  signals (R3). No test covers ordering or chat.
- Status:
  - Members refresh after a change: Believed.
  - A missed code 101 (socket down, H23, or a backgrounded web tab) is
    repaired by the 60 s catch-up, so a member can see state up to 60 s
    old. Believed.
  - Out-of-order responses: two overlapping fetches (a 101 and the
    catch-up, or two 101s) can resolve in reverse order. The older
    snapshot then overwrites the newer one until the next fetch.
    Suspect (low-medium).
  - A failed ready RPC: nothing rolls back the optimistic patch; the
    next fetch does. Believed (low).
  - State 3 edges also receive code 101 for the party. They come only
    from a raw `JoinGroup` on a closed party. Believed (low).
  - Chat:
    - no runtime hook touches chat. The 500-character limit is
      client-only (`src/ui/party/party_chat_panel.gd:23`), and there is
      no server rate limit or block filter. Believed (low-medium);
    - messages render in plain Labels (191-192), so markup can't be
      injected. Believed;
    - the history persists with the group. Members who join later, and
      kicked members who rejoin by code, read all of it. Believed
      (low);
    - `_tear_down_chat` (`party_manager.gd:1087`) leaves the channel
      when the player leaves the party.
- Testability: a GUT case with a fake party API that resolves two
  fetches in reverse order, asserting that the newer one wins. It needs
  a sequence number or a dirty flag first.

### F10. Sign-out, offline and quit

- Implementation:
  - Sign-out (`src/core/sign_out_router.gd`) announces offline
    (73-76), stops the poller and the socket (105-116), and calls
    `party_manager.reset()` (111). That reset is local only
    (`party_manager.gd:549-559`).
  - Quit: `src/core/main.gd:428` announces offline. Nothing touches
    the party.
  - Next sign-in: `_on_auth_completed` (`party_manager.gd:562-575`)
    fetches the party, and `_show_rejoin_dialog` (872-912) offers
    Rejoin or Leave.
  - Account deletion is the one path that cleans up server-side: it
    leaves parties and removes the invite code
    (`platform:runtime/account.go:407-446, 488-502`).
- Coverage: GUT covers the poller's reset on sign-out (R3). Nothing
  covers server-side membership after sign-out or quit.
- Status:
  - **Membership outlives the session.** Sign-out, quit and a closed
    web tab leave the membership, the ready row and the leader flag in
    place. Believed. The other members then see the absent player as
    active:
    - if the absent player was not ready, Start stays disabled; the
      lobby needs everyone ready (`party_lobby_panel.gd:362-380`);
    - if they were ready, Start is enabled, the start waits 20 s for
      them, then aborts with `members_never_joined`
      (`src/core/nakama_matchmaker_client.gd:218-237`);
    - the only remedy is a kick, which fails when the absent player is
      the creator or an earlier leader (F8).
  - **Ready survives matches.** Nothing clears ready rows at match
    start or end. Only join, leave, kick, join-by-code and account
    deletion call `clearPartyReadyRows` (`party.go:2477`), and the
    client changes ready only when the player presses the row
    (`party_lobby_panel.gd:666-667`). After a match everyone is still
    ready, so any member can start the next one at once, including
    while others are still on the results screen. Believed
    (medium-low).
  - Another account signs in on the same device: the old account stays
    in the party, absent as above. Believed.
  - A network drop mid-party: the socket backs off (1-30 s) and the
    party refetches on reconnect. Meanwhile the poll's failures toast
    raw errors (F12). Believed.
  - The rejoin dialog also appears for a party the player was
    force-added to (F7), and its Leave fails for a creator (F8).
    Believed.
  - Anonymous players have no party (feature absent).
- Testability:
  - Two-user compliance cases. Both fail today:
    - member B signs out and member A starts: the start should skip B
      or mark B away;
    - a finished match clears ready rows.
  - The rejoin dialog would be a harness lobby scenario with injected
    party state; the harness has no fake party backend yet.

### F11. Party matchmaking, client side

h37-matchmaking owns tickets and allocation; this flow stops at the
client.

- Implementation:
  - Start:
    - the lobby's start row is shown to every member and is enabled
      at 2 or more active members, all ready (`party_lobby_panel.gd`
      362-380; `all_active_members_ready`, `party_manager.gd:437-449`,
      client-only);
    - `party_manager.gd:477` calls `party_start_matchmaking`
      (`party.go:265-453`). The RPC lists the active members (state 3
      skipped), resolves the leader's mode, and sends code 100 to the
      members. `LeaderID` (447) is whoever pressed Start, and
      `rt_party_id` is optional (304-311). Any member may start; that
      is intentional per the comment at 343-354, while the doc comment
      at 231-264 still says leader-only.
  - Followers:
    - `on_party_matchmaking_notification` (`party_manager.gd:787-792`)
      emits `matchmaking_started`, then `_start_party_matchmaking`
      (803-846) runs;
    - it checks only that no game is loading or active and that
      `rt_party_id` is set, then calls
      `G.game_panel.client_load_game()`;
    - the matchmaker client joins the realtime party
      (`sdk:matchmaker_api_client.gd:382-399`).
  - The starter waits up to 20 s for every member
    (`begin_rt_party_wait`, 495-520) and otherwise aborts with
    `members_never_joined` (`nakama_matchmaker_client.gd:218-237`).
  - Abort: `party_manager.gd:517-533` calls `party_abort_matchmaking`
    (`party.go:510-609`), which is leader-only and sends code 102.
- Coverage:
  - compliance `party_pair_matched_into_same_mock_deploy`, on the
    legacy path without `rt_party_id`;
  - GUT `party_matchmaking_context` (11): building the context (R3).
  - Nothing tests the realtime-party path, the abort or the 20 s wait.
- Status:
  - Legacy path: Verified (compliance, cited). Realtime-party path:
    Believed only.
  - **No server-side ready check.** Any active member can start at
    any time with a raw RPC call. The ready gate exists only in the
    client's start row. Believed.
  - **Followers load unconditionally.** The follower doesn't check:
    - that the start is for the party it shows;
    - that the player is ready;
    - that the player is on a screen where a load is expected.

    With F7, anyone can drag any player into a matchmaking load.
    Believed.
  - Every member must be online. One absent member aborts the start
    after 20 s (F10). Believed.
  - Socket down (H23): code 100 is transient, so the follower never
    learns of the start, and the starter aborts after 20 s. Believed.
  - A follower who started can't cancel it: the abort RPC is
    leader-only, so only the leader can stop the search. Suspect
    (low-medium).
  - Two members press Start at once: each RPC sends code 100 with its
    own realtime party. Each follower takes whichever arrives first
    and skips the other (the loading guard), so the party can split
    and both starts abort after 20 s. Suspect (low-medium).
  - H21: a follower whose realtime-party join fails gets two toasts
    (`nakama_matchmaker_client.gd:210-215`). Believed true.
  - `matchmaking_started` fires even when the follower skips the start
    (787-792), so a listener can show "searching" while nothing
    happens. Believed (low).
  - Dead code: the `status == "matchmaking"` branch at
    `party_manager.gd:741`. Believed (low).
- Testability:
  - GUT: feed `on_party_matchmaking_notification` a code 100 for a
    party other than the current one, and for a player who isn't
    ready. Assert no load (fails today). About 30 min with the
    existing `party_manager` test doubles.
  - Two-user compliance on the realtime-party path (h37-exec-a/b):
    start with one member signed out, and expect the abort reason.

### F12. Social UI: panels, toasts and the U/D/L/R contract

- Implementation:
  - Panels under `src/ui/settings_panel/`: friends, add friend, friend
    request, friend details, blocked users and recent players.
  - Under `src/ui/party/`: the party lobby and party chat.
  - Toasts: `src/ui/toast/`.
  - The main menu hides Friends and Party for anonymous players
    (`main_menu_panel.gd:76-91`).
- Coverage: harness scenario `i18n-party-strings`, which screenshots
  the empty party panel, a toast and the remove-friend confirm in five
  locales (R4). No test drives a social panel with input.
- Status:
  - **H18 is still true.** The SDK's `_describe`
    (`sdk:party_api_client.gd:611-614`) formats raw errors as
    `"%s (status=%d)"`, and three panels toast that text unchanged:
    - `friends_panel.gd:342-354`;
    - `party_lobby_panel.gd:649-656`;
    - `blocked_users_panel.gd:122-132`.

    Broken in R4: each time the party panel opened without a session,
    it toasted an English "Not authenticated", in all five locales.
    The friends and blocked-users panels are Believed.
  - **The background poll's failures reach the panels.** The poll
    emits the shared `request_failed` (`sdk:friends_api_client.gd`
    265-267). During an outage, the friends panel toasts a raw error
    every 10 s while it is open, and the add-friend (164-173) and
    friend-request (138-147) panels re-enable their rows while their
    own request is still in flight. Believed.
  - Dead checks: three panels compare the error with "Request in
    progress", a string nothing emits (`friends_panel.gd:350`,
    `party_lobby_panel.gd:652`, `blocked_users_panel.gd:128`).
    Believed (low).
  - Missing chevrons: rows that open another panel call `push_panel`
    without `show_chevron`, against `.claude/rules/ui.md:76-83`:
    - `friends_panel.gd:468, 545`;
    - `party_lobby_panel.gd:200, 215, 395, 408`.

    Verified for 200 and 215 (R4 screenshots); the others Believed
    (low). R4 also shows a check-mark icon on Join with code.
  - Arabic: the side panel moves to the left edge, but its rows are
    not mirrored; icons stay left and labels are left-aligned (R4).
    Low; i18n polish.
  - **No on-screen keyboard.** `text_input_row.gd` takes typed input
    only, and `src/` never shows a virtual keyboard. A player with
    only a controller can't type a friend or party code. Mobile OS
    keyboards appear on their own. Believed (low-medium).
  - Toasts: at most 5 at once (`toast_overlay.gd:10`). The alert icon
    shows only for errors (19, 55-66), and the background is black at
    60% (`toast_overlay.tscn:10`). The TODO's "Background opacity" and
    "Alert icon" are style calls, not bugs. Believed.
  - Small gaps, all Believed (low):
    - cancelling a sent request has no confirm
      (`friends_panel.gd:646-657`);
    - the friend code label stays "..." when the profile fetch fails;
    - copying the code (197-202) was not checked on web, where the
      clipboard needs a user gesture.
  - Tooltips: `src/` sets no `tooltip_text` anywhere. Godot shows
    tooltips only on mouse hover, so a controller-first UI would need
    a focus-driven hint instead.
  - U/D/L/R: the social panels are built from `MenuRow` rows, so they
    should follow the contract. No controller run was done, so this is
    Believed only.
- Testability:
  - Inject party and friends state into the harness. An eval step can
    already call panels; what is missing is a fake `Platform.party` and
    `Platform.friends`. With them, scenarios could screenshot every
    panel state and walk it with key presses. About 2-3 h once.
  - A GUT case that emits a poll failure and asserts no toast
    (fails today).

## TODO-scratch notes in this area (a verdict for each)

Line numbers refer to `TODO-scratch.md` at 9bbaa7ee.

- **L81 "Test friends presence tracking."** Partly done; keep it,
  reworded.
  - Done: compliance covers five presence cases and two socket cases
    (Verified, cited), and R1 covers the TTL.
  - Still open (F5):
    - rows are public-read, so non-friends and blocked users can read
      them;
    - a client can stay "online" forever;
    - staleness reaches about 2 min after a crash or a closed web tab;
    - friends past the first 100 edges get no presence;
    - `rich_presence` arrives in the sender's locale.

  The note can close once a "non-friend cannot read presence" case
  exists and passes.
- **L82 "Test everything with anonymous users."** (shared). For social:
  done by design.
  - Anonymous players have no Nakama session, so Friends and Party are
    hidden from the main menu, and the poller, the socket and the party
    manager skip them. Believed, from code.
  - R4 shows what happens when a party panel opens without a session
    anyway: a raw English "Not authenticated" toast.
  - Nothing pins the gate. Add one GUT case for the main-menu gate. The
    rest of this note belongs to h37-account.
- **L83 "Test party matchmaking."** (shared). Open.
  - Only the legacy path has a test.
  - Untested: the realtime-party path, aborts, the 20 s wait, absent
    members and double starts.
  - F11 lists the bugs found by reading. Its testability line gives
    the GUT and two-user compliance cases that would close this.
- **L107-108 "Let's fix the friends panel." (empty sub-bullet).** Open.
  The empty bullet names no symptom. Replace it with the concrete
  defects found:
  - raw error toasts, including one every 10 s from the background
    poll during an outage (F12, H18);
  - friend events that arrived while the player was offline never
    toast, and old ones toast again at every launch (F6);
  - no chevrons on the rows at 468 and 545;
  - cancelling a request has no confirm;
  - the code label stays "..." when the fetch fails.
- **L122-127 "Test/fix party formation, matchmaking, and lobbying".**
  Open; this is where the worst findings sit.
  - "The panel UI?": R4 renders only the empty state. No scenario
    shows a party with members, ready, kick or transfer. Chevrons are
    missing, and errors toast raw (H18). Open.
  - "Matchmaking": no server ready check, unconditional follower loads,
    absent members abort the start, double starts split the party, and
    a follower can't abort (F11). Open.
  - "Forming": invites are forced joins with no consent, block,
    friendship or rate checks. The raw API bypasses the RPC, a stale
    one-shot invite can fire later, and a player can sit in two parties
    (F7). Open; highest priority.
  - "Disbanding": there is no disband, and the creator cannot leave
    while anyone else is present (F8). Open.
  - "Who gets control?": the leader is the override row, else the
    creator. A transfer makes the new leader an admin only. The
    creator stays superadmin and can kick the leader through the raw
    API, and former leaders stay admins. Any member may start (this is
    intentional), but only the leader may abort or pick the mode. Needs
    a decision from Levi (see proposal 3).
- **L144-160 Polish.** My verdicts on the social items only; credits,
  game over, leaderboard, consent, auth and loading are other areas.
  - "friends panel": see L107.
  - "all other side-panel UI": chevrons are missing on forward rows
    (F12), and in Arabic the side panel's rows are not mirrored (R4).
  - "Toast":
    - "Background opacity": black at 60% (`toast_overlay.tscn:10`). In
      R4 it reads well over both the level and the dimmed menu. A style
      call, not a bug.
    - "Alert icon": shown for errors only (R4 shows it). That works as
      coded; whether info toasts get an icon is a design choice.
  - "Look for":
    - "Icons": Join with code uses a check mark (R4), which reads as
      "done", not "enter a code".
    - "L/R interactions": not run with input. Believed to follow
      `MenuRow`.
    - "Spacing": consistent across the five locales in R4. The German
      party-size toast is wide but fits.
    - "Should we add images anywhere?": a design question for Levi; no
      finding.
- **L164 "Test with a controller."** Open for social.
  - Blocker found: friend and party codes can't be entered without a
    keyboard, because there is no on-screen keyboard (F12).
  - The harness presses mapped actions, so a controller-equivalent walk
    of the panels becomes possible once fake party and friends state
    can be injected (F12, testability).
- **L241-242 tooltips.** Not started.
  - `src/` sets no `tooltip_text`.
  - Neither CLAUDE.md nor `.claude/rules/ui.md` mentions tooltips, so
    the sub-bullet is not done either.
  - Godot shows tooltips on mouse hover only. A controller-first game
    would want a hint line driven by focus instead. Decide the form
    before writing the rule.
- **L257 "M9: Friends System".** Done; close the line. It was delivered
  on Nakama, not on the planned DynamoDB tables (table below). The one
  missing piece is discovery through the sign-in provider; file it as
  an idea if it is still wanted.

## Ledger items in this area (still true? fixed?)

| Item | Verdict |
|---|---|
| H18 | **Still true, reproduced** (R4): the party panel toasts an English "Not authenticated" in all five locales. Also raw in the friends and blocked-users panels (`sdk:party_api_client.gd:611-614`). New, same class: the background poll's failures toast every 10 s (F12). |
| H21 | Still true by code: two emits (`src/core/nakama_matchmaker_client.gd:210-215`). Not run. |
| H23 | Still true by code (`sdk:notification_socket_client.gd:321-327`), and worse than filed. Party start, state and abort events are transient, so the poll can't stand in, and the poll is frozen anyway (F6). |
| SP14 | Still true. It is also the main reason the poll freezes (F6). Passing the cursor alone won't stop rows piling up; something must delete them. |
| SP25 | Still true, and dormant: nothing in the game calls `follow_users_async`; only a compliance test does. |
| H35 | The file passes 11/11 alone (R3). That fits a bleed between files, but I did not run the directory, so the bleed itself is not re-checked. |
| H15 | Believed still true. Sign-out stops the poller, the notification socket and the party state (`src/core/sign_out_router.gd:105-116`), but nothing on that path calls the matchmaker's `cleanup()` (`src/core/nakama_matchmaker_client.gd:159`). |
| H22 | Believed still true: `log_out` awaits `announce_offline()` before clearing tokens (`sign_out_router.gd:76`). Not re-run. |

## Archived audits

### `docs/archive/FRIENDS_PARTY_MATCHMAKING_AUDIT.md` (May)

Friends, parties and presence only; matchmaking rows belong to
h37-matchmaking.

| May finding | Verdict now |
|---|---|
| GDPR cascade on account delete | Resolved for social: deletion leaves parties and removes the invite code (`platform:runtime/account.go:407-446, 488-502`). The full verdict is h37-account's. |
| Block list missing | Resolved; the lifecycle is Verified (compliance). New gaps: parties and presence ignore blocks (F4). |
| Recent players missing | Resolved (two compliance tests, cited). |
| Pagination of friends (limit 100) | Resolved in the friends client. The presence RPC still reads only the first 100 edges (F5). |
| Per-game friend filter | Open. No impact with one game. |
| Presence `game_id` | Resolved: the key is `{game_id}/current` and the row carries `game_id` (`presence.go:31-46, 107-115`). |
| Friend code read from the legacy profile | Resolved: it now comes from the `get_friend_code` RPC. |
| Hardcoded `_OWN_GAME_ID` | Resolved. |
| Max pending requests | Resolved (a cap of 50), but the cap also blocks accepts (F3, Verified R2). |
| Online-status push | Partial. Presence still comes from a 30 s poll; the socket follow path is unused (SP25). |
| `party_start_matchmaking` missing | Resolved (`party.go:265-453`). |
| Members list never populated | Resolved. |
| `leader_id` never set | Resolved (override row, else the creator). |
| No per-game party scoping | Open, deferred (`party.go:208-212`). |
| Polling, not socket | Partial. The socket exists, but the poll fallback is frozen (F6) and can't carry transient party events (H23). |
| Invite semantics (adds at once, no pending state) | **Not resolved, and worse than described.** The RPC still adds directly, and Nakama's source shows state 2: a forced join (F7). |
| No party id in the matchmaker query | Believed resolved by the realtime party; h37-matchmaking owns it. |
| Hardcoded party size 4 | Open (`sdk:party_api_client.gd`). |
| UI breaks the SidePanel pattern | Resolved; R4 shows the side panel. |
| No invite-accepted UI | Moot. Forced joins leave nothing to accept; the rejoin dialog is the only prompt (F7). |
| Missing: chat, mode pick, ready, transfer and kick, rejoin, join by code | All delivered, each with gaps: chat has no server limits (F9), ready is client-only (F11), transfer never demotes (F8), the rejoin dialog's Leave fails for the creator (F10), and the join code never rotates (F8). |
| Missing: cross-game guard, joinable flag | Open; no impact with one game. |

### `docs/archive/DISTRIBUTED_SYSTEMS_PLAN.md` M9 (1380-1430)

| Planned | Now |
|---|---|
| DynamoDB FriendsTable | Superseded by Nakama's friend graph. |
| 8-character friend codes | Delivered: 8 symbols from a 32-symbol alphabet. A username also resolves as a code. |
| Discovery by auth provider | **Absent.** |
| Discovery from recent matches | Delivered (recent players). |
| Add, remove, list and search endpoints | Add, remove and list delivered; search means by code or username only. |
| Friends screen; post-match Add Friend | Delivered. |
| Party creation | Delivered, with F7 and F8. |
| Online status with a TTL and a 30 s poll | Delivered: 90 s TTL, 30 s poll. |
| Tests | Partial: single-user compliance cases and pure Go units only. Nothing has two users in a party. |

## Proposals ranked by value/effort

1. **Notification hygiene.** High value, low effort (about half a day).
   - Pass and store `cacheable_cursor`.
   - Delete notifications once handled, or have the runtime prune old
     ones; this also fixes SP14.
   - Keep the toast dedup across launches.
   - Poll only while the socket is down.

   Fixes F6 and finding 4.
2. **Make invites real invitations.** High value, 1-2 days.
   - A stored invitation plus an accept RPC that does the
     `GroupUsersAdd`.
   - Friendship and block checks and a rate limit on invite and
     join-by-code.
   - `BeforeCreateGroup`, `BeforeAddGroupUsers` and `BeforeJoinGroup`
     hooks that refuse raw calls on `party-*` groups, so every party
     change goes through an RPC; runtime `nk` calls skip the hooks.
   - Fix the stale one-shot invite in the same change.

   Fixes F7 and finding 1, and with proposal 4 finding 2.
3. **Leadership that can be handed over and ended.** High value, about
   1 day.
   - A `party_leave` RPC that hands superadmin on (or deletes the party
     when the leaver is alone) before leaving.
   - A `party_disband` RPC for the leader.
   - Demote on transfer (`GroupUsersDemote` exists in 3.25).
   - Ban on kick (`GroupUsersBan`), or rotate the code on kick.
   - An alternative: have the runtime own each party group (a system
     user as creator), so no player is ever superadmin.

   Fixes F8 and findings 3 and 11. Needs Levi's call on "who gets
   control" (L127).
4. **Server-side start checks.** High value, about half a day.
   - `party_start_matchmaking` refuses unless every active member is
     ready and recently present, refuses a second start while one is
     pending, and clears ready rows on start.
   - The follower checks the start's party id and its own readiness
     before loading.

   Fixes the core of F11, finding 2 and most of finding 5.
5. **Fix H23.** Medium value, about 1 h. Stop the socket only on a real
   sign-out; keep reconnecting through a transient refresh failure.
   Add the GUT case from F6.
6. **Absent members.** Medium value, about half a day. Sign-out leaves
   the party (needs proposal 3 for the creator), or the start skips
   members whose presence is stale. Clear ready at match end.
7. **Presence privacy.** Medium value, about 2 h.
   - Write rows with read and write permission 0 and serve them only
     through the RPC.
   - Stamp `updated_at` on the server.
   - Cap `rich_presence`, and drop blocked users from results.
8. **Rate limits and the pending cap.** Medium value, about 2 h.
   - Limit adds by id, exempting accepts.
   - Exempt accepts from the cap of 50.
   - Limit invites and joins by code.
9. **Error surfacing.** Medium value, about half a day.
   - Per-operation failure signals in the SDK, or an operation tag on
     `request_failed`.
   - Map known errors to `tr()` keys.
   - Never toast background-poll failures.
   - Remove the dead "Request in progress" checks.

   Fixes H18, the poll toasts and the row cross-talk.
10. **Client races.** Low-medium value, about half a day.
    - Single-flight plus a dirty flag for `fetch_party_status`.
    - Let the member who started abort.
    - Pair with proposal 4's double-start refusal.
11. **Controller input.** Medium value, about 1 day.
    - An on-screen keyboard for `TextInputRow`. Codes use a 32-symbol
      alphabet, so a small grid of `MenuRow`s is enough.
    - Add the missing chevrons (15 min).
    - Replace the Join-with-code icon.
    - Mirror rows for RTL locales.
12. **Test seams that let Claude run these cases unattended.** These
    enable the rest.
    - A Go fake-`nk` harness for RPC unit tests (1-2 h; R2 is its
      start).
    - Two-user compliance cases (h37-exec-a/b style, 3-4 h in total).
      All but the first fail today:
      - invite state;
      - creator leave;
      - kick then rejoin;
      - start with an absent member;
      - accept with 50 pending;
      - 51 notifications;
      - a non-friend reads presence.
    - A fake `Platform.party` and `Platform.friends` for harness UI
      scenarios (2-3 h).
    - Run the compliance suite on a schedule (h37-exec-a's H11).

## Could not check

- **Live two-user flows.** My brief allows no Docker and no ports.
  Every multi-user case marked Believed needs a run by h37-exec-a/b or
  a later one: invite state, creator leave, kicks, absent members,
  double starts.
- **Web.** Nothing ran on web: the clipboard, the socket in a
  background tab, closing a tab.
- **A controller walk of the social panels.** R4 only takes
  screenshots.
- **Production.** Not touched.
- **Other agents' areas.** The interplay of guests and recent players
  is left to h37-account; tickets and allocation behind party starts
  to h37-matchmaking.

Done 2026-10-14 10:25:28 -0700.
