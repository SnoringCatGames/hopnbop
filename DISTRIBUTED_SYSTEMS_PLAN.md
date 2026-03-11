# Hop 'n Bop: Backend & Distributed Systems Master Plan

## Context

Hop 'n Bop has a robust client with rollback netcode and an untested
but well-structured backend (AWS SAM, Lambda, DynamoDB, GameLift
FlexMatch). This plan covers everything needed to go from local
multiplayer testing to a fully deployed, monitored, multi-platform
game with auth, persistence, social features, and legal compliance.

Publisher: Snoring Cat LLC. No monetization. 13+ age rating. Domain:
hopnbop.net (purchased).

---

## Architecture Overview

```
┌────────────────────────────────────────────────────────────┐
│                        CLIENTS                             │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌────────────┐  │
│  │ Windows  │  │   Web    │  │   iOS    │  │  Android   │  │
│  │  (ENet)  │  │(WebSocket│  │(WebSocket│  │ (WebSocket │  │
│  │          │  │  or WRT) │  │  or WRT) │  │   or WRT)  │  │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └─────┬──────┘  │
└───────┼─────────────┼─────────────┼──────────────┼─────────┘
        │             │             │              │
        ▼             ▼             ▼              ▼
┌───────────────────────────────────────────────────────────┐
│                    AWS INFRASTRUCTURE                     │
│                                                           │
│  ┌─────────────────────────────────────────────────────┐  │
│  │              API Gateway (HTTPS)                    │  │
│  │  POST /auth/login     POST /matchmaking/start       │  │
│  │  POST /auth/anon      GET  /matchmaking/status/:id  │  │
│  │  POST /auth/refresh   GET  /player/profile          │  │
│  │  POST /auth/link      PUT  /player/settings         │  │
│  │  POST /auth/unlink    GET  /leaderboard             │  │
│  │  GET  /player/export  POST /friends/add             │  │
│  │  DELETE /player       POST /friends/remove          │  │
│  └──────────────┬──────────────────────────────────────┘  │
│                 ▼                                         │
│  ┌─────────────────────────────────────────────────────┐  │
│  │              Lambda Functions (Python 3.12)         │  │
│  │  auth_handler  matchmaking_handler  player_handler  │  │
│  │  leaderboard_handler  friends_handler               │  │
│  └───────┬────────────┬──────────────┬─────────────────┘  │
│          │            │              │                    │
│          ▼            ▼              ▼                    │
│  ┌────────────┐ ┌──────────┐ ┌──────────────────────┐     │
│  │  DynamoDB  │ │ GameLift │ │  Secrets Manager     │     │
│  │  Players   │ │ FlexMatch│ │  JWT key, OAuth      │     │
│  │  Matches   │ │          │ │  client secrets      │     │
│  │  Friends   │ │          │ └──────────────────────┘     │
│  │  Leaderbd  │ │          │                              │
│  │  Settings  │ │          │                              │
│  └────────────┘ └────┬─────┘                              │
│                      ▼                                    │
│  ┌─────────────────────────────────────────────────────┐  │
│  │        GameLift Container Fleet (us-west-2)         │  │
│  │   ┌──────────────────────────────────────────────┐  │  │
│  │   │  Godot Dedicated Server (Linux, headless)    │  │  │
│  │   │  ENet listener (port 4433)                   │  │  │
│  │   │  WebSocket listener (port 4434)              │  │  │
│  │   │  Crash reporter → CloudWatch                 │  │  │
│  │   └──────────────────────────────────────────────┘  │  │
│  │   Spot instances (primary) + On-Demand (fallback)   │  │
│  │   Target-based auto-scaling                         │  │
│  └─────────────────────────────────────────────────────┘  │
│                                                           │
│  ┌─────────────────────────────────────────────────────┐  │
│  │  CloudWatch: Dashboards, Alarms → SNS → Email       │  │
│  │  S3 + CloudFront: hopnbop.net (website + web build) │  │
│  │  Route 53: DNS for hopnbop.net                      │  │
│  │  ACM: SSL/TLS certificates                          │  │
│  └─────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────┘
```

---

## All Decisions

| # | Decision | Choice |
|---|----------|--------|
| 1 | Identity backbone | Direct provider mapping in DynamoDB, custom JWT |
| 2 | Anonymous players | Persistent device-based ID, can upgrade |
| 3 | Network tick rate | 60 FPS uniform, all platforms |
| 4 | Web transport | WebSocket first, architect for swappability |
| 5 | AWS region | us-west-2 (Oregon), single region to start |
| 6 | Scale | 10-50 concurrent at launch |
| 7 | OAuth providers | Web: Google + Facebook. Platform: Steam, Epic, Apple, Android |
| 8 | Token refresh | Yes, refresh tokens for better UX |
| 9 | Age rating | 13+ only |
| 10 | Offline mode | Local multiplayer (couch co-op), not solo |
| 11 | Offline sync | No. Server authority preserved |
| 12 | Dev accounts | None yet |
| 13 | Deploy trigger | PR merge to release branch |
| 14 | Monetization | None. Completely free |
| 15 | Publisher | Snoring Cat LLC |
| 16 | Matchmaking | Soft preferences, progressive relaxation |
| 17 | Min match size | 2 (never solo matchmake) |
| 18 | Typical match size | 4 (max 8) |
| 19 | Party queue | Yes |
| 20 | Play again flow | Yes |
| 21 | Recent match friending | Yes |
| 22 | Leaderboard periods | All-time + weekly |
| 23 | Friends leaderboard | Yes, friend-filtered view |
| 24 | Settings sync | All settings, local + cloud, prefer cloud |
| 25 | Match history | Last 5 matches viewable |
| 26 | Stats to track | All fields from PlayerMatchStats |
| 27 | Alerting | Email via SNS |
| 28 | Friend discovery | Auth provider info + unique friend codes |
| 29 | In-game chat | No |
| 30 | Spectating | No |
| 31 | Web features | Full parity with desktop |
| 32 | Mobile local multiplayer | No |
| 33 | Version mismatch | Force update |
| 34 | Player migration | Not worth it for 45-sec matches |
| 35 | Database backups | DynamoDB PITR (AWS-managed) |
| 36 | Website features | Leaderboards, blog, patch notes, Discord link |
| 37 | Account management | In-game only, not on website |
| 38 | GDPR data export | Yes |
| 39 | Email service | Not needed (OAuth handles verification) |
| 40 | GameLift fleet type | Container fleets (faster iteration) |

