# Hop 'n Bop: Backend & Distributed Systems Master Plan

---

Manual Steps (User)
Before the code works end-to-end, you need credentials for at
least one provider. You can test with anonymous auth
immediately. For OAuth providers, register apps at:

Google: console.cloud.google.com (free)
Discord: discord.com/developers (free)
Twitch: dev.twitch.tv (free)
Apple: developer.apple.com ($99/yr)
After registering, update the Secrets Manager secrets with
real client IDs and secrets.

Verification
Deploy backend: sam build then sam deploy
Test anonymous auth:

Invoke-RestMethod -Method Post `
  -Uri https://4xol3ejva9.execute-api.us-west-2.amazonaws.com/prod/auth/anon `
  -Body '{"device_id":"test-device-123"}' `
  -ContentType 'application/json'
Should return JWT + refresh token + player_id.
Test refresh:

Invoke-RestMethod -Method Post `
  -Uri .../prod/auth/refresh `
  -Body '{"player_id":"...","refresh_token":"..."}' `
  -ContentType 'application/json'
Run client in editor → splash → auth screen appears
Click "Play Anonymously" → get token → navigate to lobby
Close and reopen → cached token skips auth screen

---

### M2: Complete Auth Flow

**Goal**: End-to-end authentication from client through backend,
all 6 OAuth providers + anonymous + refresh tokens.

**What's included**:

*Backend changes*:
- Add Google, Apple, Discord, Twitch to auth_service.py
- Add anonymous auth endpoint (POST /auth/anon) that generates
  device-based player ID and issues limited JWT
- Add refresh token endpoint (POST /auth/refresh)
- Add account linking endpoint (POST /auth/link) to upgrade
  anonymous → authed or add providers to existing account
- Store refresh tokens in DynamoDB Players table
- Migrate secrets from SAM parameters to Secrets Manager
- Add version check field to login response

*Client changes*:
- Auth screen UI (provider selection buttons, anonymous play option)
- Token storage (local file, encrypted)
- Token refresh logic (auto-refresh before expiry)
- Version check on auth response (force update if mismatch)
- Settings flag for cached auth (support start_in_game with
  stored token)
- Loading screen status updates during auth flow

*New API endpoints*:
- POST /auth/anon — Generate anonymous player ID
- POST /auth/refresh — Refresh expired token
- POST /auth/link — Link provider to existing account
- GET /auth/version — Return required client version

**Key files to modify**:
- `backend/src/handlers/auth_handler.py` — Add endpoints
- `backend/src/services/auth_service.py` — Add 4 providers
- `backend/template.yaml` — Add Lambda functions, secrets refs
- `src/core/settings.gd` — Add auth-related settings
- `src/ui/screens/` — New auth screen scene
- `src/core/game_session_manager.gd` — Integrate auth before
  matchmaking
- `src/ui/screens/loading_screen.gd` — Status messages

**OAuth provider setup** (manual steps for each):
- **Google**: Create project in Google Cloud Console, enable
  OAuth2, create credentials, note client ID/secret
- **Apple**: Apple Developer account ($99/yr), create App ID,
  enable Sign In with Apple, create Services ID, generate key
- **Discord**: Create application at discord.com/developers,
  add OAuth2 redirect, note client ID/secret
- **Twitch**: Create application at dev.twitch.tv, add OAuth2
  redirect, note client ID/secret
- **Steam**: Already have Steam Web API key (existing code)
- **Epic**: Need Epic Games developer account

**Testing**:
- Unit tests for each provider's token validation
- Integration test: client → auth → receive JWT → connect to
  server with JWT
- Test anonymous flow: play without auth, get device ID
- Test account linking: anonymous → link Google → verify stats
  preserved
- Test refresh: let token expire, verify auto-refresh works
- Test version mismatch: server returns "update required"

---

### M3: GameLift Container Fleet Deployment

**Goal**: Deploy game server to GameLift container fleet with
Spot instances and Anywhere mode for local testing.

