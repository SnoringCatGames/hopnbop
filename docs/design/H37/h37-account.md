# H37 account audit

Started 2026-10-14 09:34:16 -07:00 (agent h37-account, claude session
40ecd3b7). Repos at: hopnbop 44f0093e (9bbaa7ee, a ledger-only commit, landed
on top during the audit), platform 8e85e8a, netcode 7d6ebd9.

Status labels: Verified = a run I did or a cited test that covers the case.
Believed = code reading only. Suspect = code reading says likely wrong.
Broken = reproduced or certain from code.

Paths: `game:` = hopnbop, `sdk:` =
`third_party/snoringcat-platform/addons/snoringcat_platform_client/`,
`rt:` = `third_party/snoringcat-platform/runtime/`.

My probes: `.claude/probes/H37/h37-account/test_h37_account_probe.gd`
(GUT, fake Nakama client, no network; DEL-2, LK-1, PI-1, PI-2, SO-1). Each
test asserts today's buggy behavior, so a pass reproduces the bug. Latest
run: `h37-account/gut_probe_run5.log`, 5/5 tests, 24 asserts.

## Summary (top findings, ordered)

1. **LG-1** (high, Broken in the shipped web build): the in-game Terms,
   Privacy and Data Deletion screens are blank in exported builds, because
   the export presets leave out `legal/en/*.txt`. The consent screen asks
   players to accept documents it then shows empty. One-line fix per preset.
2. **AN-1** (high, Broken by code): the guest "upgrade" signs in to the
   Google account's own account and abandons the guest's server account and
   stats, while the panel says "Keep Your Progress". The orphans are never
   purged.
3. **DEL-2** (high, Verified by probe): a failed account deletion is
   reported as a failed sign-in; the Delete panel stays busy with no message
   (the player may think it worked), and the notification socket stops.
4. **SO-1 / H15 + AN-1b** (medium-high; client side Verified at unit level
   by my probe, server side Believed): the matchmaking socket survives
   log-out and sign-in over a guest, so the next account's tickets and party
   operations go out as the previous account.
5. **AN-2** (medium-high, Broken by code): guests cannot export, delete or
   forget their server account, though the privacy and deletion texts promise
   it; the email route needs a player ID no screen shows.
6. **PI-2** (medium, Verified at unit level): avatars from an earlier match
   show on the wrong players (cache keyed by the per-server player id, kept
   until sign-out).
7. **PI-1 + DN-2** (medium; the cache's acceptance of any URL with no size
   limit or timeout is Verified at unit level by my probe, the rest
   Believed): names and avatar URLs are never
   validated; any player can set any name or image URL, every viewer's
   client fetches that URL (leaks their IP, can stall all avatar downloads),
   and in-match name, avatar and backend id are taken as the client declares
   them.
8. **SI-2 / SP12** (medium, Broken by code): Facebook sign-in and link always
   fail, yet both panels offer Facebook and the privacy text names it.
9. **DN-1** (medium, decision for Levi): the Google profile name (often a
   real name) is the display name, shown to players and on the public
   leaderboards, against TODO L50; there is no rename.
10. **LK-1** (Verified by probe, latent): a refresh that lands while a link
    waits in the browser is reported as the link's success, and the real
    code then signs in instead of linking.
11. Then: LK-4 / LK-2 (merge path dead), TD-1 (two devices unhandled), SI-1
    (non-crypto device id), DEL-3, SL-1, DX-1, AP-1, H22 (about 9 s
    log-out), H23, AN-3, SI-4, SI-6, TS-1, DEL-1, LG-2, SI-3, SI-5 / SP13.

Verified elsewhere and solid: session refresh, backoff and kept-offline
boots; consent retention and re-consent; legal_version parity; server-side
deletion, cascade and export; email privacy.

## Flows

### Sign-out (log-out, account deletion, automatic sign-out)

- Implementation: game `src/core/sign_out_router.gd` (`log_out` 71-78,
  `finish_account_deletion`, `clear_session_state` 94-121, `_on_signed_out`
  124-134, `_forget_account` 139-151). SDK `core/auth_api_client.gd`
  `_handle_refresh_failure` 1410-1442 (rejection -> `token_store.clear_session()`
  + `signed_out`), `_handle_delete_success` 1339-1344 (`clear_tokens()`).
- Finding SO-1 (H15, still true; client side Verified at unit level by my
  probe, server-side attribution Believed):
  `clear_session_state()` (sign_out_router.gd:94-121) closes the notification
  socket (`Platform.notification_socket.stop()`, :110) but never the
  matchmaking/party socket. `sdk:core/matchmaker_api_client.gd:287-289`
  `ensure_socket()` returns early whenever `_socket` is connected, without
  comparing the socket's session to the account now signed in; `_on_socket_closed`
  (:851) only prints. The only close path is `cleanup()` (:262-271), reached from
  the game only through `NakamaMatchmakerClient.cleanup()`
  (`game:src/core/nakama_matchmaker_client.gd:159-163`), and nothing in `src/`
  calls that (grep for `.cleanup()` finds only :163 itself;
  `SessionProvider.cleanup()` is a no-op base at session_provider.gd:107).
  Scenario: A plays online, logs out, B signs in on the same running client and
  queues: B's ticket and party ops go out on A's socket, so Nakama attributes them
  to A (matchmaker user id, party leader, stats attribution downstream).
  Probe `test_so1_log_out_leaves_the_matchmaking_socket_open`
  (`h37-account/test_h37_account_probe.gd`, log
  `h37-account/gut_probe_run4.log`, 4/4 with the other probes): with a
  connected socket on the matchmaking client, `SignOutRouter.log_out()`
  completes and clears the tokens, the client still holds the same socket,
  and `ensure_socket()` returns true without replacing it. The server-side
  attribution was not reproduced (needs a backend; exec agents own that).
  Shared with h37-matchmaking.
- Finding SO-2 (H22, still true, Believed): `log_out()` awaits
  `Platform.presence.announce_offline()` before `clear_tokens()`
  (sign_out_router.gd:71-78), so a slow or offline backend stalls log-out on a
  network round trip. Verified duration against the harness blackhole: about
  9 s (h37-exec-b run `20261014-094432-log-out-sign-in-cycles`, client1
  `process.log`: step 7 `log_out()` issued at about 0.8 s of process time,
  "[Toast:INFO] Logged out" and LOBBY => CONSENT at 9.79 s). Worst case on a
  real network that drops packets is about 12 s (Believed: nakama-godot
  `DEFAULT_TIMEOUT = 3` s x the adapter's 1 + 3 auto-retries,
  `addons/nakama/Nakama.gd:11`, `NakamaHTTPAdapter.gd:14-18,59-71`). The
  player sees nothing in that time.