---

## Milestones

### M1: AWS Account & Infrastructure Foundation ✅

**Goal**: Set up AWS account and base infrastructure so all
subsequent milestones can build on it.

**What's included**:
- Create AWS account, configure IAM admin user
- Set up billing alerts ($25, $50, $100 thresholds)
- Configure AWS CLI locally
- Install and configure AWS SAM CLI
- Create Secrets Manager secrets (JWT signing key, placeholder
  OAuth secrets)
- Deploy initial SAM stack to us-west-2
- Verify existing Lambda functions deploy and respond

**Manual steps**:
1. Go to aws.amazon.com, create account with Snoring Cat LLC info
2. Enable MFA on root account
3. Create IAM admin user with programmatic access
4. Run `aws configure sso` and set region to us-west-2
5. Install AWS SAM CLI (`winget install Amazon.SAM-CLI`)
6. Generate a JWT signing key
   (`python -c "import secrets; print(secrets.token_hex(32))"`)
7. Create secrets in Secrets Manager via AWS Console
8. Run `sam build` then `sam deploy --guided` from backend/
9. Test endpoints with `Invoke-RestMethod`

**Testing**: `Invoke-RestMethod -Method Post -Uri https://<api-id>.execute-api.us-west-2.amazonaws.com/Prod/auth/login`
returns a structured error (no valid credentials, but proves the
endpoint is live).

**Key files**: `backend/template.yaml`, `backend/samconfig.toml`

---

### M2: Complete Auth Flow ✅

**Goal**: End-to-end authentication from client through backend,
OAuth providers + anonymous + refresh tokens + account
linking/unlinking.

**Status**: Complete. 67 backend tests passing.

**What was built**:

*Backend (auth_handler.py, auth_service.py)*:
- POST /auth/login. OAuth login (Steam, Epic, Google, Facebook,
  Apple). Issues JWT + refresh token.
- POST /auth/anon. Anonymous login via device ID. Issues JWT
  with is_anonymous flag.
- POST /auth/refresh. Token rotation (old refresh token
  invalidated).
- POST /auth/link. Link additional OAuth provider to existing
  account. Detects conflicts (provider already linked to
  different player).
- POST /auth/unlink. Unlink provider with last-provider safety
  guard (blocks if only auth method and no device_id fallback).
- All responses include linked_providers list.

*Client (auth_client.gd)*:
- Three OAuth flows:
  - Desktop loopback: local TCP server on port 9876 captures
    browser redirect.
  - Web popup: Opens popup window, static oauth-callback.html
    sends code via postMessage. No backend polling needed.
  - Platform: Steam/Epic provide tokens via their SDK.
- Auth screen: auto-login on implied-auth platforms (Steam,
  Epic). Shows Google + Facebook + Anonymous on web/desktop.
- Token storage: encrypted local config with linked_providers.
- Auto-refresh: background refresh before token expiry.
- Version mismatch detection from login response.
- Account linking/unlinking from settings panel
  (LinkAccountRow).

*OAuth provider decisions*:
- Web/desktop explicit auth: Google + Facebook (best audience
  coverage).
- Platform implied auth: Steam, Epic, Apple, Android (SDK
  provides token, no browser flow needed).
- Account linking: any platform player can link Google/Facebook
  as a cross-platform identity bridge.

*Key files*:
- `backend/src/handlers/auth_handler.py`. All auth endpoints.
- `backend/src/services/auth_service.py`. Provider-specific
  token exchange.
- `backend/src/services/player_service.py`. Player profiles,
  refresh tokens.
- `backend/src/services/provider_mapping_service.py`. Provider
  ID to player ID mapping.
- `src/core/auth_client.gd`. All client OAuth flows.
- `src/core/auth_token_store.gd`. Encrypted token persistence.
- `src/ui/screens/auth_screen.gd`. Auth UI.
- `src/ui/settings_panel/link_account_row.gd`. Link/unlink UI.
- `web/oauth/callback/index.html`. Static callback for popup
  OAuth (deployed to `hopnbop.net/oauth/callback/`).

**Remaining manual steps**:
- Configure Google OAuth (see setup guide below)
- Configure Facebook OAuth (see setup guide below)
- Store client secrets in Secrets Manager
- Set client IDs in `settings.tres`
- Test real end-to-end OAuth flows

---

#### Google OAuth Setup (Manual Steps)

1. Go to Google Cloud Console (console.cloud.google.com)
2. Create a new project (or select existing):
   - Project name: "Hop n Bop"
3. Enable the Google Identity API:
   - APIs & Services > Library
   - Search "Google Identity" or navigate to "Google Identity
     Toolkit API"
   - Click Enable