**What's included**:
- Dockerfile for Godot headless server (Linux)
- ECR repository for container images
- GameLift container fleet definition
- Mixed Spot + On-Demand fleet configuration
- GameLift Anywhere fleet for local testing
- Deployment script (build container → push to ECR → update fleet)
- Server-side session validation (verify player JWT with backend)
- Graceful shutdown on Spot reclamation (2-min warning → finish
  match or return players to lobby)

**Server transport**:
- Primary: ENet listener on port 4433 (native desktop clients)
- Secondary: WebSocket listener on port 4434 (web/mobile clients)
- Both listeners feed into the same Godot multiplayer API via
  transport abstraction layer

**Key files to modify/create**:
- `Dockerfile` (new) — Godot headless server container
- `gamelift-deploy/` — Deployment scripts
- `addons/rollback_netcode/core/network_connector.gd` — Transport
  abstraction (line 150 TODO)
- `addons/rollback_netcode/core/network_settings.gd` — Transport
  config
- `addons/gamelift_session_manager/server/gamelift_server_provider.gd`
  — Container fleet integration
- `.github/workflows/deploy-server.yml` (new) — CI/CD

**Manual steps**:
1. Create ECR repository:
   `aws ecr create-repository --repository-name hopnbop-server`
   (works in both bash and PowerShell)
2. Create GameLift container fleet via AWS Console or CLI
3. Configure Spot + On-Demand priority in fleet queue
4. Set up Anywhere fleet for local dev (already partially done)
5. Test local Anywhere mode: run server in Docker locally
6. Test cloud deployment: push container, verify fleet activates

**Testing**:
- Local: Docker build → run → connect from editor in preview mode
- Anywhere: Register local machine → connect via GameLift API
- Cloud: Deploy to fleet → matchmake → play a full match
- Spot reclamation: Simulate with fleet draining → verify graceful
  disconnect

---

### M4: Legal & Compliance

**Goal**: Draft and publish all required legal documents before
collecting real user data in production.

**Documents needed**:
1. **Privacy Policy** — Required by law (GDPR, CCPA, etc.), app
   stores, and OAuth providers
   - What data is collected (player ID, display name, gameplay
     stats, device ID, OAuth tokens)
   - How data is used (matchmaking, leaderboards, auth)
   - Data retention period
   - Third-party services (AWS, OAuth providers)
   - Data deletion and export rights (GDPR Article 17 & 20)
   - Children's privacy (13+ age gate, no COPPA)
   - Contact info: Snoring Cat LLC
   - Hosting: hopnbop.net/privacy

2. **Terms of Service / EULA** — Required by app stores
   - License grant (free, non-commercial use)
   - User conduct (no cheating, no harassment)
   - Account termination rights
   - Disclaimer of warranties
   - Limitation of liability
   - Governing law (your state)
   - Age requirement (13+)
   - Hosting: hopnbop.net/terms

3. **Data Deletion Policy** — Required by GDPR, CCPA, app stores
   - How to request deletion (in-game + email)
   - What gets deleted (all player data, stats, friends, settings)
   - Timeline (within 30 days)
   - Hosting: hopnbop.net/data-deletion

**Additional compliance**:
- Age gate: Client shows "I am 13 or older" checkbox before
  account creation
- GDPR consent: Accept privacy policy before data collection
- CCPA: "Do not sell my data" notice (even though you don't sell
  data, California requires the notice)
- Apple App Store: Privacy Nutrition Labels
- Google Play: Data Safety section

**Not needed** (since no monetization):
- Refund policy
- Payment terms
- Tax compliance documents

**Manual steps**:
1. Draft documents (Claude can help generate initial drafts)
2. Have a lawyer review (recommended but not strictly required
   for a free non-monetized game)
3. Host on hopnbop.net
4. Add links in-game (settings menu, first-launch flow)
5. Add links in app store listings

**Ongoing maintenance**:
- Update privacy policy when adding new data collection
- Review annually for legal changes
- Respond to data deletion requests within 30 days
- Respond to data export requests within 30 days

---

### M5: Monitoring, Logging & Alerting

**Goal**: Production visibility into server health, player
experience, and costs.

**What's included**:

*CloudWatch Dashboards*:
- Server metrics: CPU, memory, active connections, match count
- GameLift metrics: active sessions, available sessions, player
  sessions