- Case matrix:
  - Log-out in the lobby, signed in: back to Consent, tokens, consent and
    the auth file forgotten, `announce_offline` sent first, friends poller
    and notification socket stopped, friends and presence caches cleared:
    **Verified** by `test_sign_out_router.gd` (264, 273, 279, 287) and
    `log-out-sign-in-cycles` (h37-exec-b, 33/33; waits for CONSENT at line
    13, asserts lines 14-19). The party reset and the avatar cache clear
    (`sign_out_router.gd:103`, `:111`) have no test or scenario: Believed.
    (Correction: `sign-out-lobby` covers the automatic sign-out below, not
    log-out.)
  - Log-out offline or with the backend unreachable: works but takes about
    9 s with no feedback: **Verified** (H22 / SO-2 above).
  - Repeated log-out and sign-in in one process, guest in between: state
    resets each time: **Verified** by `log-out-sign-in-cycles` (h37-exec-b,
    33/33). Note what it does not cover: it signs in by writing a fake token
    into the store (scenario lines 7 and 30), not through any sign-in flow,
    and it logs the guest out through `eval` (line 25), a path the UI does
    not offer guests (AN-2). It makes no assertion about the matchmaking
    socket (SO-1).
  - Automatic sign-out (refresh rejected): consent kept, auth screen:
    **Verified** by `test_sign_out_router.gd:243` and
    `consent-kept-after-sign-out` (21/21). From the lobby: lobby torn down,
    auth screen offers sign-in, toast: **Verified** by `sign-out-lobby`
    (h37-exec-b, 13/13) and `test_sign_out_router.gd:181`.
  - Sign-out during a local match: the match finishes and auth opens after
    the results: **Verified** by h37-exec-b's 10 s copies of
    `sign-out-local-match` and `sign-out-play-again`; the committed scenarios
    fail on the 180 s match (88e3089b).
  - Sign-out during an online match: deferred by `resolve_screen` until
    results (Believed; no scenario, needs a backend).
  - Matchmaking socket closed on log-out: **Broken**, SO-1: the socket
    survives and is reused, Verified at unit level by my probe
    (`gut_probe_run4.log`); the server-side effect is Believed.
  - Party: `G.party_manager.reset()` is local only (`party_manager.gd:549-559`),
    so the server-side party still lists the logged-out account (Believed;
    whether it should leave is h37-social's call).
  - Log-out with an expired access token: the Log Out row is hidden (AP-1).
    Guest: no Log Out row at all (AN-2).
  - Second device of the same account: log-out announces "offline" for the
    whole account (TD-1).
  - Account deletion as a sign-out: consent forgotten, Consent screen:
    **Verified** (`test_consent_retention.gd:247`); a failed deletion:
    DEL-2.

### Session lifecycle (boot refresh, expiry, backoff, kept offline)

- Implementation: SDK `refresh_token()` 330-345 (guarded by `_is_refreshing`),
  `_do_session_refresh` 1089-1121, `_check_auto_refresh` 1380-1390 (store
  `needs_refresh()`: 1 h before expiry, never for guests; 60 s cooldown;
  backoff), `_handle_refresh_failure` 1410-1442 (rejection = gRPC 16/7/5 ->
  `clear_session()` keeping consent, then `signed_out`; anything else -> backoff
  5 s doubling to 300 s). Boot: SDK `ui/screens/auth_screen.gd` resumes a stored
  session and refreshes it; only a rejection signs out, anything else toasts
  `TOAST.SESSION_KEPT_OFFLINE` and continues. Before an online match:
  `game:src/core/game_session_manager.gd:189-221` (only when
  `needs_refresh()`). Mid-session sign-out:
  `game:src/core/sign_out_router.gd` (`_on_signed_out` 124-134,
  `resolve_screen` 50-65). Prod lifetimes: access 2 h, refresh 7 days
  (`infra/remote/nakama/config.yml:18-19`).
- Case matrix:
  - Boot, refresh succeeds / server error / network error / timeout /
    non-Nakama reply keeps session / rejected refresh signs out / deleted
    account signs out: **Verified** by `game:test/unit/platform/
    test_auth_screen_resume.gd` (7 tests; 7/7 passed in h37-exec-a's full GUT
    run today) and by scenario `session-kept-offline` (h37-exec-b run
    `20261014-094308`, ok 11/11).
  - Background refresh: rejection signs out and is not retried, banned
    account, a late rejection keeps a newer session, unreadable refresh token,
    transient failure keeps session and backs off, backoff doubles to the cap,
    explicit refresh skips backoff, success stores and resets backoff,
    linked providers kept: **Verified** by `test_auth_api_client_refresh.gd`
    (17/17 in exec-a's run).
  - Consent kept on automatic sign-out, forgotten on log-out and deletion,
    asked again on a legal-version change: **Verified** by
    `test_consent_retention.gd` (12/12) and scenarios
    `consent-kept-after-sign-out` (ok 21/21) and `log-out-sign-in-cycles`
    (ok 33/33), both exec-b runs.
  - Refresh before an online match, transient failure -> back to lobby still
    signed in: **Verified** (`session-refresh-before-match`, exec-b ok 19/19).
    Rejection there -> auth screen: Believed (no scenario injects a rejection).
  - Sign-out during a local match keeps the match and opens auth after
    results: the committed scenarios `sign-out-local-match` and
    `sign-out-play-again` **fail today** (exec-b: the committed match became
    180 s in 88e3089b); exec-b's copies with a 10 s match pass, so the behaviour
    is Verified and the scenarios are broken (exec-b's finding).
  - Expiry mid online match: Believed fine. The game server checks the session
    ticket only at connect; the background refresh keeps running, and a
    rejection mid-match is deferred by `resolve_screen` until the results
    screen ends.
  - Server restart: Believed fine for auth. JWTs survive a Nakama restart (same
    signing key); the notification socket reconnects; a signing-key rotation
    makes every refresh a rejection, so everyone is signed out once, consent
    kept.
  - Away more than 7 days: the refresh token has expired, the boot refresh is
    rejected and the player signs in again (`TOAST.SIGNED_OUT`). Believed, by
    design; whether Nakama rotates the refresh token on each refresh (a rolling
    window) is not checked (Nakama source not local).
- Finding H23 (still true, Believed, low): a transient refresh failure ends in
  `auth_completed.emit(false, error)` (auth_api_client.gd:1440), and
  `sdk:core/notification_socket_client.gd:321-326` stops the socket on any
  `auth_completed(false)`. With the backoff the socket stays down up to the
  next successful refresh (backoff caps at 300 s), so friend and party pushes
  pause while the catch-up polls carry on. A second trigger is DEL-2 (a failed
  deletion is reported as `auth_completed(false)`). Fix in the listener: stop
  only when the store has no valid token.
- Finding SL-1 (NEW, Believed, low-medium; touches social): every successful
  refresh, about once an hour, emits the same `auth_completed(true, "")` as a
  sign-in (`_handle_auth_success`, 1282). All subscribers treat it as a fresh
  sign-in: `global.gd:388-392` refetches and merges cloud settings,
  `party_manager.gd:562-576` re-arms its boot-time "still in a party?" check
  and restarts polling, `friends_notification_poller.gd:458-470` refetches
  friends, `account_deletion_prompt.gd:30-42` calls the deletion-status RPC
  until a prompt has shown, `profile_image_display.gd:159-165` reloads. Each is
  harmless alone; together they make an hourly refresh a sign-in replay and a
  source of surprises (a cloud-settings merge overwriting a local change made
  since the last sync is the one to check). A separate `session_refreshed`
  signal would let sign-in listeners ignore refreshes.
- Finding AN-3 (NEW, Believed, low): a guest's server calls go out with an
  expired JWT after 2 h. `game:src/core/backend_api_client.gd:528-536`
  `_ensure_session` asks for a guest JWT only when the store has none, not
  when it has expired, and guests never auto-refresh; `fetch_player_stats`,
  `fetch_player_profile`, `fetch_match_history` and the optional-session calls
  then fail with 401 until matchmaking re-authenticates
  (`get_guest_jwt` checks `is_token_valid()`, 314-320).

### Sign-in (anonymous, Google, Facebook, Steam, Apple, Epic)

- Implementation: SDK `auth_api_client.gd` `login_with_provider` 258-273,
  `login_anonymous` 300-306 (local-only identity), `get_guest_jwt` 314-320 ->
  `_do_anon_auth` 1012-1030 (Nakama device auth, create=true, vars carry
  `game_id`), desktop OAuth `_start_browser_oauth` 509-548 +
  `_poll_oauth_redirect` 551-665 (loopback 127.0.0.1:9876), web OAuth
  `_start_web_oauth` 679-722 + `_poll_web_oauth` 746-809 (popup +
  BroadcastChannel, 300 s timeout), `_do_provider_auth` 1033-1086, Google PKCE
  1581-1601 + broker exchange `_exchange_google_code_for_id_token` 1616-1663.
- Finding SI-1 (Suspect, low-medium): the anonymous device id, the only
  credential of a guest account, and the OAuth `state` nonce come from
  `_generate_state_nonce()` (auth_api_client.gd:1701-1706), which fills 16 bytes
  with `randi() % 256`: the global, non-cryptographic PCG seeded at boot
  (`game:src/core/main.gd:22 randomize()`; the engine seeds from unix time +
  ticks_usec). Anyone who can estimate a victim's first-launch time narrows the
  space far below 128 bits; the device id is also the Nakama device-auth key
  (create=true), so guessing it means signing in as that guest. The PKCE
  verifier already uses a CSPRNG (1581-1601); the same `Crypto`
  `generate_random_bytes(16)` fixes this. In agent runs `agent_driver.gd:213,727`
  calls `seed(_process_seed)`, so harness-made ids are deterministic (fine for
  tests, but shows how predictable the source is).
- Finding SI-2 (SP12, still true, Broken by code): Facebook sign-in and link pass
  the OAuth authorization `code` where Nakama expects an access token
  (auth_api_client.gd:1058-1064 and the link path; `_build_facebook_auth_url`
  1666-1678 asks for `response_type=code`). Every Facebook attempt fails at
  Nakama. The provider IS offered in hopnbop's UI: a Facebook row in
  AccountPanel (`game:src/ui/settings_panel/account_panel.gd:132-145`) and in
  UpgradeAccountPanel, so a player who picks it goes through the browser and
  then gets only a status label revert and a `push_warning` (see LK-4), no
  message. Either fix SP12 or hide the rows until it is fixed.
- Finding SI-3 (Believed): Apple is in the Provider enum (86-93) with no flow;
  Epic is a stub; Steam goes through `OS.has_feature("steam")`. Only anonymous
  and Google are live. DISTRIBUTED_SYSTEMS_PLAN M16 notes Sign in with Apple is
  mandatory on iOS once any third-party sign-in ships there.
- Finding SI-4 (Suspect, low-medium): desktop loopback OAuth is fragile:
  fixed port 9876 (a second instance or any other program on it makes sign-in
  fail), it handles only the first TCP connection, and a connection that sends
  nothing for 2 s is treated as a failure (browser preconnects and favicon
  requests are common), see `_poll_oauth_redirect` 551-665. Not reproduced:
  binding a port is reserved to the exec agents.
- Finding SI-6 (Believed, low-medium, unverified on a device): Android has
  no sign-in path of its own. The SDK branches only on web vs not-web
  (`sdk:core/auth_api_client.gd:246`), so an Android build runs the desktop
  loopback flow (a TCP server on 127.0.0.1:9876, then `OS.shell_open`).
  DISTRIBUTED_SYSTEMS_PLAN M16 (custom URI scheme, native sign-in SDKs) was
  never built. Android pauses the app while the browser is in front, so the
  redirect is read only after the player switches back, and SI-4's fragility
  applies. An Android export preset exists (`export_presets.cfg:160`).
- Case matrix:
  - Guest, first launch: a local-only identity, no server call (Believed).
  - Guest goes online: device auth with create=true and `game_id` in vars:
    **Verified** server side by compliance `auth_anon` (3/3, h37-exec-a).
  - Google, desktop (loopback, PKCE, token broker): **not run** (SP17; no
    production sign-ins here). Unit coverage: the scope asks for no email and
    the profile comes from the ID token (`test_auth_api_client_privacy.gd`,
    10/10). Port busy, second instance, early idle connection: SI-4,
    Suspect.
  - Google, web (popup, BroadcastChannel, 300 s timeout): **not run**;
    Believed. A blocked or closed popup ends only at the 300 s timeout: the
    code cannot see the popup (`window.open` returns null under COOP,
    comment at 706-709), so `_on_popup_timeout` (842-844) is the only exit
    (Believed, low).
  - Google, Android: SI-6. iOS: no build, Apple absent (SI-3).
  - Facebook: **Broken**, SI-2. Apple and Epic: not offered. Steam: only
    with the `steam` feature (not checked).
  - Offline or timeout during the code exchange: a failed sign-in, the
    player stays on the auth screen (Believed).
  - Session tokens never hold an email: **Verified** (compliance
    `email_privacy` 4/4).
  - Abuse: a predictable guest credential (SI-1, Suspect), three unhooked
    auth endpoints (SI-5 / SP13), no rate limit on account creation
    (Believed).
  - Crossplay: web and native get the same kind of Nakama session; the
    difference is only the OAuth window. Match admission is
    h37-matchmaking's (F1).

### Account linking and merge

- Implementation: SDK `link_provider` 349-366 (sets `_is_linking = true` before
  opening the browser), `_do_link` 1124-1195, `unlink_provider` 386-395 ->
  `_do_unlink` 1198-1233, `confirm_merge` 401-407 -> `_send_auth_request`
  852-876; completion routed by `_handle_auth_success` 1236-1282.
- What the game actually offers (`game:src/ui/settings_panel/account_panel.gd`
  104-145, `upgrade_account_panel.gd` 70-97, `link_account_row.gd`): a Google
  row and a Facebook row. For a guest both rows call `login_with_provider`, a
  sign-in, not a link (link_account_row.gd:74-79); for a signed-in player a row
  links (`link_provider`, :85) when not linked and unlinks when linked. So the
  only live `link_provider` call today is a Google player linking Facebook,
  which SP12 breaks anyway. Nothing in hopnbop links a provider to a guest.
- Finding LK-1 (NEW; the misrouting is Verified by my probe test, the
  sign-in-instead-of-link consequence is Believed; latent today, high impact
  once a second working provider exists or guests link, see AN-1). Probe:
  `.claude/probes/H37/h37-account/test_h37_account_probe.gd`
  `test_lk1_refresh_during_link_is_taken_for_the_link` passes (GUT 9.7.1,
  Godot 4.7.2, log `gut_probe_run2.log`): with `_is_linking` set and a
  successful refresh, `link_completed(true, "", "google")` fires,
  `auth_completed` does not, `_is_linking` is cleared and the store keeps the
  old access token. A
  background refresh that completes while a link is in its browser phase is
  taken for the link's result. `_handle_auth_success` checks `_is_linking` first
  (1240-1246): it emits `link_completed(true, ...)` for the refresh, drops the
  refreshed tokens (the `store_from_response` below is skipped), and clears
  `_is_linking`. When the browser then returns the code, `_poll_oauth_redirect`
  (640-643) and `_poll_web_oauth` (794-797) pick the endpoint from
  `_is_linking`, now false, so the code goes to sign-in (create=true): the
  player is moved to the Google account's own account (new or pre-existing)
  instead of linking it to the guest account, and the guest's progress stays on
  an account they no longer hold. Window: any `_check_auto_refresh` tick or
  explicit `refresh_token()` during the minutes a player spends in the browser
  while the access token is inside its refresh window. Sizing: prod Nakama
  issues 2 h tokens (`infra/remote/nakama/config.yml:18 token_expiry_sec:
  7200`) and `needs_refresh()` opens 1 h before expiry
  (`sdk:core/auth_token_store.gd:30,109-117`), so a running signed-in client
  refreshes about once an hour and a 1-2 minute browser trip collides a few
  percent of the time. Guests never auto-refresh (`needs_refresh()` returns false
  when `is_anonymous`). The failure path already guards against this exact
  misrouting (comment at auth_api_client.gd:1407-1409); the success path does
  not. If Nakama rotates refresh tokens on refresh, the dropped refresh also
  orphans the stored refresh token (not checked; Nakama source not local).
- Finding LK-4 (Broken by code): the link row matches AWS-era error codes that
  the Nakama path never produces. `link_account_row.gd:159` opens the merge
  panel only when `error == "PROVIDER_CONFLICT"` and :209 toasts
  `LINK.LAST_PROVIDER` only when `error == "LAST_PROVIDER"`, but every SDK
  link/unlink failure is `"<message> (status=N, grpc=M)"`
  (`_describe_nakama_exception`, auth_api_client.gd:952-956). So
  `MergeAccountPanel` is unreachable, and a link conflict (provider already on
  another account) or an unlink of the only identity ends with a status label
  reverting and a `push_warning`, no message to the player. Combined with LK-2,
  the merge UI and its strings (`MERGE.*`, which promise "Friends and stats from
  both accounts will be kept") are dead code.
- Finding LK-2 (Broken by code): merge is dead. `confirm_merge` always ends in
  `_emit_failure("Account merge is not yet wired to Nakama...")`
  (auth_api_client.gd:871-874). Archived audit P2 #16 (anon upgrade + merge UI)
  is therefore only half done; see the UI notes below for what a player sees.
- Finding LK-3 (Believed): unlink sends an empty token (1198-1233) and the client
  has no last-identity guard; Nakama itself refuses to unlink the last identity
  of an account that has no other credential (Believed from Nakama behaviour, not
  checked against its source here).
- Case matrix:
  - Link, server side (a second identity onto an account): **Verified** by
    compliance `auth_link` (2/2, h37-exec-a).
  - Signed-in Google player links Facebook (the only live link in the UI):
    **Broken**, SI-2.
  - Guest links Google: not offered; the row signs in instead (AN-1,
    Broken).
  - Link conflict (the identity already owns another account): silent
    failure, LK-4 (Broken by code); the merge it should lead to is dead
    (LK-2).
  - Unlink, including the last identity: silent on failure (LK-4); LK-3,
    Believed.
  - A refresh lands during a link: **Verified** misrouting by my probe
    (LK-1).
  - Offline or timeout during a link: `_emit_failure` routes it to
    `link_completed(false, ...)`, then LK-4's silent handling (Believed).
  - Web vs native: the same code after the OAuth window.

### Sign-in, runtime side (hooks, abuse)

- Finding SI-5 (SP13, still true, Believed): `rt:main.go` `registerAuthHooks`
  (688-784) registers BeforeAuthenticate for Device, Google, Facebook, Apple and
  Steam, plus BeforeSessionRefresh, each running `validateGameIDInVars`. Custom,
  GameCenter and FacebookInstantGame have neither a game_id hook nor a refusal,
  so with the public server key anyone can create accounts through those
  endpoints without a `game_id`, exactly SP13's list. Email is NOT open:
  `rt:privacy.go` `registerPrivacyHooks` refuses it before Nakama runs
  (BeforeAuthenticateEmail :377, BeforeLinkEmail :386). Verified: compliance
  `test_email_privacy` 4/4 in h37-exec-a's run (`test_email_sign_in_is_refused`,
  `test_email_link_is_refused`, plus the imported-email drops on sign-in and
  refresh). (An earlier draft of this file said Email was open; that was wrong.)
  The game_id hooks are not an abuse control anyway: device auth with
  create=true and a random id makes unlimited accounts by design. I found no
  rate limit on account creation in the runtime; infra rate limits are
  h37-stats-ops' ground.
- Bootstrap exemption (Believed): `requireClientSession`, `requireGameID` and
  `validateGameIDInVars` (`rt:auth.go`) pass everything when no game is
  registered. Matters only on a fresh or wiped database; prod has hopnbop
  registered.

### Anonymous accounts (guests) and the upgrade path

- Implementation: `login_anonymous()` (auth_api_client.gd:300-306) makes a
  local-only identity, `local_player_id` from `_generate_state_nonce()` (see
  SI-1). A server account exists only after something calls `get_guest_jwt()`
  (314-320 -> `_do_anon_auth` 1012-1030: Nakama device auth with that id,
  create=true), which today is matchmaking
  (`sdk:core/matchmaker_api_client.gd:612`) and
  `game:src/core/backend_api_client.gd:531`. The guest JWT lives in memory
  only: `save_tokens()` writes no JWT, refresh token or player id for guests
  (auth_token_store.gd:216-243), and `needs_refresh()` is false for guests
  (:109-111), so each process re-authenticates the same device id. A guest who
  plays online records stats under that device account
  (`rt:player_stats_test.go:116`, "A guest (no display name) records scores but
  is never listed").
- Finding AN-1 (NEW, Broken by code, high): the guest "upgrade" signs in to a
  different account and abandons the guest's server account. For guests,
  `link_account_row.gd:74-79` calls `login_with_provider`, which is
  `_do_provider_auth` with create=true (1033-1086): Nakama returns the Google
  identity's own account, new or existing. Nothing links Google to the device
  account, moves its stats, or deletes it. Yet the UpgradeAccountPanel says
  "Keep Your Progress" and promises progress synced across devices
  (`UPGRADE.HEADER`, `UPGRADE.BENEFITS_BODY` in
  `translations/ui_translations.csv`). Only device-local data survives; the
  server-side record of the guest's matches stays on an account that becomes
  unreachable once the device id is forgotten (log-out's `clear_tokens()` clears
  `local_player_id`, auth_token_store.gd:161), and nothing ever purges such
  orphans (no anonymous-account cleanup in `rt:account_cron.go`; cf. SP23). The
  SDK's `ui/screens/anonymous_upgrade_screen.gd` doc says `login_with_provider()`
  links "the anonymous account to a permanent identity", which it does not. A
  regression against the AWS-era intent recorded in the archived audit (P2 #16).
  Fix: when the guest has a device account, take the guest JWT and link Google
  to it (Nakama LinkGoogle), then decide what to do when that Google identity
  already owns an account (today's dead merge path, LK-2/LK-4).
- Finding AN-1b (NEW, H15 variant, Believed, medium): signing in from a guest
  session is not a sign-out, so `SignOutRouter.clear_session_state()` never runs.
  A guest who played online keeps a matchmaking socket authenticated with the
  guest JWT, `ensure_socket()` reuses it (matchmaker_api_client.gd:287-289), and
  the Google player's tickets and party operations then go out as the guest
  account, with no log-out involved. The H15 fix must cover every account
  change (sign-in over a guest included), not only sign-out. (The reuse
  half is the same `ensure_socket()` early return the SO-1 probe verifies;
  that the guest sign-in path skips the cleanup is code reading.)
- Finding AN-2 (NEW, Broken by code, medium-high): guests have no way to export
  or delete their server account, nor to forget the local identity. Settings
  sends guests to UpgradeAccountPanel ("Sign In") instead of AccountPanel
  (`game:src/ui/settings_panel/main_menu_panel.gd:57-75`), and that panel holds
  only the Google and Facebook rows and "Maybe Later"
  (`upgrade_account_panel.gd`). Delete, Export and Log Out exist only in
  AccountPanel, and there they also require `is_token_valid()` (148-151,
  167-169, 181-183), which for a guest holds only after this process called
  `get_guest_jwt()` and for 2 h after (`token_expiry_sec: 7200`, never
  refreshed). So a guest who played online holds a server account with their
  match stats and has no in-game export or deletion. Friends and My Stats are
  hidden for guests too (main_menu_panel.gd:77-83, 124-129). See Legal for
  what the privacy and data-deletion pages promise.
- Finding AP-1 (NEW, Believed, low-medium): the same gate hits signed-in
  players whose access token has expired, e.g. after "session kept offline" at
  launch or while a refresh is backing off: Account shows no Log Out, Delete,
  Export or link rows (104-111) until a refresh succeeds. A player on a shared
  device who is offline cannot log out. Log Out needs no server (it should only
  need `clear_tokens()`, see SO-2/H22).
- Finding TS-1 (Believed, low): the token store "encryption" passphrase is
  `OS.get_unique_id().sha256_text()` (auth_token_store.gd:302-303). It is
  obfuscation, not protection, which is fine for a user-profile file, but two
  side effects: (a) if the OS unique id changes (OS reinstall, hardware change;
  Godot's own doc warns against encrypting persistent data with it,
  `godot:doc/classes/OS.xml:559`), the file no longer decrypts: a guest loses
  the device id and with it the server account (AN-1 again), and every player
  loses consent and is asked again; (b) on web, `OS_Web::get_unique_id()` is
  `ERR_FAIL_V_MSG("", ...)` (`godot:platform/web/os_web.cpp:147-148`), so the
  key is the constant hash of "" and every save and load prints an engine
  error to the browser console (not to crash reports, which skip engine
  `ERROR:` lines).
- Guest limits as built (Believed): no notification socket for guests
  (`sdk:core/notification_socket_client.gd` `_attempt_connect` skips them), no
  leaderboard listing (no display name), no friends UI path found for them, and
  crash reports wait for an online session (H32).
- Case matrix:
  - Guest plays offline: works with no server account (Believed).
  - Guest goes online (matchmaking): a device account is made on demand:
    **Verified** server side (compliance `auth_anon` 3/3).
  - Guest after 2 h online: calls go out with an expired JWT (AN-3,
    Believed).
  - Guest "upgrade" to Google: **Broken**, AN-1 (and AN-1b for the socket).
  - Guest export, delete, forget: **Broken**, AN-2.
  - Guest identity lost (reinstall, cleared data, token file that no longer
    decrypts, TS-1): the server account is orphaned for good (Believed).
  - Guest on web: the token store key is the hash of "" (TS-1 b) and each
    save and load logs an engine error (Believed).
  - Guest log-out: possible only through `eval` (the cycles scenario does
    it); the UI offers none (AN-2).
  - Guest crash reports while offline only: expire unsent (H32).
  - Guest on leaderboards: left out (empty name, `rt:leaderboard_public.go:39`;
    Believed).
  - Abuse: unlimited guest accounts by design (SI-5), predictable guest
    credential (SI-1).

### Account deletion

- Implementation: SDK `delete_account()` (417-422) -> `_send_delete_request()`
  (879-901) -> runtime RPC `delete_account` (`rt:account.go` `deleteAccountRpc`
  198-399): a soft delete. It writes a queue record (permissions 0/0, scheduled
  30 days out), sets the profile to "[deleted]" and cascades over friends,
  groups, presence, leaderboard records, storage, references and activity. The
  hourly cron (`rt:account_cron.go`) hard-deletes due rows
  (`hardDeleteAccount` 220-235, `AccountDeleteId` with recorded=true).
  `get_account_deletion_status` and `cancel_account_deletion` serve the
  game's `AccountDeletionPrompt` (`game:src/core/account_deletion_prompt.gd`),
  which asks on sign-in whether to cancel.
- Finding DEL-2 (NEW, Verified by my probe test, high): a failed deletion is
  reported as a failed sign-in, and the Delete panel hangs. Probe:
  `test_h37_account_probe.gd`
  `test_del2_failed_delete_is_reported_as_auth_failure` passes (a 503/gRPC
  14 from the `delete_account` RPC gives `auth_completed(false, ...)` and
  no `delete_completed`). Both failure paths of `_send_delete_request`
  clear `_is_deleting` first (auth_api_client.gd:890 and :896) and then
  call `_emit_failure`, which routes on that same flag (1368-1370), so it
  falls through to `auth_completed.emit(false, error)` (1371-1372).
  `delete_completed(false, ...)` is never emitted by any path. The confirm
  panel waits on a one-shot `delete_completed`
  (`game:src/ui/settings_panel/delete_account_confirm_panel.gd:137-142`), so on
  any failure (offline, timeout, 5xx, token expired since the panel opened) it
  stays busy with the confirm row disabled and shows nothing; the player may
  believe the deletion went through. Side effect: the stray
  `auth_completed(false)` makes the notification socket `stop()`
  (`sdk:core/notification_socket_client.gd:321-326`, H23) for a signed-in player
  until the next successful refresh. Only the success path is tested
  (`game:test/unit/platform/test_consent_retention.gd:247-261`). This also
  means the H18 raw-error toast on that panel (:160-166) is unreachable.
- Finding DEL-3 (NEW, Believed, low-medium): deletion does not end the
  account's other sessions. The RPC neither bans nor logs out sessions (only a
  profile and data wipe), so a second device stays signed in, keeps refreshing
  for up to 30 days, and keeps playing; anything it records (stats, storage
  writes) is created again after "Your profile and game data are deleted right
  away" (`CONFIRM.DELETE_ACCOUNT_DETAIL`) and survives until the hard delete.
  The legal text discloses this case (privacy.txt:102-117: anything added "if
  you keep playing in the meantime" goes at the 30-day delete), and that device
  sees the cancel prompt at its next successful auth, the designed way back. So
  what remains is the in-game copy and the live second session. Revoking
  sessions on delete (Nakama `SessionLogout`/`SessionDisable`-style call) or
  rejecting writes for queued accounts would make the copy true.
- Finding DEL-1 (Believed, low): `AccountDeletionPrompt._prompt_shown_for_session`
  is set on show and on cancel success but never cleared (the comment at :20
  says "Cleared when the cancellation RPC succeeds"; :117 sets it true). It
  survives log-out, so after one prompt in a process, a different account that
  signs in later in the same process and has a pending deletion is not asked.
  The status check also runs on every successful auth until a prompt shows
  (an RPC per hourly refresh), harmless.
- Finding SP16 (still true, Believed): no call that invalidates the public
  leaderboard cache in `rt:account.go`, `account_cron.go` or `privacy.go`, so a
  deleted player's rows stay in the cached public leaderboard until it expires.
  `rt:leaderboard_public.go:39,676` does drop "[deleted]" and empty names when it
  rebuilds.
- Guest deletion: works only with an in-memory guest JWT (AN-2).
- Case matrix (deletion):
  - Happy path, server side (soft delete, cascade, cancel within 30 days,
    hard delete by the cron): **Verified** by compliance `account_delete` 4/4
    and the cascade tests (h37-exec-a) and runtime `go test` (passes).
  - Happy path, client side (consent forgotten, signed out to Consent):
    **Verified** by `test_consent_retention.gd:247-261`
    (`test_account_deletion_forgets_consent`, 12/12 in h37-exec-a's run).
  - Failure (offline, timeout, 5xx, token lapsed): **Broken**, DEL-2.
  - Retry / double submit: the RPC is repeat-safe (`rt:account.go:213-242`
    writes the queue record again with no "already pending" error): Believed.
  - Second device of the same account: **Suspect**, DEL-3.
  - Guest: **Broken**, AN-2. Deleted player still on the public leaderboard:
    SP16, Believed.

### Data export

- Implementation: SDK `export_player_data()`
  (`sdk:core/auth_api_client.gd:464-501`): an `_is_exporting` guard,
  `is_token_valid()` or "Not authenticated", then the
  `export_player_data` RPC on `Platform.nakama_client`. Success keeps the
  server's JSON text verbatim (`last_export_json`); failure emits
  `export_completed(false, <SDK error text>, {})`. Game row
  `game:src/ui/settings_panel/export_data_row.gd`: native saves to
  `user://export/` (:9, `save_export` 59-), web hands the bytes to the browser
  (`JavaScriptBridge.download_buffer`, :108). A failure goes to `G.log.error`
  (:93) and a toast that appends the raw error (:96-99).
- Case matrix:
  - Happy path, server side (the player's account, stats, storage and social
    data; crash reports left out, as privacy.txt:122-129 says): **Verified**
    by compliance `data_export` 3/3 and runtime `data_export_test.go`
    (h37-exec-a: both pass).
  - Client keeps the server's text exactly (no float re-encoding), a failed
    export leaves no stale text, the file is written verbatim under a
    timestamped name: **Verified** by `test_auth_api_client_privacy.gd:259,273`
    and `game:test/unit/ui/test_export_data_row.gd` (4 tests, 4/4 in
    h37-exec-a's run).
  - Offline: a `TOAST.EXPORT_FAILED` toast (carrying the raw SDK error,
    H18), no export text kept, and the settings menu closed: **Verified** by
    scenario `export-data-offline` (h37-exec-b, 16/16; it waits up to 30 s
    for the toast, lines 17-19). It reaches the row through a shortcut, not
    menu navigation, and asserts nothing about the screen afterwards.
  - Raw SDK error text in the toast: H18, **Verified still true**: in the
    `export-data-offline` run the toast reads "Export failed: HTTPRequest
    failed! (status=13, grpc=-1)" (h37-exec-b run
    `20261014-094346-export-data-offline`, client1 `process.log:177`).
  - Time to the failure offline: about 9 s with no progress shown (trigger
    at about 2.1 s of process time: the panel opened at 1.007 s, then two
    0.5 s waits; failure at 11.10 s, `process.log:154-177`, the backtrace
    passes through the adapter's `retry`, `NakamaHTTPAdapter.gd:71`).
    **Verified** against the harness blackhole; the same 9 s as log-out
    (SO-2).
  - Expired access token: the SDK refuses before sending; in the game the row
    is hidden until a refresh succeeds (AP-1). Believed.
  - Guest: **Broken**, AN-2 (no Export row for guests).
  - Slow server or a large export: DX-1 below, Believed.
  - Double click: `_is_exporting` drops the second request (Believed).
  - Abuse: no per-player rate limit on this heavy RPC (no limiter found in
    `rt:` for it; Believed, low). Any signed-in player can call it in a loop.
- Finding DX-1 (NEW, Believed, low-medium): export and delete run with the
  3 s HTTP timeout of `Platform.nakama_client` (`Nakama.DEFAULT_TIMEOUT`,
  `sdk:core/platform.gd:266-271`). The 60 s `_export_http_request`
  (auth_api_client.gd:217, 229-231) is created but never used, and
  `_EXPORT_ENDPOINT` / `_DELETE_ACCOUNT_ENDPOINT` (140-143) are AWS-era
  leftovers. nakama-godot's adapter retries a timed-out request up to 3 more
  times (`NakamaHTTPAdapter.gd:59-71,197-211`), so an export that takes more
  than 3 s on the server is requested 4 times (4 full server-side exports),
  then fails with the raw error (H18). Delete is repeat-safe, so a slow delete
  is only slow. Fix: a per-call timeout for export (the adapter takes one per
  client, so a second client or `rpc_async` over a longer-timeout client).
- Export failures also reach `G.log.error` (export_data_row.gd:93), and every
  `G.log.error` queues a crash report (`game:src/core/crash_reporter.gd:6-7,
  140-143`), so an offline export attempt files a crash report (low; an
  expected failure should log as a warning). **Verified**: the same exec-b
  run's editor crash queue (`crash_reports_editor.json` in its sandboxed
  appdata) holds exactly one entry, "Data export failed: HTTPRequest
  failed! (status=13, grpc=-1)". Editor builds only queue; a shipped build
  would send it (Believed).

### Legal consent and re-consent

- Implementation: game `src/ui/screens/consent_screen.gd` (99 lines) wraps the
  SDK consent screen (`sdk:ui/screens/consent_screen.gd`, with a self-declared
  13+ checkbox, `_age_checked` :83, `%AgeCheckBox` :105). The version checked
  is `LegalVersion.get_current()` (`game:src/core/legal_version.gd`): the
  server's `legal_version` from `version_check` when it has arrived, else the
  compile-time `LEGAL_VERSION`. Accept goes to Auth (or Lobby when auth is
  skipped, 63-70). The Terms and Privacy links always open the in-game
  `LegalDocScreen` (79-99), which reads `res://legal/<locale>/<file>` with an
  `en` fallback (`legal_doc_screen.gd:148-159`).
- Finding LG-1 (NEW, Broken in the shipped web build, high): the in-game
  legal documents are not in exported builds, so the Terms, Privacy and Data
  Deletion screens open blank. All four export presets use
  `export_filter="all_resources"` with `include_filter=""`
  (`game:export_presets.cfg:10,56,124,167`), which packs only resources, and
  `legal/en/*.txt` are plain text files with no `.import`. Observed: the
  production web build's pck (an unauthenticated GET of the deployed file,
  deleted after the search) holds the paths of the consent and legal-doc
  screens but no `legal/` path and none of the legal text. Local July exports
  (`build/web/index.pck`, `build/linux/hopnbop_server.pck`, both after the
  2026-03-14 commit that added `legal/`) show the same absence. Windows and
  Android: Believed (same filter). `FileAccess.get_file_as_string` on the
  missing file returns "" and prints an engine error. The consent screen asks
  the player to accept documents it links to and then shows nothing. This is
  the "works in editor" trap: every test and harness scenario runs from the
  project folder, where the files exist. Fix: `include_filter="legal/*"` in
  each preset, plus a CI step that lists the exported pck (or a GUT test that
  reads export_presets.cfg) and fails without `legal/en/privacy.txt`. TODO
  L166-168 is implemented in code but not shipped.
- Case matrix:
  - Parity of the version (game.yaml, `legal_version.gd`, production):
    **Verified**: `legal_version.gd:25` "1.2", `game.yaml:186` "1.2", and an
    unauthenticated GET of production `version_check` reports 1.2;
    `pr-validate.yml:94` fails CI on a mismatch.
  - Consent kept across sign-out, rejected refresh, ban, launch-time
    rejection; forgotten on log-out and deletion: **Verified** by
    `test_consent_retention.gd` (12/12), `test_sign_out_router.gd:243,264`
    and scenario `consent-kept-after-sign-out` (h37-exec-b, 21/21).
  - Re-consent after a legal change: **Verified** by
    `test_consent_retention.gd:276`
    (`test_kept_consent_is_asked_for_again_after_a_legal_change`).
  - Offline first launch: falls back to `LEGAL_VERSION`, so the gate works
    offline (Believed). But a player who passes the gate before
    `version_check` answers is not asked again in that session when the
    server reports a newer version: `server_legal_version` is set when the
    reply lands (`game:src/core/backend_api_client.gd:473`) and read only when the
    consent screen is shown (game `consent_screen.gd:42`). Believed, low.
  - Native client older than a legal bump: it asks for the new version but
    shows its own bundled (older) text, or none (LG-1). The release rule
    (sync the bump only with the release that ships the text) covers web,
    where every player gets the new client; installed native builds are not
    covered (Believed, low).
  - Early sync of a pending bump publishes it (documented risk in CLAUDE.md;
    no guard). Not a code bug.
  - Locales: only `legal/en/` exists; every locale falls back to English
    (Believed, fine while the text is English-only). The web pages
    (`web/{terms,privacy,data-deletion}/`) and `legal/en/*.txt` are word for
    word the same today, but nothing checks it (LG-2, low): a fix to one copy
    can silently leave the other stale. A CI diff of the normalized text would
    hold them together.
  - Age gate: a self-declared "13 or older" checkbox (TODO L303 is done). A
    box that states the expected answer is a weaker age screen than a
    neutral birth-year question; a policy question for Levi, not a bug.
  - Controller navigation of the consent screen (TODO L150, L164): not
    checked.
- What the legal text claims vs what is built (Believed unless noted):
  - privacy.txt:11, :69 and :90 name Facebook sign-in, which always fails
    (SI-2 / SP12) though the UI offers it.
  - privacy.txt:122-129 (export from Settings) and the data-deletion text
    (in-game deletion) do not hold for guests (AN-2). The email route asks
    for "your player ID" (data_deletion.txt:17-18); I found no screen that
    shows a player their ID, and a guest has no way to learn theirs.
  - privacy.txt:108 "up to about a minute" for the public leaderboard: holds
    in the normal case (60 s cache plus a 60 s browser max-age, so up to
    about 2 min in a browser), up to 10 min while the database is failing
    (SP16; `rt:leaderboard_public.go:81-90`).
  - Provider display names on leaderboards (privacy.txt:69-71): disclosed,
    see DN-1.
  - Data added by a second session after deletion: disclosed
    (privacy.txt:102-117), see DEL-3.

### Display names and usernames

- Implementation: guests get a generated name (a word plus "_" and four
  digits, `sdk:core/auth_api_client.gd:1691-1698`) that stays on the device;
  guests are not listed on leaderboards (no display name on the server
  account). Google sign-in and link copy the ID token's `name` and `picture`
  claims (`_provider_profile_from_claims` 1537-1541) into the Nakama account
  through `update_account_async` (`_apply_provider_profile` 1549-1574; on
  failure only a `push_warning`); `_do_link` forces this on every link
  (1163-1173). In a match, the client sends its own `display_name`,
  `profile_image_url` and `backend_player_id`
  (`game:src/core/game_panel.gd:109-128`), the game server stores them as
  declared (`game:src/core/edgegap_server_provider.gd:188-263`, stored
  261-263, 380-399) and relays them to every client (game_panel.gd 1687+,
  1711; `match_state_synchronizer.gd:544-569`).
- Finding DN-1 (TODO L50, medium; decision for Levi; that the client applies
  the Google name is Verified by the covering test cited below, where it is
  shown is Believed): TODO L50 says
  "Don't use Google or Apple account usernames", but the Google profile name
  IS the display name, often a real full name, and it is shown to other
  players (party, friends, recent players, the post-match list) and on the
  public leaderboards (hopnbop.net/leaderboard and in-game). privacy.txt:69-71
  discloses it. There is no rename UI, so a player cannot opt out short of
  playing as a guest. h37-triage's note on T17 (L50) says no provider-name
  claim was found by grep; that is wrong (the claims are read at 1537-1541).
  Coverage: `test_auth_api_client_privacy.gd:161`
  (`test_provider_profile_comes_from_id_token_claims`) pins today's behavior,
  so a change will need that test changed too. A fix is not client-only:
  Nakama's own provider sign-in fills an empty avatar from the provider
  (`rt:privacy.go:25-26`), so a generated or chosen name and image need a
  runtime hook (after Google auth and link) as well as a rename screen.
- Finding DN-2 (NEW, Believed, medium): no server-side validation of display
  names or avatars. The runtime registers no `BeforeUpdateAccount` hook (grep
  of `rt:`), so any signed-in player can set any `display_name` (length,
  profanity, impersonation of another player or of staff) and any
  `avatar_url` through Nakama's public UpdateAccount API, and the public
  leaderboard shows the name as stored (`rt:leaderboard_public.go` only drops
  "[deleted]" and empty names, :39). Inside a match the game server takes the
  client's declared name, avatar URL and backend id without checking them
  against the session, so a modified client can show any name or picture to
  the other players and claim another player's backend id (the same root as
  H17 and h37-matchmaking F1). The web leaderboard renders names with
  `textContent` (`game:web/leaderboard/index.html`), so no script injection
  there (Believed). Fix: a `BeforeUpdateAccount` hook (length, character
  set, a blocklist), and have the game server derive name, avatar and backend
  id from the validated session instead of the client's claims.
- Case matrix:
  - Google sign-in sets the name and picture, a cancelled deletion restores
    them, another account's profile is never applied: **Verified** by
    `test_auth_api_client_privacy.gd` (10/10 in h37-exec-a's run).
  - Email is never requested or stored: **Verified**
    (`test_google_sign_in_asks_for_no_email`, compliance `email_privacy`
    4/4).
  - A failed profile write after sign-in or link: only a `push_warning`
    (Believed, low). Nakama's own provider sign-in refills an empty avatar
    (`rt:privacy.go:25-26`), so the loss is limited.
  - Name changes on the provider side: picked up only at the next link or
    sign-in (Believed, fine).
  - Two players with the same name: allowed, no disambiguation (Believed).

### Profile images

- Implementation: `game:src/core/profile_image_cache.gd` (163 lines; 3
  pooled `HTTPRequest`s; textures cached by player id; decodes PNG, JPEG and
  WebP, 151-163). Displays: `game:src/ui/profile_image/profile_image_display.gd`
  (`set_player` 70-82, `set_from_url` 87-109, `_try_load_cached` 112-142,
  which falls back to the token store's own URL in the lobby and for local
  players, 132-139). In a match the URLs come from the server relay
  (`match_state_synchronizer.gd:544-556` -> `request_image(player_id, url)`).
- Finding PI-2 (NEW, Verified at unit level by my probe, medium; visible):
  avatars from an earlier match show on the wrong players. The cache is keyed
  by the match player id, which restarts at 1 on every game server
  (`addons/rollback_netcode/core/network_connector.gd:114`, reset at 740), and
  `request_image` returns early for any id it already holds
  (profile_image_cache.gd:52-53). It is cleared only on sign-out
  (`sign_out_router.gd:103`). So in the next match, player 1 shows the
  previous match's player 1 (or the local player's own lobby image) for the
  rest of the process. Probe
  `test_pi2_cached_avatar_ignores_a_new_url_for_the_same_id` in
  `test_h37_account_probe.gd` passes (3/3 with the other two,
  `h37-account/gut_probe_run3.log`; 4/4 in `gut_probe_run4.log`): a cached
  id keeps its texture and the new URL is never queued. The two-match
  symptom itself is Believed (needs two online matches). Fix: key by URL
  (or backend id), and clear per-match entries when a match ends.
- Finding PI-1 (NEW, medium; privacy; the cache half Verified at unit level
  by my probe, the IP leak and the stall Believed): every client downloads
  whatever avatar URL another player supplies (their Nakama `avatar_url`, or
  the URL the game server relays as declared, DN-2), with no host allowlist,
  no https requirement, no `body_size_limit` and no timeout on the pooled
  requests. A player who sets the URL to a host they control learns the IP
  address of everyone who sees their card (privacy.txt says other players
  never see IP addresses, in the leaderboard context), and a slow or endless
  response holds one of the 3 download slots for good (3 such players stall
  every avatar). A large image is decoded in memory. Fix: allow only the
  provider CDNs (Google's and Facebook's image hosts), cap the size, set a
  timeout, and have the server supply the URL (DN-2). Probe
  `test_pi1_any_avatar_url_is_accepted_without_limits`
  (`h37-account/gut_probe_run5.log`, 5/5 with the other probes): a
  plain-http URL on an arbitrary host is queued for download, and the three
  pooled requests keep HTTPRequest's defaults (`body_size_limit` -1,
  `timeout` 0, so neither limit applies).
- Case matrix:
  - Download and show a Google avatar: Believed (no test, no scenario; the
    harness has no network).
  - Download fails or the URL is empty: the tinted anonymous icon (Believed,
    `profile_image_display.gd`).
  - Party members: a tinted anonymous icon by design, keyed by `hash(uid)`
    with an empty URL, because party state carries no avatar URL
    (`game:src/ui/hud/player_display.gd:295-300`). Believed.
  - Sign-out clears the cache: Believed (one call, untested).
  - Coverage: no tests for `ProfileImageCache` or `ProfileImageDisplay`
    beyond my probe.

### Two devices signed in at once

- Finding TD-1 (TODO L112, Believed, medium): nothing prevents or handles one
  account on two devices. Production Nakama sets no `single_session`,
  `single_socket`, `single_match` or `single_party`
  (`infra/remote/nakama/config.yml`; token 7200 s, refresh 604800 s), so both
  devices stay signed in, refresh independently and hold their own sockets.
  Consequences found:
  - Presence is one row per user per game (`rt:presence.go:208-209`, read at
    256-257), so logging out on device A announces "offline" for the account
    while device B is still playing (Believed).
  - Cloud settings: last writer wins, edits clobber each other
    (h37-stats-ops, findings :134 and :160).
  - Matchmaking: both devices can queue, and session ids are `<uid>_<n>`
    with validation not enforced, so the same account in one match collides
    on a slot (h37-matchmaking F1, G1.1 and G1.3). TODO L112's "prevent at
    matchmaking time" is not done.
  - Deletion on one device leaves the other signed in and playing (DEL-3).
  - Guests cannot be on two devices (the identity is the device id), so this
    is linked accounts only.
  - Coverage: none (no test or scenario runs two clients on one account).
  - Testability: a compliance test can authenticate one account twice
    (device auth twice with the same id) and assert the presence and
    matchmaking outcome; the harness `match-2-clients` scenario could take a
    shared account once a local backend runs it.

### Coverage gaps (account area)

- No test that log-out or sign-in over a guest closes the matchmaking
  socket (H15 / AN-1b); `log-out-sign-in-cycles` could assert it. My probe
  reproduces the log-out case at unit level.
- No test for a failed `delete_account` (DEL-2) or for a refresh that lands
  during a link (LK-1); my probe reproduces both.
- No test for the guest upgrade (AN-1) or for guest export and delete
  (AN-2).
- No check that an exported build contains the legal text (LG-1).
- No suite tests for `ProfileImageCache` (PI-1, PI-2); my probe covers
  both at unit level.
- The `sign-out-local-match` and `sign-out-play-again` scenarios fail today
  only because the local match now lasts 180 s (88e3089b); their 10 s copies
  pass (h37-exec-b). Their timing needs to follow the setting.

## TODO-scratch notes in this area (a verdict for each)

Line numbers are `TODO-scratch.md` at 407c6abd.

- L17 (resting bunny on the player card): **Done** in eb4da2d3
  (2026-10-11, "hud: show the player's resting bunny on their player card",
  with a `test_player_display.gd` test). Agrees with h37-triage T05.
- L50 ("Don't use Google or Apple account usernames"): **Open, and the code
  does the opposite**: the Google profile name is the display name, shown to
  players and on public leaderboards (DN-1). Needs Levi's decision. The
  h37-triage T17 note ("no provider-name claim found by grep") is wrong.
- L82 ("Test everything with anonymous users"): **Partly done, real gaps**:
  the guest upgrade abandons the guest account (AN-1), guests cannot export,
  delete or forget their identity (AN-2), a guest session is not closed on
  sign-in (AN-1b), guest calls after 2 h (AN-3), offline guests' crash
  reports (H32).
- L112 (two devices at once; prevent at matchmaking time): **Not done**.
  Nothing prevents or handles it (TD-1); the matchmaking half is in
  h37-matchmaking F1.
- L120 ("Fix crossplay auth"): **No open sign-in bug found** that differs
  between web and native: both get the same Nakama session, and the web
  OAuth popup path has its own code (`_start_web_oauth`). The crossplay match
  admission (session tickets) is h37-matchmaking F1 (validation not
  enforced). Google sign-in has never run end to end with a real account on
  either platform (SP17), so this cannot be closed as Verified.
- L150-151 (Consent screen, Auth screen in the polish list) and L164 ("Test
  with a controller"): **Not checked** (no navigation run of these screens).
- L166-168 (in-game copies of the legal docs; offline): **Implemented but
  not shipped** (LG-1): `LegalDocScreen` reads `legal/en/*.txt`, which the
  export filter leaves out, so exported builds show blank documents online
  and offline.
- L178 (legal docs up to date): **Mostly**, version 1.2 matches the code
  except: Facebook named but broken (SP12), export and deletion promised in
  Settings but missing for guests (AN-2), an email route that needs a player
  ID nobody can see, "about a minute" for the leaderboard (SP16, roughly
  true).
- L219 (privacy and terms links on the Google and Facebook OAuth consent
  screens): **Not checkable** (needs a console sign-in).
- L250 / L252 (M2 auth flow, M4 legal and compliance): **Obsolete as
  milestones** (AWS-era plan, both marked done in the archived plan); what is
  still open sits in the items above.
- L266-307 (manual setup checklist): **Mostly obsolete** (AWS-era steps).
  Legal docs are hosted (`web/terms`, `web/privacy`, `web/data-deletion`).
  L303 "Age gate (13+) implemented in client" is **done** (the SDK consent
  screen's checkbox) though still unticked.
- L324 (where auth fits with GameLift): **Obsolete** (GameLift retired
  2026-05-03; auth is Nakama sessions plus per-match session tickets).
- L330-333 (loading text, "Auth?"): **Partly**: `game_session_manager.gd:196-200`
  emits an "authenticating" stage before a match; whether the loading screen
  shows text for it was not checked.

## Ledger items in this area (still true? fixed?)

- **H15** (matchmaking socket survives log-out): **Still true** (SO-1; the
  client side is Verified at unit level by my probe, `gut_probe_run4.log`;
  the server-side effect is Believed). Wider than the item says: a sign-in
  over a guest session hits it too (AN-1b), so the fix belongs at every
  account change.
- **H18** (raw SDK error text in toasts): **Still true** for export
  (export_data_row.gd:96-99; Verified: the `export-data-offline` run's toast
  reads "Export failed: HTTPRequest failed! (status=13, grpc=-1)") and
  merge (Believed). The delete toast is unreachable
  because failures never reach the delete panel (DEL-2). DX-1 makes the
  export toast likelier.
- **H22** (log-out waits for the offline announcement): **Still true**,
  about 9 s measured in h37-exec-b's run, about 12 s worst case.
- **H23** (notification socket stops on any failed sign-in result): **Still
  true**; DEL-2 adds a trigger (a failed delete).
- **H32** (offline-only guests' crash reports expire): **Still true**: the
  queue flushes only after `auth_completed` or `guest_jwt_obtained`
  (`crash_reporter.gd:129-130, 316`), and an offline-only guest never gets
  either.
- **SP6** (refresh retried every frame): **Done** in 8b891cd, and Verified
  by `test_auth_api_client_refresh.gd` (17/17, backoff and rejection cases).
- **SP9** (device id printed to stdout and godot.log): **Still true**
  (`sdk:core/matchmaker_api_client.gd:653`).
- **SP12** (Facebook sign-in broken): **Still true** (SI-2, by code); the
  rows are live in AccountPanel and UpgradeAccountPanel and the privacy text
  names Facebook.
- **SP13** (Custom, Game Center, Facebook Instant skip the auth hook):
  **Still true** for those three. Email is already refused
  (`rt:privacy.go:377,386`, Verified by compliance `email_privacy`).
- **SP15** (OAuth secrets in Nakama's environment, unread): **Still true** in
  the runtime (no Go code reads either variable); the host compose file was
  not re-read.
- **SP16** (deletion doesn't refresh the leaderboard cache): **Still true**
  (Believed); about 1 to 2 min normally, up to 10 min while the database
  fails.
- **SP17** (Google sign-in never run end to end): **Not checkable** here (no
  production sign-ins).
- **SP23** (phase-a creates a junk anonymous account per run): **Still true**
  (platform `scripts/phase-a.ps1:1170`, no cleanup nearby). Same class as AN-1's
  orphans: nothing purges unused anonymous accounts.
- SP24, SP25: not in this area.
- Archived `FRIENDS_PARTY_MATCHMAKING_AUDIT.md`:
  - §Auth (242-251): embedded HTTP key **fixed** (the client never holds it,
    `test_client_http_key.gd`); one global LEGAL_VERSION **fixed** (per game
    via `version_check`); the upgrade UI now exists but does not link
    (**AN-1**); the merge UI is dead (**LK-2**). The hardcoded callback and
    host lines were not re-checked.
  - §Account (253-257): `delete_account` and export **built** (Verified by
    compliance). The profile name and image are still global per account
    (no per-game name): unchanged, by design so far.
  - Edge cases (343-348): upgrade mid-party, match or queue: not handled
    (AN-1, AN-1b). Two devices: TD-1. Refresh failure with a live socket:
    H23, SL-1. Deleted in another game while present: DEL-3. Legal bump
    mid-session: no in-session re-check (Legal, low).
  - Security (371-377): SQL injection via display name not re-checked
    (Nakama parameterizes queries); names are unvalidated (DN-2).
  - P0 #4 (511) `delete_account`: **Done**. P2 #16 (540) upgrade and merge
    UI: UI built, flows broken (AN-1, LK-2).
- Archived `DISTRIBUTED_SYSTEMS_PLAN.md`: M2 (auth flow) built on Nakama
  except Facebook (SP12) and Apple (SI-3). M4 (legal) built, except the
  in-game copies do not ship (LG-1). M16 (mobile auth) never built (SI-6).

## Proposals ranked by value/effort

1. LG-1: add `include_filter="legal/*"` to the four presets, plus a CI check
   that the exported pck holds `legal/en/privacy.txt` (tiny effort, legal
   exposure today).
2. DEL-2: emit `delete_completed(false, ...)` from the delete failure paths
   (route on a local flag before clearing `_is_deleting`), and add the test
   from my probe (small).
3. H15 / AN-1b: close the matchmaking socket in SignOutRouter's shared
   cleanup and whenever the signed-in account changes; assert it in
   `log-out-sign-in-cycles` and keep my SO-1 probe as a unit test (small).
4. PI-2: key the avatar cache by URL or backend id and drop match entries at
   match end; add a cache test (small).
5. LK-1: skip `_check_auto_refresh` while linking, merging or deleting, or
   give refresh results their own route; keep my probe as the test (small).
6. SP12 / SI-2: hide the Facebook rows (and the privacy text's Facebook
   lines) until the code exchange is fixed (small).
7. AN-1: link Google onto the guest's device account (with the merge
   decision when that Google identity already has an account), so "Keep
   Your Progress" is true (medium).
8. AN-2: give guests Export, Delete and "forget this device" (medium).
9. PI-1 + DN-2: allowlist avatar hosts with a size cap and timeout; a
   `BeforeUpdateAccount` hook for names; derive in-match identity (name,
   avatar, backend id) server-side from the validated session (medium, shared
   with h37-matchmaking F1 / H17).
10. DN-1: Levi's decision on provider names; if generated names win, a
    runtime hook after Google auth and link plus a rename screen (medium).
11. Then, smaller: SI-1 (CSPRNG for the device id and state), SL-1 (a
    separate `session_refreshed` signal), H22 (clear tokens first, announce
    offline in the background), AP-1 (Log Out without a valid token), DX-1
    (longer export timeout, no auto-retry), DEL-3 (revoke sessions on
    delete), AN-3, H23, LG-2 (CI diff of web vs `legal/en` text), SI-4/SI-6
    (loopback robustness, a mobile sign-in path), DEL-1, TS-1, the two
    180 s sign-out scenarios.

Done 2026-10-14 10:38:47 -07:00