4. Configure the OAuth consent screen:
   - APIs & Services > OAuth consent screen
   - User type: External
   - App name: "Hop 'n Bop"
   - User support email: your email
   - Developer contact: your email
   - Scopes: add `openid`, `profile`, `email`
   - Test users: add your own Google account for testing
   - Save
5. Create OAuth 2.0 credentials:
   - APIs & Services > Credentials > Create Credentials >
     OAuth client ID
   - Application type: **Web application**
   - Name: "Hop n Bop Web Client"
   - Authorized redirect URIs. Add all of these:
     - `https://hopnbop.net/oauth/callback/` (web popup)
     - `http://127.0.0.1:9876` (desktop loopback)
   - Click Create
   - Note the **Client ID** and **Client Secret**
6. Store in AWS Secrets Manager:
   ```powershell
   aws secretsmanager create-secret `
     --name hopnbop/oauth/google `
     --secret-string '{"client_id":"YOUR_ID.apps.googleusercontent.com","client_secret":"YOUR_SECRET"}' `
     --region us-west-2 --profile hopnbop
   ```
7. Set client ID in Godot:
   - Open `settings.tres` in the Godot inspector
   - Set `google_oauth_client_id` to the Client ID from step 5
8. Publish the OAuth consent screen:
   - Go back to OAuth consent screen
   - Click "Publish App" to move from Testing to Production
   - Google may require verification if you request sensitive
     scopes (openid/profile/email are not sensitive, so this
     should be immediate)

**Testing**: Click the Google button in the auth screen. A
browser window (desktop) or popup (web) should open to
accounts.google.com. After signing in, the redirect should
return a code that the client sends to /auth/login. Verify
the response includes a valid JWT and the player's Google
display name.

---

#### Facebook OAuth Setup (Manual Steps)

1. Go to Facebook for Developers
   (developers.facebook.com)
2. Create a new app:
   - Click "Create App"
   - Use case: "Authenticate and request data from users
     with Facebook Login"
   - App type: Consumer
   - App name: "Hop n Bop"
   - Create
3. Set up Facebook Login:
   - In the app dashboard, find "Facebook Login" product
   - Click "Set Up"
   - Choose "Web"
   - Site URL: `https://hopnbop.net`
   - Save
4. Configure OAuth settings:
   - Facebook Login > Settings
   - Valid OAuth Redirect URIs:
     - `https://hopnbop.net/oauth/callback/`
   - Client OAuth login: Yes
   - Web OAuth login: Yes
   - Save Changes
   - Note: Facebook requires HTTPS redirect URIs, so the
     desktop loopback (`http://127.0.0.1:9876`) cannot be
     used directly. Desktop auth uses a two-hop pattern:
     Facebook redirects to the hosted callback page, which
     then forwards the code to the loopback server via a
     client-side redirect.
5. Note your credentials:
   - App Dashboard > Settings > Basic
   - Note the **App ID** (this is the client ID) and
     **App Secret** (this is the client secret)
6. Store in AWS Secrets Manager:
   ```powershell
   aws secretsmanager create-secret `
     --name hopnbop/oauth/facebook `
     --secret-string '{"client_id":"YOUR_APP_ID","client_secret":"YOUR_APP_SECRET"}' `
     --region us-west-2 --profile hopnbop
   ```
7. Set client ID in Godot:
   - Open `settings.tres` in the Godot inspector
   - Set `facebook_oauth_client_id` to the App ID from step 5
8. Switch app to Live mode:
   - App Dashboard > top toggle: switch from "Development" to
     "Live"
   - Facebook may require you to complete a Data Use Checkup
     and provide a Privacy Policy URL
     (`https://hopnbop.net/privacy`) before going live
   - Only `public_profile` permission is needed (no app
     review required for this default permission)

**Testing**: Click the Facebook button in the auth screen. A
browser window (desktop) or popup (web) should open to
facebook.com. After signing in, Facebook redirects to the
hosted callback page. On web, the popup sends the code via
postMessage. On desktop, the callback page redirects to the
loopback server (`http://127.0.0.1:9876`), which captures
the code and sends it to /auth/login. The backend exchanges
this via the Graph API v19.0 for an access token, fetches
/me for the user's name and ID, and returns a JWT.

---

#### hopnbop.net Web Hosting Setup (Manual Steps)

The site needs to be live before OAuth works (redirect URIs
point to `hopnbop.net/oauth/callback/`). This is also where
the web build, legal pages, and press kit will live.

**Part A: Domain & Certificate**

1. Register or transfer `hopnbop.net` to Route 53:
   - If purchased elsewhere (e.g., Namecheap, Google Domains):
     Route 53 > Hosted Zones > Create hosted zone for
     `hopnbop.net`. Copy the 4 NS records. Update your
     registrar's nameservers to these Route 53 NS records.
     Allow 24-48 hours for DNS propagation.
   - If purchasing new: Route 53 > Registered Domains >
     Register. Route 53 auto-creates the hosted zone.
2. Request an ACM SSL certificate:
   - **Important**: Switch to `us-east-1` region in the AWS
     Console. CloudFront requires certificates in us-east-1.
   - ACM > Request a public certificate
   - Domain names: `hopnbop.net` and `*.hopnbop.net`
   - Validation method: DNS
   - Click "Create records in Route 53" to auto-add the
     CNAME validation records
   - Wait for status to change to "Issued" (usually 5-30
     minutes)

**Part B: S3 Bucket**