- API metrics: request count, error rate, latency (p50/p99)
- DynamoDB metrics: read/write capacity, throttle events

*CloudWatch Alarms → SNS → Email*:
- Server CPU > 80% for 5 minutes
- API error rate > 5% for 5 minutes
- GameLift available sessions < 2 (scaling trigger)
- DynamoDB throttle events > 0
- Lambda errors > 0 for 5 minutes
- Monthly cost exceeds budget threshold

*Game Analytics*:
- Custom CloudWatch metrics: match_started, match_completed,
  player_connected, player_disconnected, auth_success, auth_failure
- Analytics DynamoDB table for session events (optional, deferred)

*Client Crash Reporting*:
- Godot autoload script catches unhandled errors
- Sends crash data (stack trace, player ID, OS, game version,
  frame index) to POST /telemetry/crash endpoint
- Lambda logs to CloudWatch Logs with structured JSON
- Alarm on crash rate > threshold

*AWS Cost Management*:
- AWS Budgets: $25/month alert, $50/month alert
- Cost Explorer tags for per-service breakdown

**Key files to create/modify**:
- `backend/template.yaml` — Add telemetry Lambda, SNS topic,
  CloudWatch alarms
- `src/core/crash_reporter.gd` (new) — Client-side crash capture
- `backend/src/handlers/telemetry_handler.py` (new)

**Manual steps**:
1. Create SNS topic, subscribe your email
2. Create CloudWatch dashboard via Console or CloudFormation
3. Configure alarms in template.yaml
4. Enable DynamoDB PITR for all tables
5. Set up AWS Budgets alerts

**Testing**:
- Trigger an intentional error, verify alarm fires and email sent
- Verify dashboard shows real-time metrics
- Trigger client crash, verify it appears in CloudWatch Logs

---

### M6: Matchmaking Enhancements

**Goal**: Production-quality matchmaking with progressive
relaxation, party queue, and play-again flow.

**What's included**:

*FlexMatch Ruleset*:
```
Phase 1 (0-15s):  Strict region, prefer same auth+platform
Phase 2 (15-30s): Relax platform preference
Phase 3 (30-45s): Relax auth status preference
Phase 4 (45-60s): Widen region tolerance
Timeout (60s):    "No matches found" message
Min players: 2    Max players: 8    Target: 4
```

*Party Queue*:
- Backend: Accept party_id in matchmaking request
- Backend: FlexMatch team-based matching for parties
- Client: Party creation UI, invite friends, party lobby
- Client: All party members submit matchmaking together

*Play Again Flow*:
- After match ends, show "Play Again?" prompt to all players
- Server collects votes, if majority yes → re-queue group
- Players who decline return to lobby
- Server starts new matchmaking ticket for remaining group

*Friend from Recent Match*:
- After match ends, show other players with "Add Friend" button
- Recent match players visible for 10 minutes
- Client stores recent match player list locally

*Loading Screen Updates*:
- "Authenticating..." (during auth)
- "Finding other players..." (during matchmaking)
- "Connecting to server..." (during server connection)
- "Waiting for players..." (connected, waiting for match start)
- "No matches found. Try again?" (on timeout)

**Key files to modify**:
- `backend/src/handlers/matchmaking_handler.py` — Party support
- `backend/template.yaml` — FlexMatch ruleset configuration
- `src/core/game_session_manager.gd` — Party + play-again logic
- `src/ui/screens/loading_screen.gd` — Status messages
- `src/ui/screens/` — Post-match screen with play-again + friending
- `addons/rollback_netcode/core/network_connector.gd` — Party
  connection coordination

**Testing**:
- Test progressive relaxation: connect 2 players, verify match
  starts without waiting for 8
- Test timeout: connect 1 player, verify "no matches" after 60s
- Test party: 2 friends queue together, verify same match
- Test play-again: finish match, both vote yes, verify re-queue
- Test different phases: verify platform/auth preferences relax

---

### M7: Database & Player Persistence

**Goal**: Full player profiles, settings sync, match history,
and data export.

**What's included**:

*Extended DynamoDB Schema*:
```
PlayersTable:
  player_id (PK)
  display_name
  friend_code (unique, GSI)
  device_id (for anonymous, GSI)
  auth_providers: {steam: id, google: id, ...}
  first_play_time
  last_play_time
  total_time_played_sec
  total_matches_played
  total_wins
  # All PlayerMatchStats fields as lifetime totals:
  total_kills, total_deaths, total_bumps
  total_crown_time, total_jumps
  total_water_count, total_ice_count, total_spring_count
  total_direction_changes
  total_snail_crushes, total_cricket_disturbances
  total_fish_disturbances, total_butterfly_disturbances
  total_fly_proximity_time, total_poop_count
  created_at
  updated_at

SettingsTable (new):
  player_id (PK)
  settings_json (all persisted settings)
  updated_at

MatchHistoryTable (exists, wire up):
  player_id (PK)
  timestamp (SK)
  level_id, duration, player_count
  placement, kills, deaths, bumps
  per-player stats snapshot

FriendsTable (new): → covered in M9
LeaderboardTable (new): → covered in M8
```

*New API Endpoints*:
- GET /player/profile — Full player profile with stats
- PUT /player/settings — Save settings to cloud
- GET /player/settings — Read settings from cloud
- GET /player/export — GDPR data export (all tables as JSON)
- DELETE /player — GDPR data deletion (all tables)
- GET /player/history — Last 5 match results

*Client Changes*:
- Settings persistence manager: save to local file AND call
  PUT /player/settings when authed
- On login: fetch cloud settings, merge (cloud wins conflicts)
- Profile screen: show lifetime stats, match history
- Account linking UI: add/remove providers
- Account deletion flow: confirm → call DELETE /player → logout
- Settings book visibility: track rounds played (local count),
  hide until >= 3

*Server Changes*:
- After match ends, server calls backend API to record match
  results and update player lifetime stats
- Send PlayerMatchStats data to backend with match results

**Key files to modify/create**:
- `backend/template.yaml` — New tables, new Lambda functions
- `backend/src/handlers/player_handler.py` (new)
- `backend/src/services/player_service.py` — Extend
- `src/core/settings.gd` — Settings sync logic
- `src/core/settings_persistence.gd` (new) — Local + cloud sync
- `src/ui/screens/` — Profile screen, account management
- Match end flow in server code — Report results to backend

**Testing**:
- Change setting on client A, login on client B, verify setting
  synced
- Play 3 matches, verify match history shows all 3
- Verify lifetime stats accumulate correctly
- Test GDPR export: verify JSON contains all player data
- Test GDPR deletion: verify all tables cleared
- Test settings book hidden for first 3 rounds

---

### M8: Leaderboards

**Goal**: All-time and weekly leaderboards with friend filtering.

**What's included**:

*DynamoDB Schema*:
```
LeaderboardTable:
  leaderboard_id (PK): "alltime#global", "weekly#2026-W09",
                        "alltime#level_0", "weekly#level_0#2026-W09"
  player_id (SK)
  score (wins, or composite score)
  display_name
  rank (computed)

  GSI: leaderboard_id + score (for sorted queries)
```

*API Endpoints*:
- GET /leaderboard?type=alltime&scope=global&page=1
- GET /leaderboard?type=weekly&scope=level_0&page=1
- GET /leaderboard?type=alltime&scope=global&player_id=X
  (returns page containing player X)
- GET /leaderboard/friends?player_id=X&type=alltime

*Weekly Reset*:
- CloudWatch Events rule triggers Lambda weekly (Monday 00:00 UTC)
- Archives previous week's leaderboard
- Creates new weekly leaderboard entry

*Client*:
- Leaderboard screen: global page 1 + friends list + local
  player context page
- Toggle: all-time vs weekly
- Toggle: global vs per-level
- Friends filter overlay

**Key files to create**:
- `backend/src/handlers/leaderboard_handler.py`
- `backend/src/services/leaderboard_service.py`
- `src/ui/screens/leaderboard_screen.gd`

**Testing**:
- Play matches, verify score updates on leaderboard
- Verify weekly reset clears weekly board
- Verify friend-filtered view shows only friends
- Verify pagination works

---

### M9: Friends System

**Goal**: Add, remove, and view friends. Queue with friends.

**What's included**:

*DynamoDB Schema*:
```
FriendsTable:
  player_id (PK)
  friend_id (SK)
  created_at
  source: "friend_code" | "recent_match" | "provider"

  (Bidirectional: adding a friend creates two rows)
```

*Friend Discovery*:
- By unique friend code (8-char alphanumeric, generated at
  account creation, stored in PlayersTable)
- By auth provider info (e.g., Steam username lookup)
- From recent match (last 10 minutes, stored client-side)

*API Endpoints*:
- POST /friends/add — Add by friend_code or player_id
- POST /friends/remove — Remove friend (both directions)
- GET /friends — List all friends with online status
- GET /friends/search?code=ABCD1234 — Lookup by friend code

*Client*:
- Friends list screen (name, online/offline/in-match status)
- Add friend dialog (enter friend code)
- Post-match: "Add Friend" button next to each player
- Party creation: select friends → create party → matchmake

*Online Status*:
- Server reports connected player list to backend periodically
- Backend tracks online/in-match status in a TTL-based DynamoDB
  item or simple in-memory cache
- Friends list polls every 30 seconds

**Key files to create**:
- `backend/src/handlers/friends_handler.py`
- `backend/src/services/friends_service.py`
- `src/ui/screens/friends_screen.gd`
- `src/ui/screens/party_lobby_screen.gd`

**Testing**:
- Add friend by code, verify appears in both players' lists
- Remove friend, verify removed from both sides
- Verify online status updates when friend connects/disconnects
- Create party with friend, matchmake, verify same match
- Post-match: add random player as friend, verify works

---

### M10: Web Build & Cross-Play

**Goal**: Web clients connect via WebSocket alongside native
ENet clients in the same match.

**What's included**:

*Transport Abstraction Layer*:
- New `TransportFactory` that creates the appropriate
  MultiplayerPeer based on platform/config
- Web builds: `WebSocketMultiplayerPeer`
- Native builds: `ENetMultiplayerPeer`
- Server: dual-listener (both protocols simultaneously)
- Architect interface so WebRTC can replace WebSocket later

*Dual-Listener Server*:
- Option A (recommended): Use Godot's `SceneMultiplayer` to run
  two multiplayer instances, bridge messages internally
- Option B: Custom low-level networking that accepts both
  protocols and unifies at the RPC layer
- Both feed into the existing NetworkFrameDriver/rollback system

*Web Build Optimization*:
- Export preset already exists for Web (HTML5/Emscripten)
- CORS configuration on API Gateway (already enabled)
- Asset compression for web delivery
- Loading screen for web (show progress while WASM loads)

*Network Connector Changes*:
- Replace hardcoded `ENetMultiplayerPeer.new()` at line 121-122
  and 152-153 with `TransportFactory.create_peer()`
- Add `transport_type` setting (AUTO, ENET, WEBSOCKET)
- AUTO: detect platform → web=WebSocket, native=ENet
- WebSocket port configuration (4434)

**Key files to modify/create**:
- `addons/rollback_netcode/core/network_connector.gd` — Transport
  abstraction (the line 150 TODO)
- `addons/rollback_netcode/core/transport_factory.gd` (new)
- `addons/rollback_netcode/core/network_settings.gd` — Transport
  config
- `src/core/settings.gd` — WebSocket port, transport selection
- Export presets — Verify web export works

**Testing**:
- Build web export, load in browser, connect to local server
- Native client + web client in same match
- Verify rollback/reconciliation works identically on both
- Test under simulated packet loss (web should handle gracefully)
- Performance profiling on web (60 FPS network tick feasible?)

---

### M11: Offline Mode / Local Multiplayer

**Goal**: Multiple players on one device without network
connectivity.

**What's included**:
This is the multi-player-per-client architecture from the
DELETE_ME doc. Major subsystems:

*Input Device Manager*:
- New InputDeviceManager singleton
- Map physical devices to logical players:
  - Gamepad 1 → Player 1
  - Gamepad 2 → Player 2
  - Keyboard left (WASD) → Player 3
  - Keyboard right (IJKL) → Player 4
- Device discovery and assignment UI
- Hot-plug support for gamepads