3. Create the S3 bucket:
   ```powershell
   aws s3 mb s3://hopnbop-website --region us-west-2 `
     --profile hopnbop
   ```
   - Do NOT enable "Static website hosting" on the bucket
     (CloudFront will use OAC instead, which is more secure)
   - Block all public access (default). CloudFront will be
     the only way to reach the content.

**Part C: CloudFront Distribution**

4. Create a CloudFront distribution:
   - CloudFront > Create distribution
   - Origin domain: select the S3 bucket
     (`hopnbop-website.s3.us-west-2.amazonaws.com`)
   - Origin access: Origin Access Control (OAC). Create a
     new OAC with S3 origin type.
   - Viewer protocol policy: Redirect HTTP to HTTPS
   - Allowed HTTP methods: GET, HEAD
   - Cache policy: CachingOptimized (recommended)
   - Alternate domain names (CNAMEs): `hopnbop.net` and
     `www.hopnbop.net`
   - Custom SSL certificate: select the ACM certificate
     from step 2
   - Default root object: `index.html`
   - Error pages: Create custom error response for 403 →
     `/index.html` with 200 status (for SPA routing, if
     needed)
   - Create distribution. Note the distribution domain
     (e.g., `d1234abcdef.cloudfront.net`)
5. Update S3 bucket policy to allow CloudFront OAC:
   - After creating the distribution, CloudFront shows a
     banner: "Copy policy". Copy the JSON and apply it:
   ```powershell
   aws s3api put-bucket-policy `
     --bucket hopnbop-website `
     --policy file://cloudfront-bucket-policy.json `
     --profile hopnbop
   ```
   Or paste it in the S3 Console under Permissions > Bucket
   policy.

**Part D: DNS Records**

6. Create Route 53 DNS records:
   - Route 53 > Hosted Zones > hopnbop.net
   - Create record: Name = (blank for apex), Type = A,
     Alias = Yes, Route traffic to CloudFront distribution
   - Create record: Name = `www`, Type = A, Alias = Yes,
     Route traffic to same CloudFront distribution
   - Optionally create AAAA records (same config) for IPv6

**Part E: Deploy Initial Content**

7. Upload the OAuth callback page:
   ```powershell
   aws s3 cp web/oauth/callback/index.html `
     s3://hopnbop-website/oauth/callback/index.html `
     --content-type "text/html" `
     --profile hopnbop
   ```
8. Create a placeholder index.html:
   ```powershell
   aws s3 cp web/index.html `
     s3://hopnbop-website/index.html `
     --content-type "text/html" `
     --profile hopnbop
   ```
   (Create a simple landing page or "Coming Soon" page in
   `web/index.html` first.)
9. Invalidate CloudFront cache (do this after every deploy):
   ```powershell
   aws cloudfront create-invalidation `
     --distribution-id YOUR_DIST_ID `
     --paths "/*" `
     --profile hopnbop
   ```

**Part F: Verify**

10. Browse to `https://hopnbop.net`. Verify HTTPS works and
    the page loads.
11. Browse to `https://hopnbop.net/oauth/callback/?code=test`.
    Verify the callback page loads and shows the hourglass
    then "No authorization code received" (since `code=test`
    is not empty, it should show the success message with no
    opener).
12. Set up Google and Facebook OAuth redirect URIs pointing
    to `https://hopnbop.net/oauth/callback/` (see setup
    guides above).

**Ongoing deployment**: Upload files with `aws s3 sync`,
then invalidate CloudFront. This will be automated in
M13 (CI/CD).

**Files in the `web/` directory**:
- `web/oauth/callback/index.html`. OAuth redirect page
  (already created).
- `web/index.html`. Landing page (to be created).
- Future: `web/play/`. Godot web export files.
- Future: `web/privacy/index.html`. Privacy policy.
- Future: `web/terms/index.html`. Terms of service.
- Future: `web/data-deletion/index.html`. Data deletion
  policy.

---

#### Steam Integration & Deployment (Manual Steps)

**Part A: Steamworks Setup**

1. Create a Steamworks developer account:
   - Go to partner.steamgames.com
   - Sign up with your Steam account
   - Pay the $100 app credit fee (refunded after $1000 revenue,
     but this is a free game so it won't be refunded)
   - Complete tax and banking information for Snoring Cat LLC
2. Create a new app:
   - Steamworks > Create New App
   - App name: "Hop 'n Bop"
   - Note the **App ID** (e.g. 1234560)
3. Get your Steam Web API Key:
   - steamcommunity.com/dev/apikey
   - Domain: hopnbop.net
   - Note the **Web API Key**
4. Store credentials:
   ```powershell
   aws secretsmanager create-secret `
     --name hopnbop/oauth/steam `
     --secret-string '{"api_key":"YOUR_WEB_API_KEY"}' `
     --region us-west-2 --profile hopnbop
   ```
   Also set the `STEAM_APP_ID` parameter when deploying:
   ```powershell
   sam deploy --parameter-overrides SteamAppID=1234560
   ```

**Part B: Auth Integration (Client)**

5. Install the GodotSteam GDExtension:
   - Download from godotsteam.com (match your Godot version)
   - Place the addon in `addons/godotsteam/`
   - Enable in Project Settings > Plugins
6. Initialize Steam SDK on startup:
   ```gdscript
   # In an autoload or _ready of a boot scene.
   var is_init := Steam.steamInitEx(false, YOUR_APP_ID)
   if is_init.status != Steam.STEAM_API_INIT_STATUS_OK:
       push_error("Steam init failed: %s" % is_init.verbal)
   ```
7. Auth flow. When the auth screen detects the Steam
   platform (via `OS.has_feature("steam")`), it calls
   `AuthClient.login_with_provider(Provider.STEAM)` which
   triggers `submit_platform_token`. The client gets a
   session ticket:
   ```gdscript
   var auth_ticket: Dictionary = (
       Steam.getAuthSessionTicket(Steam.networking_identities)
   )
   var ticket_hex: String = (
       auth_ticket.buffer.hex_encode()
   )
   G.auth_client.submit_platform_token(
       AuthClient.Provider.STEAM, ticket_hex
   )
   ```
8. Backend validation. The `_auth_steam()` method in
   `auth_service.py` calls the Steam Web API
   `ISteamUserAuth/AuthenticateUserTicket` to validate
   the ticket and get the player's Steam ID. Then it
   fetches `ISteamUser/GetPlayerSummaries` for the
   display name.

**Part C: Store Deployment**

9. Configure store page:
   - Steamworks > App Admin > Store Page
   - Upload capsule images (header: 460x215, hero: 3840x1240,
     capsule: 231x87, library: 600x900)
   - Upload screenshots (minimum 5, 1920x1080 recommended)
   - Write short description (< 300 chars) and full description
   - Set genres: Action, Indie, Multiplayer
   - Set tags: Platformer, Local Multiplayer, Online Multiplayer
   - Set supported languages
   - Age rating: select "13+" or get IARC rating
10. Configure build depots:
    - Steamworks > App Admin > SteamPipe > Depots
    - Create depot for Windows (default)
    - Optionally create depots for Linux and macOS
11. Upload builds using steamcmd:
    ```powershell
    steamcmd +login YOUR_USERNAME `
      +run_app_build app_build_1234560.vdf +quit
    ```
    Or use the Steamworks Upload tool (GUI).
    The `app_build_*.vdf` file defines which local folder
    maps to which depot.
12. Set the build live:
    - Steamworks > App Admin > SteamPipe > Builds
    - Set the uploaded build as the default branch
13. Submit for review:
    - Steamworks > App Admin > Release > Request Review
    - Steam review typically takes 2-5 business days
    - Common rejection reasons: missing screenshots, broken
      links, incomplete store page

**Testing**: Launch the game through Steam. Verify GodotSteam
initializes, the auth screen auto-logs in with Steam, and the
backend validates the session ticket. Verify the Steam overlay
works (Shift+Tab).

---

#### Epic Games Integration & Deployment (Manual Steps)

**Part A: Epic Developer Portal Setup**

1. Create an Epic Games developer account:
   - Go to dev.epicgames.com
   - Sign up (free)
   - Create an organization for Snoring Cat LLC
2. Create a new product:
   - Developer Portal > Products > Create Product
   - Product name: "Hop 'n Bop"
3. Create an application (client):
   - Product Settings > Clients > Add New Client
   - Client policy: GameClient
   - Note the **Client ID**, **Client Secret**, and
     **Deployment ID**
4. Configure Epic Account Services:
   - Product Settings > Epic Account Services
   - Create a new application
   - Permissions: Basic Profile (no email needed)
   - Linked clients: link the client from step 3
   - Brand settings: app name, icon
5. Store credentials:
   ```powershell
   aws secretsmanager create-secret `
     --name hopnbop/oauth/epic `
     --secret-string '{"client_id":"YOUR_CLIENT_ID","client_secret":"YOUR_SECRET","deployment_id":"YOUR_DEPLOY_ID"}' `
     --region us-west-2 --profile hopnbop
   ```

**Part B: Auth Integration (Client)**

6. Install the Epic Online Services (EOS) GDExtension:
   - Use the community EOS plugin for Godot (e.g.,
     3ddelano/epic-online-services-godot) or build a
     minimal GDExtension wrapping the EOS SDK
   - Place in `addons/eos/`
7. Initialize EOS on startup:
   ```gdscript
   EOS.Platform.create({
       "client_id": "YOUR_CLIENT_ID",
       "client_secret": "YOUR_SECRET",
       "product_id": "YOUR_PRODUCT_ID",
       "sandbox_id": "YOUR_SANDBOX_ID",
       "deployment_id": "YOUR_DEPLOYMENT_ID",
   })
   ```
8. Auth flow. When Epic is detected, the client uses
   the EOS Auth Interface to get an access token:
   ```gdscript
   # Login with Epic Account Portal.
   EOS.Auth.login({
       "type": EOS.Auth.LOGIN_EPIC_ACCOUNT_PORTAL,
   })
   # On success callback:
   var token: String = EOS.Auth.copy_user_auth_token()
   G.auth_client.submit_platform_token(
       AuthClient.Provider.EPIC, token
   )
   ```
9. Backend validation. The `_auth_epic()` method in
   `auth_service.py` validates the token by calling the
   Epic account API
   (`api.epicgames.dev/epic/oauth/v2/tokenInfo`)
   and fetches the user's display name.

**Part C: Store Deployment**

10. Submit to Epic Games Store:
    - Developer Portal > Your Product > Store Settings
    - Upload store assets (key art: 2560x1440, offer images,
      screenshots)
    - Write description, set genres, age rating
    - Upload builds via BuildPatchTool:
      ```powershell
      BuildPatchTool.exe -mode=UploadBinary `
        -OrganizationId=YOUR_ORG `
        -ProductId=YOUR_PRODUCT `
        -ArtifactId=YOUR_ARTIFACT `
        -BuildRoot="path/to/build" `
        -CloudDir="path/to/cloud/cache" `
        -BuildVersion="0.1.0" `
        -AppLaunch="HopnBop.exe" `
        -AppArgs=""
      ```
11. Submit for review:
    - Epic review can take 1-2 weeks
    - Free games are accepted (Epic takes 0% revenue for
      games using Unreal, 12% for others. Since Godot is not
      Unreal, standard 12% of $0 = $0)

**Testing**: Launch the game via the Epic Games Launcher
or directly with EOS initialized. Verify the EOS login
portal appears, the auth screen auto-logs in with Epic,
and the backend validates the token.

---

#### Android Integration & Deployment (Manual Steps)

**Part A: Google Play Console Setup**

1. Create a Google Play Developer account:
   - Go to play.google.com/console
   - Pay the $25 one-time registration fee
   - Complete identity verification for Snoring Cat LLC
2. Create a new app:
   - Google Play Console > Create app
   - App name: "Hop 'n Bop"
   - Free app, Game category
   - Accept policies
3. Set up Google Play Games Services:
   - Play Console > Play Games Services > Setup
   - Create a new game project (or link existing Google
     Cloud project from Google OAuth setup)
   - Add your app's package name
   - Note the **Games Services Project ID**
4. Create OAuth credentials for Android:
   - Google Cloud Console > APIs & Services > Credentials
   - Create OAuth client ID > Application type: Android
   - Package name: `com.snoringcat.hopnbop`
   - SHA-1 fingerprint: get from your signing keystore:
     ```powershell
     keytool -list -v -keystore your-key.jks `
       -alias your-alias
     ```
   - Note the **Client ID** (this is different from the web
     client ID)
5. Link Play Games Services:
   - Play Console > Play Games Services > Configuration
   - Add the Android OAuth client from step 4
   - Publish the Play Games Services configuration

**Part B: Auth Integration (Client)**

6. Android auth uses Google Play Games Services sign-in,
   which provides a server auth code. The Godot Android
   export includes a plugin for this:
   - Use a GDScript Android plugin or
     `JavaScriptBridge`-style JNI calls to invoke the Play
     Games sign-in flow
   - On sign-in success, get the server auth code:
   ```gdscript
   # After Play Games sign-in completes:
   var server_auth_code: String = (
       PlayGames.get_server_auth_code()
   )
   G.auth_client.submit_platform_token(
       AuthClient.Provider.GOOGLE, server_auth_code
   )
   ```
   - The backend's existing `_auth_google()` method handles
     this. The server auth code is exchanged via Google's
     token endpoint just like a web OAuth code.
7. No separate backend provider needed. Android uses the
   same `google` provider as web OAuth. The only difference
   is the client ID (Android vs web) and the redirect_uri
   (empty for Android server auth codes).

**Part C: Store Deployment**

8. Prepare store listing:
   - Play Console > Your App > Store Listing
   - Upload screenshots (phone: 1080x1920 min, tablet:
     1920x1200, Chromebook optional)
   - Upload feature graphic (1024x500)
   - Upload app icon (512x512)
   - Short description (80 chars), full description (4000 chars)
   - Content rating: complete IARC questionnaire (free)
   - Set target audience: 13+ (avoid Under 13 to skip COPPA)
9. Complete Data Safety section:
   - Play Console > App Content > Data Safety
   - Declare: Account info (name, user ID), gameplay data
   - Purpose: App functionality, analytics
   - Data shared: No data shared with third parties
   - Data encrypted in transit: Yes
   - Data deletion: Yes (via in-game account deletion)
10. Configure app signing:
    - Play Console > Setup > App Signing
    - Use Google-managed signing (recommended) or upload your
      own key
    - Keep your upload key safe. Losing it means you need to
      contact Google support.
11. Build and upload APK/AAB:
    - In Godot: Project > Export > Android
    - Export as AAB (Android App Bundle, required by Play Store)
    - Upload via Play Console > Release > Production > Create
      new release
    - Or use the Google Play Developer API for CI automation
12. Submit for review:
    - Play Console > Release > Production > Start rollout
    - Google review typically takes 1-3 days for new apps
    - First submission may take longer (up to 7 days)
    - Common rejection reasons: missing privacy policy link,
      incomplete data safety form, permissions not justified

**Testing**: Build Android export, install on a physical device
or emulator. Verify Play Games sign-in triggers automatically,
the auth screen auto-logs in, and the backend validates the
Google server auth code. Test both WiFi and mobile data
connectivity. Verify 60 FPS network tick is sustainable on
target devices.

---

#### iOS / Apple Integration & Deployment (Manual Steps)

**Part A: Apple Developer Setup**

1. Enroll in the Apple Developer Program:
   - Go to developer.apple.com
   - Enroll as an organization (Snoring Cat LLC)
   - Cost: $99/year
   - Requires a D-U-N-S number for your LLC (free from Dun &
     Bradstreet, takes 1-2 weeks if you don't have one)
2. Create an App ID:
   - Certificates, Identifiers & Profiles > Identifiers
   - Register a new App ID
   - Platform: iOS
   - Bundle ID: `com.snoringcat.hopnbop`
   - Capabilities: enable **Sign In with Apple** and
     **Game Center**
3. Create a Services ID (for web Sign In with Apple, if
   needed for account linking):
   - Identifiers > Services IDs
   - Identifier: `com.snoringcat.hopnbop.auth`
   - Enable Sign In with Apple
   - Configure: add domains (`hopnbop.net`) and return URLs
     (`https://hopnbop.net/oauth/callback/`,
     `http://127.0.0.1:9876`)
4. Create a Sign In with Apple private key:
   - Certificates, Identifiers & Profiles > Keys
   - Create a new key, enable Sign In with Apple
   - Download the `.p8` key file (you can only download
     it once)
   - Note the **Key ID** and your **Team ID** (from the
     top-right of the developer portal)
5. Store credentials:
   ```powershell
   aws secretsmanager create-secret `
     --name hopnbop/oauth/apple `
     --secret-string '{"team_id":"YOUR_TEAM_ID","key_id":"YOUR_KEY_ID","client_id":"com.snoringcat.hopnbop.auth","private_key":"-----BEGIN PRIVATE KEY-----\nYOUR_KEY_CONTENTS\n-----END PRIVATE KEY-----"}' `
     --region us-west-2 --profile hopnbop
   ```

**Part B: Auth Integration (Client)**

6. iOS auth uses Game Center or Sign In with Apple. Game
   Center is simpler for games (automatic sign-in, no
   browser needed):
   - Game Center: The player is already signed in at the
     OS level. The game requests a Game Center identity
     token on launch.
   ```gdscript
   # Using Godot's GameCenter singleton (iOS only):
   # Request identity verification signature.
   var result := GameCenter.request_identity_verification()
   # result contains: signature, salt, timestamp, player_id
   # Send to backend as the auth token.
   var token_payload := JSON.stringify({
       "player_id": result.player_id,
       "signature": result.signature,
       "salt": result.salt,
       "timestamp": result.timestamp,
       "bundle_id": "com.snoringcat.hopnbop",
       "public_key_url": result.public_key_url,
   })
   G.auth_client.submit_platform_token(
       AuthClient.Provider.APPLE, token_payload
   )
   ```
7. Backend validation. The `_auth_apple()` method in
   `auth_service.py` validates the Game Center identity
   token by:
   - Fetching Apple's public key from the `public_key_url`
   - Verifying the signature over the concatenated
     player_id + bundle_id + timestamp + salt
   - Returning the Game Center player_id as the provider_id
   Note: If using Sign In with Apple (web flow) instead of
   Game Center, the backend exchanges an authorization code
   via Apple's token endpoint, similar to Google OAuth.

**Part C: Store Deployment**

8. Create the app in App Store Connect:
   - Go to appstoreconnect.apple.com
   - My Apps > "+" > New App
   - Platform: iOS
   - Name: "Hop 'n Bop"
   - Bundle ID: select `com.snoringcat.hopnbop`
   - SKU: `hopnbop`
   - Primary language: English
9. Configure App Privacy:
   - App Store Connect > App > App Privacy
   - Data types collected:
     - Contact Info: Name (from OAuth display name)
     - Identifiers: User ID (player_id)
     - Usage Data: Gameplay data (match stats)
   - For each: Not linked to identity, Not used for tracking
   - Purposes: App Functionality
10. Prepare store listing:
    - Screenshots required for each supported device size:
      - iPhone 6.7" (1290x2796) — required
      - iPhone 6.5" (1284x2778)
      - iPad Pro 12.9" (2048x2732) — if supporting iPad
    - App icon: 1024x1024 (no transparency, no rounded corners)
    - Promotional text (170 chars), description (4000 chars)
    - Keywords (100 chars, comma-separated)
    - Category: Games > Action
    - Age rating: complete the questionnaire (result: 12+
      or 17+ depending on answers about violence)
11. Build and upload:
    - Requires a Mac with Xcode
    - In Godot: Project > Export > iOS
    - Open the generated Xcode project
    - Set signing team to Snoring Cat LLC
    - Archive: Product > Archive
    - Upload to App Store Connect via Xcode Organizer
    - Or use `xcodebuild` + `altool` for CI:
      ```bash
      # These run on macOS (requires Xcode).
      xcodebuild -project HopnBop.xcodeproj \
        -scheme HopnBop -archivePath build/HopnBop.xcarchive \
        archive
      xcodebuild -exportArchive \
        -archivePath build/HopnBop.xcarchive \
        -exportOptionsPlist ExportOptions.plist \
        -exportPath build/ipa
      xcrun altool --upload-app \
        -f build/ipa/HopnBop.ipa \
        -t ios -u "apple-id@email.com" -p "app-specific-pwd"
      ```
12. Submit for review:
    - App Store Connect > Your App > Submit for Review
    - Apple review takes 1-7 days (typically 24-48 hours)
    - **Common rejection reasons**:
      - Missing privacy policy URL
      - Sign In with Apple required if you offer other
        third-party sign-in (Google/Facebook). Since the
        game uses Game Center on iOS, this may not apply.
        But if you show Google/Facebook buttons on iOS,
        you MUST also offer Sign In with Apple.
      - Crashes on launch (test on real devices)
      - Incomplete metadata or placeholder content
      - IPv6 compatibility issues (test on IPv6-only network)
    - If rejected, read the rejection notes carefully,
      fix the issues, and resubmit. You can reply to the
      reviewer via Resolution Center.
13. TestFlight (pre-release testing):
    - Before submitting for production review, upload a
      build and distribute via TestFlight
    - Internal testers (up to 25): instant access, no review
    - External testers (up to 10,000): requires brief beta
      review (usually < 24 hours)
    - Use TestFlight for beta testing before each release

**Important Apple-specific requirements**:
- **Sign In with Apple mandate**: If the iOS app offers
  Google or Facebook login, Apple requires Sign In with
  Apple as an option. On iOS, using Game Center as the
  primary auth method (with no visible third-party login
  buttons) avoids this requirement. Show the
  Google/Facebook linking buttons only in the settings
  panel, not on the login screen.
- **App Transport Security**: All network requests must use
  HTTPS. The backend API already uses HTTPS via API Gateway.
- **Background behavior**: iOS suspends apps aggressively.
  Handle `NOTIFICATION_APPLICATION_PAUSED` and
  `NOTIFICATION_APPLICATION_RESUMED` to pause/resume
  network connections gracefully.

**Testing**: Build iOS export, run on a physical iPhone via
Xcode. Verify Game Center auto-signs in, the auth screen
auto-logs in, and the backend validates the Game Center
identity token. Test on WiFi and cellular. Test
backgrounding the app mid-match and returning.

---

### M3: GameLift Container Fleet Deployment ✅

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

### M4: Legal & Compliance ✅

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

### M5: Monitoring, Logging & Alerting ✅

**Goal**: Production visibility into server health, player
experience, and costs.

**Status**: Code complete. 106 backend tests passing (10 new
telemetry tests). Manual steps remain: deploy with AlertEmail
parameter, confirm SNS subscription, enable DynamoDB PITR,
create AWS Budgets.

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

**TODO**: Add in-game leaderboard display. The web leaderboard
page exists at `web/leaderboard/index.html` and fetches from
the backend API. The in-game UI should show the same data using
a dedicated leaderboard screen.

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

**TODO**: Do not finalize automated release deployment until
blog/patch-notes generation is integrated into the release
flow. Each release should auto-generate an entry in
`web/blog/index.html` with the release version and notes.

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

### M16: Mobile Auth (Android & iOS)

**Goal**: Native OAuth sign-in flows for Android and iOS using
custom URI scheme deep links and platform SDKs.

**What's included**:

*Custom URI Scheme Flow*:
- Register `com.hopnbop.game://` custom URI scheme
- Android: Intent filter in export config captures OAuth redirect
- iOS: URL scheme in Info.plist captures OAuth redirect
- New `_start_mobile_oauth()` path in AuthClient that uses
  `OS.shell_open()` to launch system browser, then receives
  the auth code via deep link when the browser redirects back
- Godot plugin or native extension to surface incoming deep
  link URL to GDScript

*Platform-Native SDK Integration (optional, higher quality)*:
- Google Sign-In for Android (GodotGoogleSignIn plugin or
  custom JNI wrapper)
- Sign in with Apple for iOS (required by App Store if offering
  other social sign-in options)
- These provide a native UI (bottom sheet / system dialog)
  instead of opening a browser tab

*GCP Console Updates*:
- Create **Android** OAuth client ID (package name +
  SHA-1 signing cert)
- Create **iOS** OAuth client ID (bundle ID)
- Add both to `hopnbop/oauth/google` Secrets Manager config
  or create separate per-platform secrets

*AuthClient Changes*:
- Add `_MOBILE_PROVIDERS` list or detect platform at runtime
  via `OS.has_feature("android")` / `OS.has_feature("ios")`
- Route to `_start_mobile_oauth()` from `login_with_provider()`
  when on mobile
- Handle incoming deep link in `_notification()` or via
  platform plugin signal

*Apple Sign-In Requirement*:
- If the iOS app offers Google/Facebook sign-in, Apple requires
  Sign in with Apple as an option
- Implement Apple OAuth flow (already stubbed in
  `auth_service._auth_apple()`)
- Apple Developer account setup: create Services ID, configure
  Sign in with Apple capability

**Manual steps**:
1. GCP Console: Create Android OAuth client (package name,
   SHA-1 from keystore)
2. GCP Console: Create iOS OAuth client (bundle ID)
3. Apple Developer: Enable Sign in with Apple for the app ID
4. Apple Developer: Create Services ID for web/redirect flow
5. Configure Godot Android export with intent filter for
   `com.hopnbop.game://oauth/callback`
6. Configure Godot iOS export with URL scheme
7. Test on physical devices (emulators often lack Google Play
   Services)

**Testing**:
- Android: `adb shell am start -a android.intent.action.VIEW
  -d "com.hopnbop.game://oauth/callback?code=test&state=test"`
  triggers the deep link handler
- iOS: `xcrun simctl openurl booted
  "com.hopnbop.game://oauth/callback?code=test&state=test"`
- End-to-end: Sign in with Google on Android device, verify
  tokens received and player created

**Key files to create/modify**:
- `src/core/auth_client.gd` — Add mobile OAuth path
- `export_presets.cfg` — Android intent filter, iOS URL scheme
- `android/build/AndroidManifest.xml` (if custom build)
- Godot plugin for deep link capture (if needed)

---

## Manual Setup Checklist (One-Time)

### Platform Accounts
- [x] AWS account (Snoring Cat LLC billing)
- [ ] Steam developer account (Steamworks, $100 app fee)
- [ ] Apple Developer account ($99/year)
- [ ] Google Play Console ($25 one-time)
- [ ] Epic Games Store developer account (free)
- [ ] Google Cloud Console project (for OAuth, free tier)
- [ ] Facebook for Developers app (free)
- [ ] itch.io project for Hop 'n Bop (already have account)

### AWS Infrastructure
- [x] IAM admin user with MFA
- [x] AWS CLI configured locally
- [x] SAM CLI installed
- [x] Secrets Manager: JWT signing key
- [ ] Secrets Manager: Google OAuth client secret
- [ ] Secrets Manager: Facebook OAuth client secret
- [ ] SNS topic for alarms, email subscription confirmed
- [ ] S3 bucket for hopnbop.net (see web hosting setup guide)
- [ ] CloudFront distribution with OAC
- [ ] Route 53 hosted zone + DNS records
- [ ] ACM SSL certificate (us-east-1)
- [ ] OAuth callback page deployed to S3
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