*Player ID System Changes*:
- Separate peer_id from player_id (currently 1:1)
- Format: "peer_id:local_index" or similar
- One peer connection can own multiple players
- Server (embedded) assigns player IDs for all local players

*Embedded Local Server*:
- Run server logic in-process (same Godot instance)
- Client connects to localhost (or skip network entirely)
- Reuse all existing networking code, frame driver, rollback
- No internet required

*Camera System*:
- Follow all active players (zoom out as they spread)
- Or: follow the "most active" player
- No split screen (too complex, defer)

*UI Changes*:
- Player join screen (press button on device to join)
- Device-to-player assignment display
- Per-player HUD elements
- Main menu: "Local Play" option alongside "Online Play"

**Key files to modify** (from DELETE_ME doc analysis):
- `src/core/game_session_manager.gd` — Local session mode
- `src/player/player_action_source.gd` — Multi-device input
- `addons/rollback_netcode/core/network_connector.gd` — Multi-
  player per peer support
- `src/level/level.gd` — Multiple local players
- `src/core/match_state.gd` — Multi-player per client state
- Camera system — Follow multiple players

**Testing**:
- Connect 2 gamepads, verify 2 characters spawn
- Keyboard + gamepad, verify both work simultaneously
- Verify all match mechanics work identically to online
- Verify no network calls made in offline mode

---

### M12: Mobile Builds

**Goal**: iOS and Android builds with touch controls, connected
via WebSocket.

**What's included**:
- iOS export (requires Mac with Xcode)
- Android export (requires Android SDK)
- Touch control overlay (virtual joystick + buttons)
- WebSocket transport (same as web, already built in M10)
- App store listings and metadata
- Platform-specific considerations (screen sizes, safe areas,
  background/foreground handling)
- No local multiplayer on mobile (decided)

**Manual steps**:
1. Apple Developer account setup ($99/year)
2. Create App ID, provisioning profiles, certificates
3. Google Play Console setup ($25 one-time)
4. Create app listing, upload signing key
5. Privacy Nutrition Labels (Apple) and Data Safety (Google)
6. TestFlight (iOS) and Internal Testing (Android) for beta

**Key files to create**:
- `src/ui/controls/touch_controls.gd` (new)
- `src/ui/controls/virtual_joystick.gd` (new)
- Export presets for iOS and Android
- App store assets (icons, screenshots, descriptions)

**Testing**:
- Build and run on physical iOS device
- Build and run on physical Android device
- Verify touch controls responsive and accurate
- Cross-play test: mobile + desktop in same match
- Verify 60 FPS network tick sustainable on mobile

---

### M13: CI/CD & Deployment Automation

**Goal**: PR merge to `release` branch triggers automated builds
and deployments to all platforms.

**What's included**:

*GitHub Actions Workflows*:
```
.github/workflows/
  deploy-server.yml    → Build Docker → Push ECR → Update fleet
  deploy-itch.yml      → Build Win/Mac/Linux/Web → Upload itch.io
  deploy-backend.yml   → SAM build → SAM deploy
  deploy-web.yml       → Build web → Upload S3 → Invalidate CDN
  test.yml             → (existing) Run GUT tests
  build-gamelift.yml   → (existing) Build GDExtension
```

*Release Flow*:
1. Develop on feature branches, merge to main
2. When ready to release: merge main → release branch
3. GitHub Actions detects merge to release
4. Parallel jobs: server build, client builds, backend deploy
5. Each job uploads artifacts and deploys to respective platform
6. Notification on success/failure

*itch.io Deployment*:
- Use butler CLI (itch.io's upload tool)
- Push channels: windows, mac, linux, web
- Automatic version tagging from git

*Future Platform Deployments*:
- Steam: steamcmd upload (needs Steamworks account first)
- Epic: Epic Games Store CLI
- iOS: Xcode Cloud or fastlane
- Android: fastlane + Google Play API

**Estimated CI time per release**: ~40-60 minutes total across
all parallel jobs. Well within GitHub Actions free tier
(2000 min/month).

**Key files to create**:
- `.github/workflows/deploy-server.yml`
- `.github/workflows/deploy-itch.yml`
- `.github/workflows/deploy-backend.yml`
- `.github/workflows/deploy-web.yml`
- `scripts/build-server-container.ps1`
- `scripts/upload-itch.ps1`

**Manual steps**:
1. Create itch.io API key, add as GitHub secret
2. Install butler locally for testing
3. Create `release` branch
4. Configure branch protection rules

---

### M14: Website (hopnbop.net)

**Goal**: Static website with web build, leaderboards, blog,
and game info.

**What's included**:

*Hosting Stack*:
- S3 bucket for static files
- CloudFront CDN for global delivery + HTTPS
- Route 53 for DNS (hopnbop.net)
- ACM for SSL/TLS certificate (free)

*Website Pages*:
- Home: Game description, trailer/screenshots, download links
- Play: Embedded web build (iframe or direct)
- Leaderboards: Global + weekly, fetched from API
- Blog/Patch Notes: Static markdown → HTML (use a simple SSG
  like Hugo, Eleventy, or just hand-written HTML)
- Privacy Policy, Terms of Service, Data Deletion
- Discord invite link
- Links to itch.io, Steam, app stores

*Web Build Hosting*:
- Web export files served from S3 via CloudFront
- Separate S3 path: hopnbop.net/play/
- CORS headers for API calls from web build

**Cost**: ~$1-5/month (S3 storage + CloudFront transfer +
Route 53 hosting zone at $0.50/month).

**Manual steps**:
1. Register hopnbop.net in Route 53 (or transfer DNS from current
   registrar to Route 53)
2. Request ACM certificate for hopnbop.net + *.hopnbop.net
3. Create S3 bucket with static website hosting
4. Create CloudFront distribution pointing to S3
5. Configure Route 53 A/AAAA records → CloudFront
6. Deploy website files

**Key files to create**:
- `website/` directory with static site source
- `scripts/deploy-website.ps1`
- `.github/workflows/deploy-web.yml` — Include website deploy

---

### M15: Client Polish & Remaining Items

**Goal**: Final integration items that span multiple milestones.

**What's included**:
- Loading screen: all status messages integrated
  (Authenticating... → Finding players... → Connecting... →
  Waiting for players...)
- Version check: force update dialog with link to download
- Settings book: hide in lobby until 3 rounds played
- Client crash reporter autoload
- Anti-cheat: server-side input validation (rate limiting,
  physics bounds checking)
- Connection resilience: reconnect logic on temporary disconnect
- DDoS: verify AWS Shield Standard active, API Gateway throttling
  configured, GameLift protections enabled
- Remote server testing from editor: integrate
  `preview_connect_to_remote_server` setting with auth token
  caching so `start_in_game` works with remote servers
- Game analytics: DAU, session length, retention (D1/D7/D30),
  match completion rate via CloudWatch custom metrics

---

## Manual Setup Checklist (One-Time)

### Platform Accounts
- [ ] AWS account (Snoring Cat LLC billing)
- [ ] Steam developer account (Steamworks, $100 app fee)
- [ ] Apple Developer account ($99/year)
- [ ] Google Play Console ($25 one-time)
- [ ] Epic Games Store developer account (free)
- [ ] Google Cloud Console project (for OAuth, free tier)
- [ ] Discord developer application (free)
- [ ] Twitch developer application (free)
- [ ] itch.io project for Hop 'n Bop (already have account)

### AWS Infrastructure
- [ ] IAM admin user with MFA
- [ ] AWS CLI configured locally
- [ ] SAM CLI installed
- [ ] Secrets Manager: JWT signing key
- [ ] Secrets Manager: OAuth client secrets (6 providers)
- [ ] SNS topic for alarms, email subscription confirmed
- [ ] S3 bucket for hopnbop.net
- [ ] CloudFront distribution
- [ ] Route 53 hosted zone
- [ ] ACM SSL certificate
- [ ] ECR repository for server containers
- [ ] GameLift container fleet
- [ ] GameLift Anywhere fleet (for local dev)
- [ ] DynamoDB PITR enabled on all tables
- [ ] AWS Budgets alerts ($25, $50, $100)
- [ ] CloudWatch dashboard

### Local Development
- [ ] Docker installed (for container builds)
- [ ] butler CLI installed (for itch.io uploads)
- [ ] Xcode installed on Mac (for iOS builds)
- [ ] Android SDK installed (for Android builds)

### Legal
- [ ] Privacy policy drafted and hosted
- [ ] Terms of service drafted and hosted
- [ ] Data deletion policy drafted and hosted
- [ ] Age gate (13+) implemented in client

### CI/CD
- [ ] GitHub secrets configured (AWS keys, itch.io key, etc.)
- [ ] `release` branch created with protection rules
- [ ] All deployment workflows tested with manual dispatch first

---

## Ongoing Maintenance

### Weekly
- Check CloudWatch dashboard for anomalies
- Review error logs in CloudWatch Logs
- Check AWS cost in Cost Explorer
- Process any GDPR deletion/export requests

### Monthly
- Review auto-scaling behavior, adjust if needed
- Check DynamoDB capacity utilization
- Review crash reports, prioritize fixes
- Update game analytics review

### Quarterly
- Rotate JWT signing key
- Update OAuth provider SDK/API versions if changed
- Review and update privacy policy if data practices changed
- Security audit: check IAM permissions, secret access logs
- Update Godot engine if new stable release
- Update GameLift SDK if new version

### Annually
- Renew Apple Developer account ($99)
- Review legal documents with evolving regulations
- Review GDPR/CCPA compliance
- Platform policy review (Steam, Apple, Google, Epic)

### As Needed
- Add AWS regions as player base grows geographically
- Scale up DynamoDB capacity as player count grows
- Add OAuth providers if demand warrants
- Update FlexMatch rules based on matchmaking analytics
- Respond to platform policy changes
- Handle app store review feedback
- Address security vulnerabilities in dependencies

---

## Cost Estimates (Monthly, at 10 Concurrent)

| Service | Estimated Cost |
|---------|---------------|
| GameLift (1 c5.large Spot) | $8-15 |
| Lambda (low traffic) | $0-1 (free tier) |
| API Gateway | $0-1 (free tier) |
| DynamoDB (on-demand, low traffic) | $1-3 |
| CloudFront + S3 | $1-2 |
| Route 53 | $0.50 |
| Secrets Manager (~8 secrets) | $3.20 |
| CloudWatch (dashboards, alarms) | $3-5 |
| SNS (email notifications) | $0 (free tier) |
| ECR (container storage) | $0-1 |
| **Total** | **~$17-29/month** |

Costs scale roughly linearly with player count up to ~100
concurrent, then benefit from bulk pricing and Spot savings.

---

## Publishing Concerns for a Free Game

1. **App store fees**: Apple charges $99/year regardless. Google
   charges $25 one-time. Steam charges $100 per app. Epic is free.
2. **Ratings**: ESRB rating not legally required but recommended
   for store listings. IARC rating (free, online) accepted by
   most stores.
3. **Accessibility**: Consider colorblind modes, control
   remapping, text scaling. Not legally required but good practice
   and some platforms reward it.
4. **Open source considerations**: If using open source libraries,
   ensure license compliance. Godot is MIT. GUT is MIT.
   GameLift SDK is Apache 2.0. All are compatible.
5. **Content moderation**: No chat = no moderation needed. Player
   names come from OAuth providers (already moderated by those
   platforms). Friend codes are random (no offensive content risk).
6. **Platform-specific requirements**:
   - Steam: Need store page, trading cards (optional), community
     hub setup
   - Apple: App review can take 1-7 days. May reject for various
     reasons. Plan buffer time.
   - Google: Review typically 1-3 days.
   - Epic: Developer portal submission, review process.
7. **Analytics for growth**: Track DAU, session length, retention
   (D1/D7/D30), match completion rate. Use CloudWatch custom
   metrics or a lightweight analytics service.
8. **Marketing**: itch.io visibility requires tagging and
   community engagement. Steam discovery relies on wishlists and
   reviews. Consider a press kit page on hopnbop.net.
9. **Localization**: Not required for launch but helps reach
   international audiences. Start with English, add languages
   based on player demographics.
10. **Backup and source control**: Your git repo IS your backup.
    Consider enabling GitHub's branch protection and requiring
    PR reviews even for solo dev (creates audit trail).
