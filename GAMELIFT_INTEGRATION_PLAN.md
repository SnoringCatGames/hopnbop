# GameLift Session ID Backend Integration

## Problem

The client's `_client_send_player_declaration()` at [network_connector.gd:169](c:\Users\lsl\Repositories\jumpnthump\src\networking\network_connector.gd#L169) uses placeholder "DEBUG_ID_X" values instead of real GameLift player session IDs. The server validation infrastructure is ready but lacks the client-side integration to obtain session IDs from a backend service.

## Implementation Plan Overview

This plan is divided into three parts:

1. **Part 1:** Godot client integration (LocalSession, GameLiftSessionManager, game flow)
2. **Part 2:** Python backend service architecture (Lambda, DynamoDB, OAuth)
3. **Part 3:** Manual AWS and OAuth configuration steps

**First Step:** Copy this plan to `GAMELIFT_INTEGRATION_PLAN.md` in the project root for easy reference.

## Solution Overview

Implement a backend service integration that requests player session IDs from an external matchmaking API before connecting to the GameLift game server. The flow will be:

1. Client requests session IDs from backend API
2. Backend returns session IDs + server connection info
3. Client stores session IDs in LocalSession
4. Client connects and sends stored session IDs
5. Server validates via existing GameLiftManager

## Implementation Steps

### 1. Extend LocalSession Data Model

**File:** [src/core/local_session.gd](src/core/local_session.gd)

Add session ID storage:
```gdscript
# NEW: Session IDs from backend (one per local player)
var session_ids: Array[String] = []

func has_valid_session_ids() -> bool:
    if session_ids.size() != device_configs.size():
        return false
    for session_id in session_ids:
        if session_id.is_empty():
            return false
    return true

func clear() -> void:
    is_game_active = false
    is_game_loading = false
    session_ids.clear()  # NEW
```

### 2. Create GameLiftSessionManager

**New File:** `src/networking/game_lift_session_manager.gd`

Core responsibilities:
- HTTP requests to backend matchmaking API
- Parse session IDs from JSON response
- Handle preview mode with debug IDs
- Emit signals for async completion

**Key API contract:**
```
POST /matchmaking/join
Request: {"player_count": 2, "client_id": "..."}
Response: {
    "status": "success",
    "player_session_ids": ["psess-...", "psess-..."],
    "server_ip": "54.123.45.67",
    "server_port": 4433
}
```

**Signals:**
- `session_ids_received(session_ids: Array, server_ip: String, server_port: int)`
- `session_request_failed(error_message: String)`

**Preview mode bypass:** When `use_gamelift = false` or `is_preview = true`, generate debug IDs immediately without HTTP request.

### 3. Add Backend Configuration

**File:** [src/core/settings.gd](src/core/settings.gd#L38)

Add to GameLift export group:
```gdscript
@export var gamelift_backend_api_url := "https://api.example.com"
@export var gamelift_matchmaking_timeout_sec := 30.0
```

### 4. Wire SessionManager into NetworkMain

**File:** [src/networking/network_main.gd](src/networking/network_main.gd#L54)

Add as child node:
```gdscript
var session_manager := GameLiftSessionManager.new()

func _enter_tree() -> void:
    # ... existing nodes ...
    session_manager.name = "GameLiftSessionManager"
    session_manager.backend_api_url = G.settings.gamelift_backend_api_url
    session_manager.request_timeout_sec = G.settings.gamelift_matchmaking_timeout_sec
    add_child(session_manager)
```

### 5. Integrate into Game Loading Flow

**File:** [src/core/game_panel.gd](src/core/game_panel.gd#L158)

Modify `client_load_game()` to request session IDs before connecting:

```gdscript
func client_load_game() -> void:
    # ... existing setup ...
    G.screens.client_open_screen(ScreensMain.ScreenType.LOADING)

    # NEW: Request session IDs instead of connecting immediately
    _client_request_session_ids()

func _client_request_session_ids() -> void:
    var player_count := G.local_session.local_player_count

    # Connect signals
    G.network.session_manager.session_ids_received.connect(
        _client_on_session_ids_received)
    G.network.session_manager.session_request_failed.connect(
        _client_on_session_request_failed)

    # Make request
    G.network.session_manager.request_session_ids(player_count)

func _client_on_session_ids_received(
        session_ids: Array,
        server_ip: String,
        server_port: int) -> void:
    # Store in LocalSession
    G.local_session.session_ids = []
    for session_id in session_ids:
        G.local_session.session_ids.append(str(session_id))

    # Update connection settings if provided
    if not server_ip.is_empty():
        G.settings.remote_server_ip_address = server_ip
        G.settings.remote_server_port = server_port
        G.settings.preview_connect_to_remote_server = true

    # Connect to server
    G.network.connector.client_connect_to_server()

func _client_on_session_request_failed(error_message: String) -> void:
    G.log.alert_user(
        "Failed to obtain session IDs: %s" % error_message,
        ScaffolderLog.CATEGORY_CORE_SYSTEMS)
    client_exit_game()
```

### 6. Use Stored Session IDs in Declaration

**File:** [src/networking/network_connector.gd](src/networking/network_connector.gd#L169)

Replace FIXME with actual retrieval:

```gdscript
func _client_send_player_declaration() -> void:
    var player_count := G.local_session.local_player_count

    # Use stored session IDs
    var session_ids: Array = []
    if G.local_session.has_valid_session_ids():
        session_ids = G.local_session.session_ids.duplicate()
    else:
        # Fallback for error state
        G.warning("No valid session IDs, using debug IDs")
        for i in range(player_count):
            session_ids.append(str("DEBUG_ID_%d" % i))

    # Send to server
    _server_rpc_declare_players.rpc_id(SERVER_ID, session_ids)
```

### 7. Add Error Handling

**Timeout handling:** HTTPRequest has built-in timeout, add manual timer as backup.

**Retry logic:** Retry up to 3 times with 2-second delay between attempts.

**Validation:** Check session count matches player count before connecting.

### 8. Update Loading Screen (Optional Enhancement)

**File:** [src/ui/screens/loading_screen.gd](src/ui/screens/loading_screen.gd)

Add status label to show "Requesting game session..." and "Connecting to server..." feedback.

## Mode Handling

**Preview Mode** (`use_gamelift = false` OR `is_preview = true`):
- Generate debug session IDs immediately: `["DEBUG_ID_0", "DEBUG_ID_1", ...]`
- Use local server IP/port from settings
- No HTTP request made
- Server auto-accepts without GameLift validation

**Production Mode** (`use_gamelift = true` AND `is_preview = false`):
- Make real HTTP request to backend API
- Use returned session IDs and server connection info
- Server validates via `_gamelift.accept_player_session()`

## Critical Files

1. **src/networking/game_lift_session_manager.gd** (NEW) - Backend HTTP integration
2. **src/core/local_session.gd** (MODIFY) - Add session_ids storage
3. **src/core/game_panel.gd** (MODIFY) - Orchestrate session request flow
4. **src/networking/network_connector.gd** (MODIFY) - Use stored session IDs
5. **src/core/settings.gd** (MODIFY) - Add backend API configuration
6. **src/networking/network_main.gd** (MODIFY) - Wire up SessionManager

## Verification Steps

### Preview Mode Testing:
1. Launch client with `--client=1 --preview`
2. Verify debug session IDs are generated immediately
3. Verify connection succeeds to local server
4. Check logs show "Using debug IDs"

### Production Mode Testing:
1. Configure `gamelift_backend_api_url` in settings
2. Set `use_gamelift = true`
3. Launch client
4. Verify HTTP request is made to backend
5. Verify session IDs are received and stored
6. Verify server validates via GameLift SDK
7. Check GameLiftManager logs show successful validation

### Multi-Player Testing:
1. Configure 2 local players in lobby
2. Request session IDs
3. Verify 2 session IDs returned
4. Verify both players declared to server
5. Verify both players validated by GameLiftManager

### Error Handling:
1. Test with backend unreachable
2. Verify retry logic triggers
3. Verify user sees error message after max retries
4. Test with invalid backend response (malformed JSON)
5. Test with session count mismatch

### Integration Test:
Run existing test: [test/integration/networking/test_multi_player_declaration.gd](test/integration/networking/test_multi_player_declaration.gd)

Verify all tests still pass with new session ID flow.

## Security Notes

- Backend API should require authentication (add API key header)
- Use HTTPS only in production
- Session IDs are validated server-side by GameLift SDK
- Rate limiting should be implemented on backend

## Performance Impact

- Adds ~50-500ms latency for backend request before connecting
- Minimal memory overhead (session IDs are ~50 bytes each)
- No impact during gameplay (only during connection phase)

---

# Part 2: Backend Service Architecture

## Overview

The backend service handles player authentication, matchmaking orchestration, and GameLift session management. It runs on AWS Lambda with API Gateway as the HTTP frontend.

## Architecture Components

### Technology Stack

- **Compute:** AWS Lambda (Python 3.12)
- **API:** API Gateway (REST API)
- **Auth:** Amazon Cognito + OAuth2 providers (Steam, Epic, Google)
- **Database:** DynamoDB (player profiles, ratings, match history)
- **GameLift SDK:** boto3 client for GameLift API calls
- **Deployment:** AWS SAM or Terraform

### Service Responsibilities

1. **Player Authentication**
   - OAuth2 integration with Steam, Epic Games, Google
   - Issue JWT tokens with player claims
   - Manage player profiles and ratings

2. **Matchmaking Orchestration**
   - Call GameLift StartMatchmaking API
   - Poll DescribeMatchmaking until match completes
   - Return player_session_ids to clients

3. **Session Management**
   - Track active matchmaking tickets
   - Handle ticket cancellation
   - Timeout stale requests

4. **Rate Limiting & Security**
   - Request throttling per player
   - JWT token validation
   - Input sanitization

## API Specification

### Endpoint 1: Player Authentication

```
POST /auth/login
Authorization: Bearer <oauth_token>

Request:
{
  "provider": "steam",
  "auth_code": "abc123...",
  "redirect_uri": "https://game.example.com/callback"
}

Response (200):
{
  "status": "success",
  "jwt_token": "eyJhbGc...",
  "player_id": "player-uuid-123",
  "display_name": "PlayerName",
  "expires_at": 1735689600
}

Response (401):
{
  "status": "error",
  "error_code": "INVALID_TOKEN",
  "message": "OAuth token validation failed"
}
```

### Endpoint 2: Start Matchmaking

```
POST /matchmaking/start
Authorization: Bearer <jwt_token>

Request:
{
  "player_count": 2,
  "player_attributes": {
    "skill": 1500,
    "region": "us-west-2"
  },
  "matchmaking_config": "FFA-4Player"
}

Response (200):
{
  "status": "success",
  "ticket_id": "ticket-abc123",
  "estimated_wait_ms": 5000
}

Response (429):
{
  "status": "error",
  "error_code": "RATE_LIMIT",
  "message": "Too many matchmaking requests",
  "retry_after_sec": 60
}
```

### Endpoint 3: Poll Matchmaking Status

```
GET /matchmaking/status/{ticket_id}
Authorization: Bearer <jwt_token>

Response (200 - In Progress):
{
  "status": "searching",
  "ticket_id": "ticket-abc123",
  "estimated_wait_ms": 3000,
  "players_found": 2,
  "players_needed": 4
}

Response (200 - Complete):
{
  "status": "success",
  "ticket_id": "ticket-abc123",
  "game_session_id": "gamesession-xyz789",
  "server_ip": "54.123.45.67",
  "server_port": 4433,
  "player_session_ids": [
    "psess-111111-1111-1111-1111-111111111111",
    "psess-222222-2222-2222-2222-222222222222"
  ]
}

Response (200 - Failed):
{
  "status": "failed",
  "error_code": "MATCHMAKING_TIMEOUT",
  "message": "No suitable match found within timeout"
}
```

### Endpoint 4: Cancel Matchmaking

```
POST /matchmaking/cancel/{ticket_id}
Authorization: Bearer <jwt_token>

Response (200):
{
  "status": "success",
  "ticket_id": "ticket-abc123"
}
```

## Python Implementation

### Project Structure

```
backend/
├── src/
│   ├── handlers/
│   │   ├── auth_handler.py          # OAuth2 + JWT
│   │   ├── matchmaking_handler.py   # GameLift integration
│   │   └── health_handler.py        # Health check
│   ├── services/
│   │   ├── gamelift_service.py      # GameLift SDK wrapper
│   │   ├── auth_service.py          # Token validation
│   │   ├── player_service.py        # DynamoDB player CRUD
│   │   └── rate_limiter.py          # Request throttling
│   ├── models/
│   │   ├── player.py                # Player dataclass
│   │   ├── match_ticket.py          # Matchmaking ticket
│   │   └── auth_token.py            # JWT token model
│   └── utils/
│       ├── validators.py            # Input validation
│       ├── logger.py                # Structured logging
│       └── config.py                # Environment config
├── tests/
│   ├── unit/
│   └── integration/
├── template.yaml                    # AWS SAM template
├── requirements.txt
└── README.md
```

### Core Implementation: GameLift Service

**File:** `src/services/gamelift_service.py`

```python
import asyncio
import boto3
from typing import List, Dict, Optional
from dataclasses import dataclass
from datetime import datetime
from botocore.exceptions import ClientError

@dataclass
class MatchmakingPlayer:
    player_id: str
    skill_rating: int
    region: str
    latency_map: Dict[str, int]

@dataclass
class MatchResult:
    ticket_id: str
    game_session_id: str
    server_ip: str
    server_port: int
    player_session_ids: List[str]

class GameLiftService:
    """Wrapper for AWS GameLift API operations"""

    def __init__(
        self,
        region: str = 'us-west-2',
        poll_interval_sec: float = 1.0,
        max_poll_time_sec: float = 120.0
    ):
        self.client = boto3.client('gamelift', region_name=region)
        self.poll_interval = poll_interval_sec
        self.max_poll_time = max_poll_time_sec

    async def start_matchmaking(
        self,
        config_name: str,
        players: List[MatchmakingPlayer],
        ticket_id: Optional[str] = None
    ) -> str:
        """
        Start FlexMatch matchmaking

        Returns:
            ticket_id (str): Matchmaking ticket ID for polling
        """
        player_dicts = [
            {
                'PlayerId': p.player_id,
                'PlayerAttributes': {
                    'skill': {'N': str(p.skill_rating)},
                    'region': {'S': p.region}
                },
                'LatencyInMs': p.latency_map
            }
            for p in players
        ]

        try:
            response = self.client.start_matchmaking(
                ConfigurationName=config_name,
                TicketId=ticket_id,
                Players=player_dicts
            )
            return response['MatchmakingTicket']['TicketId']

        except ClientError as e:
            error_code = e.response['Error']['Code']
            if error_code == 'InvalidRequestException':
                raise ValueError(f"Invalid matchmaking request: {e}")
            elif error_code == 'UnsupportedRegionException':
                raise ValueError(f"Region not supported: {e}")
            else:
                raise

    async def poll_matchmaking(
        self,
        ticket_id: str
    ) -> MatchResult:
        """
        Poll matchmaking ticket until COMPLETED or failure

        Returns:
            MatchResult with connection info and player_session_ids

        Raises:
            TimeoutError: Polling exceeded max_poll_time
            ValueError: Matchmaking failed, timed out, or cancelled
        """
        start_time = datetime.now()

        while True:
            # Check timeout
            elapsed = (datetime.now() - start_time).total_seconds()
            if elapsed > self.max_poll_time:
                # Cancel stale ticket
                await self.cancel_matchmaking(ticket_id)
                raise TimeoutError(
                    f"Matchmaking polling timeout after {elapsed}s"
                )

            # Poll ticket status
            try:
                response = self.client.describe_matchmaking(
                    TicketIds=[ticket_id]
                )
            except ClientError as e:
                raise ValueError(f"Failed to describe ticket: {e}")

            if not response['TicketList']:
                raise ValueError(f"Ticket {ticket_id} not found")

            ticket = response['TicketList'][0]
            status = ticket['Status']

            # Success - match found
            if status == 'COMPLETED':
                conn_info = ticket['GameSessionConnectionInfo']

                return MatchResult(
                    ticket_id=ticket_id,
                    game_session_id=conn_info['GameSessionArn'].split('/')[-1],
                    server_ip=conn_info['IpAddress'],
                    server_port=conn_info['Port'],
                    player_session_ids=[
                        mp['PlayerSessionId']
                        for mp in conn_info['MatchedPlayerSessions']
                    ]
                )

            # Terminal failure states
            if status == 'FAILED':
                reason = ticket.get('StatusReason', 'Unknown')
                raise ValueError(f"Matchmaking failed: {reason}")

            if status == 'TIMED_OUT':
                raise TimeoutError("GameLift matchmaking timeout")

            if status == 'CANCELLED':
                raise ValueError("Matchmaking cancelled")

            # Still in progress (QUEUED, SEARCHING, PLACING)
            await asyncio.sleep(self.poll_interval)

    async def cancel_matchmaking(self, ticket_id: str) -> None:
        """Cancel active matchmaking ticket"""
        try:
            self.client.stop_matchmaking(TicketId=ticket_id)
        except ClientError as e:
            error_code = e.response['Error']['Code']
            if error_code != 'NotFoundException':
                raise

    async def get_ticket_status(
        self,
        ticket_id: str
    ) -> Dict:
        """Get current ticket status without blocking"""
        try:
            response = self.client.describe_matchmaking(
                TicketIds=[ticket_id]
            )
        except ClientError as e:
            raise ValueError(f"Failed to get ticket: {e}")

        if not response['TicketList']:
            raise ValueError(f"Ticket {ticket_id} not found")

        ticket = response['TicketList'][0]

        result = {
            'status': ticket['Status'].lower(),
            'ticket_id': ticket_id,
        }

        # Add estimated wait time if available
        if 'EstimatedWaitTime' in ticket:
            result['estimated_wait_ms'] = ticket['EstimatedWaitTime']

        # Add match progress if available
        if 'Players' in ticket:
            result['players_needed'] = len(ticket['Players'])

        return result
```

### Core Implementation: Auth Service

**File:** `src/services/auth_service.py`

```python
import jwt
import httpx
from datetime import datetime, timedelta
from typing import Optional, Dict
from dataclasses import dataclass

@dataclass
class AuthToken:
    player_id: str
    display_name: str
    provider: str
    issued_at: datetime
    expires_at: datetime

    def to_jwt(self, secret: str) -> str:
        """Encode as JWT"""
        payload = {
            'sub': self.player_id,
            'name': self.display_name,
            'provider': self.provider,
            'iat': int(self.issued_at.timestamp()),
            'exp': int(self.expires_at.timestamp())
        }
        return jwt.encode(payload, secret, algorithm='HS256')

    @classmethod
    def from_jwt(cls, token: str, secret: str) -> 'AuthToken':
        """Decode and validate JWT"""
        try:
            payload = jwt.decode(token, secret, algorithms=['HS256'])
        except jwt.ExpiredSignatureError:
            raise ValueError("Token expired")
        except jwt.InvalidTokenError:
            raise ValueError("Invalid token")

        return cls(
            player_id=payload['sub'],
            display_name=payload['name'],
            provider=payload['provider'],
            issued_at=datetime.fromtimestamp(payload['iat']),
            expires_at=datetime.fromtimestamp(payload['exp'])
        )

class AuthService:
    """OAuth2 provider integration"""

    def __init__(self, jwt_secret: str, token_lifetime_hours: int = 24):
        self.jwt_secret = jwt_secret
        self.token_lifetime = timedelta(hours=token_lifetime_hours)

    async def authenticate_steam(
        self,
        steam_ticket: str
    ) -> AuthToken:
        """
        Validate Steam session ticket
        https://partner.steamgames.com/doc/webapi/ISteamUserAuth#AuthenticateUserTicket
        """
        # Call Steam Web API to validate ticket
        async with httpx.AsyncClient() as client:
            response = await client.get(
                'https://api.steampowered.com/ISteamUserAuth/AuthenticateUserTicket/v1/',
                params={
                    'key': self._get_steam_api_key(),
                    'appid': self._get_steam_app_id(),
                    'ticket': steam_ticket
                }
            )

        if response.status_code != 200:
            raise ValueError("Steam authentication failed")

        data = response.json()
        if 'response' not in data or 'params' not in data['response']:
            raise ValueError("Invalid Steam response")

        params = data['response']['params']
        steam_id = params['steamid']

        # Get player profile
        display_name = await self._get_steam_username(steam_id)

        # Issue JWT
        now = datetime.now()
        return AuthToken(
            player_id=f"steam_{steam_id}",
            display_name=display_name,
            provider='steam',
            issued_at=now,
            expires_at=now + self.token_lifetime
        )

    async def authenticate_epic(
        self,
        access_token: str
    ) -> AuthToken:
        """Validate Epic Games OAuth token"""
        # Call Epic Games API to validate token
        async with httpx.AsyncClient() as client:
            response = await client.get(
                'https://api.epicgames.dev/epic/oauth/v1/verify',
                headers={'Authorization': f'Bearer {access_token}'}
            )

        if response.status_code != 200:
            raise ValueError("Epic authentication failed")

        data = response.json()
        epic_id = data['account_id']
        display_name = data.get('display_name', f"Player_{epic_id[:8]}")

        now = datetime.now()
        return AuthToken(
            player_id=f"epic_{epic_id}",
            display_name=display_name,
            provider='epic',
            issued_at=now,
            expires_at=now + self.token_lifetime
        )

    async def authenticate_cognito(
        self,
        cognito_token: str
    ) -> AuthToken:
        """Validate AWS Cognito JWT"""
        # Cognito tokens are already JWTs, verify signature
        # https://docs.aws.amazon.com/cognito/latest/developerguide/amazon-cognito-user-pools-using-tokens-verifying-a-jwt.html

        # This is simplified - real implementation needs:
        # 1. Download Cognito JWKS
        # 2. Verify signature with public key
        # 3. Check issuer, audience, expiration

        try:
            payload = jwt.decode(
                cognito_token,
                options={"verify_signature": False}  # Verify with JWKS in production
            )
        except jwt.InvalidTokenError:
            raise ValueError("Invalid Cognito token")

        cognito_id = payload['sub']
        display_name = payload.get('cognito:username', f"Player_{cognito_id[:8]}")

        now = datetime.now()
        return AuthToken(
            player_id=f"cognito_{cognito_id}",
            display_name=display_name,
            provider='cognito',
            issued_at=now,
            expires_at=now + self.token_lifetime
        )

    def _get_steam_api_key(self) -> str:
        """Get from environment/Parameter Store"""
        import os
        return os.environ['STEAM_API_KEY']

    def _get_steam_app_id(self) -> str:
        """Get from environment"""
        import os
        return os.environ['STEAM_APP_ID']

    async def _get_steam_username(self, steam_id: str) -> str:
        """Fetch Steam username via ISteamUser API"""
        async with httpx.AsyncClient() as client:
            response = await client.get(
                'https://api.steampowered.com/ISteamUser/GetPlayerSummaries/v2/',
                params={
                    'key': self._get_steam_api_key(),
                    'steamids': steam_id
                }
            )

        data = response.json()
        players = data.get('response', {}).get('players', [])
        if players:
            return players[0].get('personaname', f"Player_{steam_id[:8]}")

        return f"Player_{steam_id[:8]}"
```

### Lambda Handler: Matchmaking

**File:** `src/handlers/matchmaking_handler.py`

```python
import json
import os
import asyncio
from typing import Dict, Any
from aws_lambda_powertools import Logger, Tracer
from aws_lambda_powertools.utilities.typing import LambdaContext

from services.gamelift_service import GameLiftService, MatchmakingPlayer
from services.auth_service import AuthService
from services.player_service import PlayerService
from services.rate_limiter import RateLimiter

logger = Logger()
tracer = Tracer()

# Initialize services (cached across invocations)
gamelift = GameLiftService(
    region=os.environ['AWS_REGION'],
    poll_interval_sec=1.0,
    max_poll_time_sec=120.0
)
auth_service = AuthService(jwt_secret=os.environ['JWT_SECRET'])
player_service = PlayerService()
rate_limiter = RateLimiter()

@tracer.capture_lambda_handler
@logger.inject_lambda_context
def start_matchmaking(event: Dict[str, Any], context: LambdaContext) -> Dict:
    """
    POST /matchmaking/start
    Start GameLift FlexMatch matchmaking
    """
    try:
        # Extract JWT from Authorization header
        auth_header = event['headers'].get('Authorization', '')
        if not auth_header.startswith('Bearer '):
            return error_response(401, 'MISSING_AUTH', 'Missing authorization')

        jwt_token = auth_header[7:]
        auth_token = AuthService.from_jwt(jwt_token, os.environ['JWT_SECRET'])
        player_id = auth_token.player_id

        # Rate limiting
        if not rate_limiter.check_limit(player_id, 'matchmaking', max_per_min=5):
            return error_response(429, 'RATE_LIMIT', 'Too many requests', retry_after=60)

        # Parse request body
        body = json.loads(event['body'])
        player_count = body.get('player_count', 1)
        player_attrs = body.get('player_attributes', {})
        config_name = body.get('matchmaking_config', 'Default')

        # Validate input
        if player_count < 1 or player_count > 4:
            return error_response(400, 'INVALID_INPUT', 'player_count must be 1-4')

        # Get player profile for skill rating
        player_profile = asyncio.run(player_service.get_player(player_id))
        if not player_profile:
            return error_response(404, 'PLAYER_NOT_FOUND', 'Player profile not found')

        # Create matchmaking players (one per local player)
        players = [
            MatchmakingPlayer(
                player_id=f"{player_id}_{i}",
                skill_rating=player_attrs.get('skill', player_profile.rating),
                region=player_attrs.get('region', 'us-west-2'),
                latency_map=player_attrs.get('latency_map', {'us-west-2': 50})
            )
            for i in range(player_count)
        ]

        # Start matchmaking
        ticket_id = asyncio.run(gamelift.start_matchmaking(
            config_name=config_name,
            players=players
        ))

        logger.info(f"Started matchmaking for {player_id}: {ticket_id}")

        return {
            'statusCode': 200,
            'body': json.dumps({
                'status': 'success',
                'ticket_id': ticket_id,
                'estimated_wait_ms': 5000
            })
        }

    except ValueError as e:
        return error_response(400, 'VALIDATION_ERROR', str(e))
    except Exception as e:
        logger.exception("Matchmaking error")
        return error_response(500, 'INTERNAL_ERROR', 'Internal server error')

@tracer.capture_lambda_handler
@logger.inject_lambda_context
def get_matchmaking_status(event: Dict[str, Any], context: LambdaContext) -> Dict:
    """
    GET /matchmaking/status/{ticket_id}
    Poll matchmaking ticket status
    """
    try:
        # Auth
        auth_header = event['headers'].get('Authorization', '')
        jwt_token = auth_header[7:]
        auth_token = AuthService.from_jwt(jwt_token, os.environ['JWT_SECRET'])

        # Get ticket ID from path
        ticket_id = event['pathParameters']['ticket_id']

        # Try non-blocking status check first
        status = asyncio.run(gamelift.get_ticket_status(ticket_id))

        # If still in progress, return current status
        if status['status'] in ['queued', 'searching', 'placing']:
            return {
                'statusCode': 200,
                'body': json.dumps(status)
            }

        # If completed, do full poll to get connection info
        if status['status'] == 'completed':
            result = asyncio.run(gamelift.poll_matchmaking(ticket_id))

            return {
                'statusCode': 200,
                'body': json.dumps({
                    'status': 'success',
                    'ticket_id': ticket_id,
                    'game_session_id': result.game_session_id,
                    'server_ip': result.server_ip,
                    'server_port': result.server_port,
                    'player_session_ids': result.player_session_ids
                })
            }

        # Failed/cancelled/timeout
        return {
            'statusCode': 200,
            'body': json.dumps({
                'status': 'failed',
                'error_code': status['status'].upper(),
                'message': f"Matchmaking {status['status']}"
            })
        }

    except ValueError as e:
        return error_response(400, 'VALIDATION_ERROR', str(e))
    except Exception as e:
        logger.exception("Status check error")
        return error_response(500, 'INTERNAL_ERROR', 'Internal server error')

def error_response(
    status_code: int,
    error_code: str,
    message: str,
    retry_after: int = None
) -> Dict:
    """Format error response"""
    body = {
        'status': 'error',
        'error_code': error_code,
        'message': message
    }

    headers = {'Content-Type': 'application/json'}
    if retry_after:
        headers['Retry-After'] = str(retry_after)

    return {
        'statusCode': status_code,
        'headers': headers,
        'body': json.dumps(body)
    }
```

## DynamoDB Schema

### Players Table

```
Table: players
Partition Key: player_id (String)

Attributes:
- player_id: String (e.g., "steam_76561198012345678")
- display_name: String
- rating: Number (skill rating 0-5000)
- matches_played: Number
- wins: Number
- losses: Number
- created_at: Number (Unix timestamp)
- last_active: Number (Unix timestamp)
- auth_provider: String (steam, epic, cognito)

GSI: auth_provider-index
- Partition Key: auth_provider
- Sort Key: last_active
```

### Match History Table

```
Table: match_history
Partition Key: player_id (String)
Sort Key: match_timestamp (Number)

Attributes:
- player_id: String
- match_id: String
- match_timestamp: Number
- game_session_id: String
- result: String (win, loss, draw)
- kills: Number
- deaths: Number
- duration_sec: Number
```

## AWS SAM Deployment Template

**File:** `template.yaml`

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Transform: AWS::Serverless-2016-10-31
Description: Jump 'n Thump GameLift Backend

Globals:
  Function:
    Timeout: 30
    Runtime: python3.12
    MemorySize: 512
    Environment:
      Variables:
        PLAYERS_TABLE: !Ref PlayersTable
        MATCH_HISTORY_TABLE: !Ref MatchHistoryTable
        JWT_SECRET: !Ref JWTSecret
        STEAM_API_KEY: !Ref SteamAPIKey
        STEAM_APP_ID: !Ref SteamAppID

Parameters:
  JWTSecret:
    Type: String
    NoEcho: true
    Description: Secret key for JWT signing

  SteamAPIKey:
    Type: String
    NoEcho: true
    Description: Steam Web API key

  SteamAppID:
    Type: String
    Description: Steam App ID

Resources:
  # API Gateway
  GameBackendAPI:
    Type: AWS::Serverless::Api
    Properties:
      StageName: prod
      Cors:
        AllowMethods: "'GET,POST,OPTIONS'"
        AllowHeaders: "'Content-Type,Authorization'"
        AllowOrigin: "'*'"
      Auth:
        ApiKeyRequired: false

  # Lambda Functions
  AuthLoginFunction:
    Type: AWS::Serverless::Function
    Properties:
      CodeUri: src/
      Handler: handlers.auth_handler.login
      Events:
        Login:
          Type: Api
          Properties:
            RestApiId: !Ref GameBackendAPI
            Path: /auth/login
            Method: post

  StartMatchmakingFunction:
    Type: AWS::Serverless::Function
    Properties:
      CodeUri: src/
      Handler: handlers.matchmaking_handler.start_matchmaking
      Policies:
        - GameLiftFullAccess
        - DynamoDBCrudPolicy:
            TableName: !Ref PlayersTable
      Events:
        StartMatch:
          Type: Api
          Properties:
            RestApiId: !Ref GameBackendAPI
            Path: /matchmaking/start
            Method: post

  GetMatchStatusFunction:
    Type: AWS::Serverless::Function
    Properties:
      CodeUri: src/
      Handler: handlers.matchmaking_handler.get_matchmaking_status
      Policies:
        - GameLiftReadOnlyAccess
      Events:
        GetStatus:
          Type: Api
          Properties:
            RestApiId: !Ref GameBackendAPI
            Path: /matchmaking/status/{ticket_id}
            Method: get

  # DynamoDB Tables
  PlayersTable:
    Type: AWS::DynamoDB::Table
    Properties:
      TableName: jumpnthump-players
      BillingMode: PAY_PER_REQUEST
      AttributeDefinitions:
        - AttributeName: player_id
          AttributeType: S
        - AttributeName: auth_provider
          AttributeType: S
        - AttributeName: last_active
          AttributeType: N
      KeySchema:
        - AttributeName: player_id
          KeyType: HASH
      GlobalSecondaryIndexes:
        - IndexName: auth_provider-index
          KeySchema:
            - AttributeName: auth_provider
              KeyType: HASH
            - AttributeName: last_active
              KeyType: RANGE
          Projection:
            ProjectionType: ALL

  MatchHistoryTable:
    Type: AWS::DynamoDB::Table
    Properties:
      TableName: jumpnthump-match-history
      BillingMode: PAY_PER_REQUEST
      AttributeDefinitions:
        - AttributeName: player_id
          AttributeType: S
        - AttributeName: match_timestamp
          AttributeType: N
      KeySchema:
        - AttributeName: player_id
          KeyType: HASH
        - AttributeName: match_timestamp
          KeyType: RANGE

Outputs:
  ApiEndpoint:
    Description: "API Gateway endpoint URL"
    Value: !Sub "https://${GameBackendAPI}.execute-api.${AWS::Region}.amazonaws.com/prod"

  PlayersTableName:
    Description: "DynamoDB players table"
    Value: !Ref PlayersTable
```

## Deployment Instructions

### Prerequisites

1. Install AWS SAM CLI
   ```bash
   pip install aws-sam-cli
   ```

2. Configure AWS credentials
   ```bash
   aws configure
   ```

3. Register Steam Web API key
   - Go to https://steamcommunity.com/dev/apikey
   - Register your domain
   - Note the API key

### Deploy Steps

1. Clone backend repository
   ```bash
   git clone <backend-repo>
   cd backend/
   ```

2. Install dependencies
   ```bash
   pip install -r requirements.txt -t src/
   ```

3. Build SAM application
   ```bash
   sam build
   ```

4. Deploy (first time)
   ```bash
   sam deploy --guided
   ```

   Provide parameters:
   - Stack Name: `jumpnthump-backend`
   - AWS Region: `us-west-2`
   - JWTSecret: Generate with `openssl rand -base64 32`
   - SteamAPIKey: Your Steam Web API key
   - SteamAppID: Your Steam App ID

5. Note the API endpoint from outputs
   ```
   Outputs:
   ApiEndpoint = https://abc123.execute-api.us-west-2.amazonaws.com/prod
   ```

6. Update Godot settings.tres
   ```
   gamelift_backend_api_url = "https://abc123.execute-api.us-west-2.amazonaws.com/prod"
   ```

### Update Existing Deployment

```bash
sam build && sam deploy
```

## Security Best Practices

### 1. JWT Token Security

- Use strong secret (256-bit minimum)
- Store in AWS Secrets Manager
- Rotate regularly (every 90 days)
- Short expiration (24 hours)
- Implement refresh tokens

### 2. Rate Limiting

Implement per-player throttling:
```python
# Allow 5 matchmaking requests per minute per player
# Allow 30 status checks per minute per player
# Allow 10 auth attempts per hour per IP
```

### 3. Input Validation

- Validate all request parameters
- Sanitize player-provided strings
- Enforce min/max ranges for ratings, player counts
- Reject suspiciously large payloads

### 4. API Gateway Protection

- Enable AWS WAF
- Add IP throttling rules
- Block known malicious IPs
- Enable CloudWatch alarms for anomalies

### 5. GameLift Security

- Use VPC for game servers
- Restrict security groups
- Enable GameLift TLS
- Validate all player_session_ids server-side

### 6. Secrets Management

Store sensitive values in AWS Secrets Manager:
```python
import boto3
from functools import lru_cache

@lru_cache(maxsize=1)
def get_secret(secret_name: str) -> str:
    client = boto3.client('secretsmanager')
    response = client.get_secret_value(SecretId=secret_name)
    return response['SecretString']

# Usage
jwt_secret = get_secret('jumpnthump/jwt-secret')
```

## Cost Estimates

### Monthly Costs (1000 active players)

**Lambda:**
- 100,000 matchmaking requests/month
- Avg 2s execution @ 512MB
- Cost: ~$1.00/month (free tier covers)

**API Gateway:**
- 100,000 API calls
- Cost: ~$0.35/month

**DynamoDB:**
- 1000 players × 10KB = 10MB storage
- 100K read/write requests
- Cost: ~$1.25/month (free tier covers)

**GameLift:** (Most expensive)
- 10 c5.large instances (game servers)
- Cost: ~$700/month
- Consider Spot pricing for 70% savings

**Total Estimated:** ~$750/month for 1000 concurrent players

### Scaling Considerations

- Lambda auto-scales to 1000 concurrent executions
- DynamoDB on-demand scales automatically
- GameLift fleet scales based on player demand
- Add CloudFront CDN for global latency ($0.085/GB)

## Monitoring & Observability

### CloudWatch Metrics

Track:
- Matchmaking success rate
- Average matchmaking wait time
- Lambda errors and duration
- DynamoDB throttling
- API Gateway 4xx/5xx rates

### Alarms

```yaml
MatchmakingFailureAlarm:
  Type: AWS::CloudWatch::Alarm
  Properties:
    MetricName: Errors
    Namespace: AWS/Lambda
    Statistic: Sum
    Period: 300
    EvaluationPeriods: 1
    Threshold: 10
    ComparisonOperator: GreaterThanThreshold
    AlarmActions:
      - !Ref SNSTopic
```

### Logging

Use AWS Lambda Powertools for structured logging:
```python
logger.info("Matchmaking started", extra={
    'player_id': player_id,
    'ticket_id': ticket_id,
    'config': config_name
})
```

## Alternative Architectures

### Option 1: Long-Polling with WebSockets

Replace HTTP polling with WebSocket connections for real-time updates:
- Use API Gateway WebSocket API
- Push status updates to clients
- Reduce API calls by 90%
- More complex client implementation

### Option 2: Step Functions for Matchmaking

Use AWS Step Functions to orchestrate matchmaking workflow:
- Better visibility into matchmaking state
- Automatic retries
- Built-in error handling
- Higher cost ($0.025 per 1000 state transitions)

### Option 3: Container-based (ECS Fargate)

Deploy as long-running container instead of Lambda:
- Better for WebSocket persistence
- More control over runtime
- Higher baseline cost
- Requires managing scaling

## Testing Strategy

### Unit Tests

```python
# tests/unit/test_gamelift_service.py
import pytest
from moto import mock_gamelift
from services.gamelift_service import GameLiftService

@mock_gamelift
def test_start_matchmaking():
    service = GameLiftService()
    ticket_id = await service.start_matchmaking(
        config_name='Test',
        players=[...]
    )
    assert ticket_id.startswith('ticket-')
```

### Integration Tests

```python
# tests/integration/test_matchmaking_flow.py
import boto3
from testcontainers.localstack import LocalStackContainer

def test_full_matchmaking_flow():
    with LocalStackContainer() as localstack:
        # Test against LocalStack
        client = boto3.client('gamelift', endpoint_url=localstack.get_url())
        # ... full flow test
```

### Load Testing

Use Locust for load testing:
```python
from locust import HttpUser, task

class GameBackendUser(HttpUser):
    @task
    def start_matchmaking(self):
        self.client.post("/matchmaking/start", json={
            "player_count": 1,
            "player_attributes": {"skill": 1500}
        }, headers={"Authorization": f"Bearer {self.jwt}"})
```

## Production Checklist

- [ ] JWT secret stored in Secrets Manager
- [ ] Steam/Epic API keys configured
- [ ] DynamoDB tables created with backups enabled
- [ ] GameLift fleet created and healthy
- [ ] API Gateway custom domain configured
- [ ] CloudWatch alarms configured
- [ ] WAF rules enabled
- [ ] Load testing completed
- [ ] Godot client configured with prod API URL
- [ ] Monitoring dashboard created
- [ ] Incident response runbook documented

---

# Part 3: Manual Configuration Guide

This section provides step-by-step instructions for all manual AWS and third-party service configuration required before deployment.

## Prerequisites

1. **AWS Account** with admin access
2. **AWS CLI** installed and configured
3. **Steam Partner account** (if using Steam auth)
4. **Epic Games Developer account** (if using Epic auth)
5. **Domain name** (optional, for custom API domain)

## Step 1: Register OAuth Providers

### Steam Web API Setup

1. **Get Steam Publisher Account**
   - Go to https://partner.steamgames.com/
   - Sign in with Steam account
   - Complete publisher registration (one-time $100 fee)

2. **Create Steam App**
   - Navigate to "Apps & Packages" → "All Applications"
   - Click "Add New App"
   - Choose "Game"
   - Fill in basic information:
     - App Name: "Jump 'n Thump"
     - Short Name: "jumpnthump"
   - Note the **App ID** (e.g., `480`)

3. **Generate Web API Key**
   - Go to https://steamcommunity.com/dev/apikey
   - Domain Name: Your website domain (e.g., `jumpnthump.com`)
   - Click "Register"
   - Copy the **Web API Key** (64-character hex string)
   - Store securely - you'll need this for Lambda

4. **Configure Steam Ticket Authentication**
   - In Steam Partner: "Technical Tools" → "Edit Steamworks Settings"
   - Enable "Steam Authentication" under "Web API"
   - Save changes

### Epic Games Setup

1. **Register Epic Developer Account**
   - Go to https://dev.epicgames.com/
   - Sign in with Epic Games account
   - Complete developer organization setup

2. **Create Application**
   - Navigate to Developer Portal → "Applications"
   - Click "Create Application"
   - Application Name: "Jump 'n Thump"
   - Choose "Game" as application type

3. **Configure OAuth Client**
   - In application settings: "Product Settings" → "Epic Account Services"
   - Click "Create Client"
   - Client Policy Type: "Public"
   - Note the **Client ID** and **Client Secret**

4. **Add Redirect URIs**
   - In OAuth settings, add redirect URIs:
     - `http://localhost:4433/auth/callback` (dev)
     - `https://yourbackend.execute-api.us-west-2.amazonaws.com/prod/auth/callback` (prod)
   - Enable "OpenID" and "Basic Profile" permissions

5. **Enable Epic Online Services**
   - In Product Settings: "Epic Online Services"
   - Create a deployment for production
   - Note the **Deployment ID** and **Product ID**

### Google OAuth (Optional)

1. **Google Cloud Console**
   - Go to https://console.cloud.google.com/
   - Create new project: "Jump n Thump"

2. **Enable APIs**
   - APIs & Services → Library
   - Enable "Google+ API"

3. **Create OAuth Credentials**
   - APIs & Services → Credentials
   - Create OAuth 2.0 Client ID
   - Application type: "Web application"
   - Authorized redirect URIs: Your API callback URL
   - Note **Client ID** and **Client Secret**

## Step 2: Configure AWS GameLift

### Create GameLift Build

1. **Build Server Artifact**
   ```bash
   # Export Godot server build
   godot --headless --export-release "Linux/X11" build/jumpnthump-server.x86_64

   # Include GameLift SDK
   cp -r gamelift-server-sdk/ build/

   # Create install script
   cat > build/install.sh << 'EOF'
   #!/bin/bash
   chmod +x jumpnthump-server.x86_64
   EOF

   chmod +x build/install.sh
   ```

2. **Upload Build to GameLift**
   ```bash
   aws gamelift upload-build \
     --name "jumpnthump-v1.0.0" \
     --build-version "1.0.0" \
     --build-root ./build/ \
     --operating-system AMAZON_LINUX_2023 \
     --region us-west-2
   ```

   Note the **Build ID** from output (e.g., `build-abc123...`)

### Create GameLift Fleet

1. **Choose Fleet Type**

   **Option A: Managed EC2 Fleet (Production)**
   ```bash
   aws gamelift create-fleet \
     --name "jumpnthump-prod-fleet" \
     --description "Production game servers" \
     --build-id build-abc123... \
     --ec2-instance-type c5.large \
     --fleet-type ON_DEMAND \
     --runtime-configuration "ServerProcesses=[{LaunchPath=/local/game/jumpnthump-server.x86_64,Parameters=--server,ConcurrentExecutions=1}]" \
     --ec2-inbound-permissions "FromPort=4433,ToPort=4433,IpRange=0.0.0.0/0,Protocol=UDP" \
     --region us-west-2
   ```

   **Option B: GameLift Anywhere (Development)**
   ```bash
   # Create compute resource (your local machine)
   aws gamelift create-compute \
     --fleet-id fleet-abc123... \
     --compute-name "dev-laptop" \
     --ip-address "192.168.1.100" \
     --location custom-location-1

   # Register compute
   aws gamelift register-compute \
     --compute-name "dev-laptop" \
     --fleet-id fleet-abc123... \
     --certificate-path ./gamelift-cert.pem
   ```

2. **Configure Scaling**

   For EC2 fleets:
   ```bash
   aws gamelift put-scaling-policy \
     --name "scale-on-capacity" \
     --fleet-id fleet-abc123... \
     --policy-type TargetBased \
     --target-configuration "TargetValue=70.0" \
     --metric-name PercentAvailableGameSessions
   ```

3. **Note Fleet Details**
   - Fleet ID: `fleet-abc123...`
   - Fleet ARN: `arn:aws:gamelift:us-west-2:123456789012:fleet/fleet-abc123...`

### Configure FlexMatch Matchmaking

1. **Create Rule Set**

   Create `matchmaking-ruleset.json`:
   ```json
   {
     "name": "jumpnthump-ffa-4player",
     "ruleLanguageVersion": "1.0",
     "teams": [
       {
         "name": "ffa",
         "maxPlayers": 4,
         "minPlayers": 2
       }
     ],
     "rules": [
       {
         "name": "SkillMatch",
         "description": "Match players with similar skill",
         "type": "distance",
         "measurements": ["skill"],
         "referenceValue": 100,
         "maxDistance": 500
       },
       {
         "name": "RegionLatency",
         "description": "Prefer low-latency regions",
         "type": "latency",
         "maxLatency": 150
       },
       {
         "name": "FastBackfill",
         "description": "Allow matches with 2-4 players",
         "type": "collection",
         "measurements": ["ffa.players.size"],
         "operation": ">=",
         "referenceValue": 2,
         "batchDistance": 1
       }
     ],
     "expansions": [
       {
         "target": "rules[SkillMatch].maxDistance",
         "steps": [
           {"waitTimeSeconds": 10, "value": 500},
           {"waitTimeSeconds": 30, "value": 1000},
           {"waitTimeSeconds": 60, "value": 2000}
         ]
       }
     ]
   }
   ```

2. **Upload Rule Set**
   ```bash
   aws gamelift create-matchmaking-rule-set \
     --name "jumpnthump-ffa-4player" \
     --rule-set-body file://matchmaking-ruleset.json \
     --region us-west-2
   ```

   Note the **Rule Set ARN**

3. **Create Matchmaking Configuration**
   ```bash
   aws gamelift create-matchmaking-configuration \
     --name "jumpnthump-ffa-matchmaker" \
     --description "4-player free-for-all matchmaker" \
     --game-session-queue-arns "arn:aws:gamelift:us-west-2:123456789012:gamesessionqueue/jumpnthump-queue" \
     --request-timeout-seconds 60 \
     --acceptance-timeout-seconds 30 \
     --acceptance-required false \
     --rule-set-name "jumpnthump-ffa-4player" \
     --notification-target "arn:aws:sns:us-west-2:123456789012:gamelift-notifications" \
     --region us-west-2
   ```

   Note the **Configuration ARN** (use in Lambda environment variables)

4. **Create Game Session Queue**
   ```bash
   aws gamelift create-game-session-queue \
     --name "jumpnthump-queue" \
     --destinations "DestinationArn=arn:aws:gamelift:us-west-2:123456789012:fleet/fleet-abc123..." \
     --timeout-in-seconds 600 \
     --player-latency-policies "MaximumIndividualPlayerLatencyMilliseconds=100,PolicyDurationSeconds=60" "MaximumIndividualPlayerLatencyMilliseconds=200" \
     --region us-west-2
   ```

## Step 3: Configure AWS Secrets Manager

Store sensitive credentials securely.

### Create JWT Secret

1. **Generate Secret**
   ```bash
   # Generate 256-bit secret
   JWT_SECRET=$(openssl rand -base64 32)
   echo $JWT_SECRET
   ```

2. **Store in Secrets Manager**
   ```bash
   aws secretsmanager create-secret \
     --name "jumpnthump/jwt-secret" \
     --description "JWT signing secret" \
     --secret-string "$JWT_SECRET" \
     --region us-west-2
   ```

### Store Steam API Key

```bash
aws secretsmanager create-secret \
  --name "jumpnthump/steam-api-key" \
  --description "Steam Web API key" \
  --secret-string "YOUR_STEAM_API_KEY_HERE" \
  --region us-west-2
```

### Store Epic Credentials

```bash
aws secretsmanager create-secret \
  --name "jumpnthump/epic-credentials" \
  --description "Epic Games OAuth credentials" \
  --secret-string '{"client_id":"YOUR_CLIENT_ID","client_secret":"YOUR_CLIENT_SECRET"}' \
  --region us-west-2
```

## Step 4: Configure IAM Roles

### Lambda Execution Role

1. **Create Trust Policy**

   Create `lambda-trust-policy.json`:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Principal": {
           "Service": "lambda.amazonaws.com"
         },
         "Action": "sts:AssumeRole"
       }
     ]
   }
   ```

2. **Create Role**
   ```bash
   aws iam create-role \
     --role-name jumpnthump-lambda-role \
     --assume-role-policy-document file://lambda-trust-policy.json
   ```

3. **Attach Policies**
   ```bash
   # CloudWatch Logs
   aws iam attach-role-policy \
     --role-name jumpnthump-lambda-role \
     --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

   # DynamoDB access
   aws iam attach-role-policy \
     --role-name jumpnthump-lambda-role \
     --policy-arn arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess

   # Secrets Manager
   aws iam attach-role-policy \
     --role-name jumpnthump-lambda-role \
     --policy-arn arn:aws:iam::aws:policy/SecretsManagerReadWrite
   ```

4. **Create GameLift Policy**

   Create `gamelift-policy.json`:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": [
           "gamelift:StartMatchmaking",
           "gamelift:DescribeMatchmaking",
           "gamelift:StopMatchmaking",
           "gamelift:CreatePlayerSession",
           "gamelift:CreatePlayerSessions"
         ],
         "Resource": "*"
       }
     ]
   }
   ```

   ```bash
   aws iam create-policy \
     --policy-name jumpnthump-gamelift-policy \
     --policy-document file://gamelift-policy.json

   aws iam attach-role-policy \
     --role-name jumpnthump-lambda-role \
     --policy-arn arn:aws:iam::123456789012:policy/jumpnthump-gamelift-policy
   ```

## Step 5: Configure Amazon Cognito (Optional)

If using Cognito for user management:

### Create User Pool

1. **Create Pool**
   ```bash
   aws cognito-idp create-user-pool \
     --pool-name "jumpnthump-users" \
     --auto-verified-attributes email \
     --policies "PasswordPolicy={MinimumLength=8,RequireUppercase=true,RequireLowercase=true,RequireNumbers=true}" \
     --schema "Name=email,AttributeDataType=String,Required=true,Mutable=true" \
     --region us-west-2
   ```

   Note the **User Pool ID** (e.g., `us-west-2_abc123`)

2. **Create App Client**
   ```bash
   aws cognito-idp create-user-pool-client \
     --user-pool-id us-west-2_abc123 \
     --client-name "jumpnthump-client" \
     --no-generate-secret \
     --explicit-auth-flows ALLOW_USER_PASSWORD_AUTH ALLOW_REFRESH_TOKEN_AUTH \
     --region us-west-2
   ```

   Note the **Client ID**

3. **Configure Identity Providers**

   Link Steam/Epic as external providers:
   ```bash
   aws cognito-idp create-identity-provider \
     --user-pool-id us-west-2_abc123 \
     --provider-name Steam \
     --provider-type OIDC \
     --provider-details "client_id=YOUR_STEAM_CLIENT_ID,client_secret=YOUR_SECRET,authorize_scopes=openid" \
     --attribute-mapping "username=sub,email=email" \
     --region us-west-2
   ```

## Step 6: Deploy Backend with SAM

### Update SAM Template

1. **Edit `template.yaml`** with your configuration:
   ```yaml
   Parameters:
     JWTSecretArn:
       Type: String
       Default: "arn:aws:secretsmanager:us-west-2:123456789012:secret:jumpnthump/jwt-secret"

     SteamAPIKeyArn:
       Type: String
       Default: "arn:aws:secretsmanager:us-west-2:123456789012:secret:jumpnthump/steam-api-key"

     SteamAppID:
       Type: String
       Default: "480"

     GameLiftFleetID:
       Type: String
       Default: "fleet-abc123..."

     MatchmakingConfigName:
       Type: String
       Default: "jumpnthump-ffa-matchmaker"
   ```

2. **Build and Deploy**
   ```bash
   sam build
   sam deploy \
     --stack-name jumpnthump-backend \
     --region us-west-2 \
     --capabilities CAPABILITY_IAM \
     --parameter-overrides \
       SteamAppID=480 \
       GameLiftFleetID=fleet-abc123...
   ```

3. **Note API Gateway URL**
   ```
   CloudFormation outputs:
   ApiEndpoint = https://abc123def.execute-api.us-west-2.amazonaws.com/prod
   ```

## Step 7: Configure Custom Domain (Optional)

### Request SSL Certificate

1. **AWS Certificate Manager**
   ```bash
   aws acm request-certificate \
     --domain-name api.jumpnthump.com \
     --validation-method DNS \
     --region us-west-2
   ```

2. **Validate Certificate**
   - Go to ACM console
   - Click certificate
   - Copy CNAME record
   - Add to your DNS provider (Route 53, Cloudflare, etc.)
   - Wait for validation (5-30 minutes)

### Create Custom Domain

1. **API Gateway Custom Domain**
   ```bash
   aws apigatewayv2 create-domain-name \
     --domain-name api.jumpnthump.com \
     --domain-name-configurations "CertificateArn=arn:aws:acm:us-west-2:123456789012:certificate/abc123..." \
     --region us-west-2
   ```

2. **Create API Mapping**
   ```bash
   aws apigatewayv2 create-api-mapping \
     --domain-name api.jumpnthump.com \
     --api-id abc123def \
     --stage prod \
     --region us-west-2
   ```

3. **Update DNS**
   - Create CNAME record:
     - Name: `api.jumpnthump.com`
     - Value: `d-abc123.execute-api.us-west-2.amazonaws.com`

## Step 8: Configure CloudWatch Monitoring

### Create SNS Topic for Alerts

```bash
aws sns create-topic \
  --name jumpnthump-alerts \
  --region us-west-2

aws sns subscribe \
  --topic-arn arn:aws:sns:us-west-2:123456789012:jumpnthump-alerts \
  --protocol email \
  --notification-endpoint your-email@example.com
```

### Create CloudWatch Alarms

**Lambda Error Alarm:**
```bash
aws cloudwatch put-metric-alarm \
  --alarm-name jumpnthump-lambda-errors \
  --alarm-description "Alert on Lambda errors" \
  --metric-name Errors \
  --namespace AWS/Lambda \
  --statistic Sum \
  --period 300 \
  --evaluation-periods 1 \
  --threshold 10 \
  --comparison-operator GreaterThanThreshold \
  --alarm-actions arn:aws:sns:us-west-2:123456789012:jumpnthump-alerts \
  --dimensions Name=FunctionName,Value=StartMatchmakingFunction
```

**API Gateway 5xx Alarm:**
```bash
aws cloudwatch put-metric-alarm \
  --alarm-name jumpnthump-api-errors \
  --alarm-description "Alert on API 5xx errors" \
  --metric-name 5XXError \
  --namespace AWS/ApiGateway \
  --statistic Sum \
  --period 300 \
  --evaluation-periods 1 \
  --threshold 50 \
  --comparison-operator GreaterThanThreshold \
  --alarm-actions arn:aws:sns:us-west-2:123456789012:jumpnthump-alerts
```

**GameLift Fleet Capacity Alarm:**
```bash
aws cloudwatch put-metric-alarm \
  --alarm-name jumpnthump-fleet-capacity \
  --alarm-description "Alert on low fleet capacity" \
  --metric-name PercentAvailableGameSessions \
  --namespace AWS/GameLift \
  --statistic Average \
  --period 300 \
  --evaluation-periods 2 \
  --threshold 20 \
  --comparison-operator LessThanThreshold \
  --alarm-actions arn:aws:sns:us-west-2:123456789012:jumpnthump-alerts \
  --dimensions Name=FleetId,Value=fleet-abc123...
```

### Create CloudWatch Dashboard

```bash
aws cloudwatch put-dashboard \
  --dashboard-name jumpnthump-production \
  --dashboard-body file://dashboard-config.json
```

**dashboard-config.json:**
```json
{
  "widgets": [
    {
      "type": "metric",
      "properties": {
        "metrics": [
          ["AWS/Lambda", "Invocations", {"stat": "Sum"}],
          [".", "Errors", {"stat": "Sum"}],
          [".", "Duration", {"stat": "Average"}]
        ],
        "period": 300,
        "stat": "Average",
        "region": "us-west-2",
        "title": "Lambda Metrics"
      }
    },
    {
      "type": "metric",
      "properties": {
        "metrics": [
          ["AWS/GameLift", "ActiveInstances"],
          [".", "PercentAvailableGameSessions"],
          [".", "CurrentPlayerSessions"]
        ],
        "period": 300,
        "stat": "Average",
        "region": "us-west-2",
        "title": "GameLift Fleet Health"
      }
    }
  ]
}
```

## Step 9: Enable AWS WAF (Optional)

Protect API Gateway from attacks:

1. **Create Web ACL**
   ```bash
   aws wafv2 create-web-acl \
     --name jumpnthump-api-protection \
     --scope REGIONAL \
     --default-action Allow={} \
     --rules file://waf-rules.json \
     --region us-west-2
   ```

2. **Rate Limiting Rule** (`waf-rules.json`):
   ```json
   [
     {
       "Name": "RateLimitRule",
       "Priority": 1,
       "Statement": {
         "RateBasedStatement": {
           "Limit": 2000,
           "AggregateKeyType": "IP"
         }
       },
       "Action": {
         "Block": {}
       },
       "VisibilityConfig": {
         "SampledRequestsEnabled": true,
         "CloudWatchMetricsEnabled": true,
         "MetricName": "RateLimitRule"
       }
     }
   ]
   ```

3. **Associate with API Gateway**
   ```bash
   aws wafv2 associate-web-acl \
     --web-acl-arn arn:aws:wafv2:us-west-2:123456789012:regional/webacl/jumpnthump-api-protection/abc123 \
     --resource-arn arn:aws:apigateway:us-west-2::/restapis/abc123def/stages/prod
   ```

## Step 10: Configure Godot Client

### Update Settings

Edit `settings.tres`:
```gdscript
[resource]
gamelift_backend_api_url = "https://api.jumpnthump.com"  # Or API Gateway URL
gamelift_matchmaking_timeout_sec = 120.0
use_gamelift = true
```

### Store Auth Tokens Locally

For Steam integration in Godot, use Godot Steam plugin:
```gdscript
# In your auth script
var steam_ticket = Steam.getAuthSessionTicket()
# Send to backend for validation
```

## Step 11: Test End-to-End

### Verification Checklist

1. **Test Authentication**
   ```bash
   curl -X POST https://api.jumpnthump.com/auth/login \
     -H "Content-Type: application/json" \
     -d '{"provider":"steam","auth_code":"test123"}'
   ```

2. **Test Matchmaking**
   ```bash
   curl -X POST https://api.jumpnthump.com/matchmaking/start \
     -H "Authorization: Bearer YOUR_JWT" \
     -H "Content-Type: application/json" \
     -d '{"player_count":1,"matchmaking_config":"jumpnthump-ffa-matchmaker"}'
   ```

3. **Test Godot Client**
   - Launch with `--preview` mode first
   - Verify debug session IDs work
   - Switch to production mode
   - Verify real GameLift connection

4. **Monitor CloudWatch**
   - Check Lambda logs for errors
   - Verify GameLift fleet shows active instances
   - Check API Gateway metrics

## Configuration Summary

After completing all steps, you should have:

| Component | Configuration Value | Location |
|-----------|---------------------|----------|
| Steam API Key | `ABC123...` | Secrets Manager |
| Steam App ID | `480` | SAM template parameter |
| Epic Client ID | `xyz...` | Secrets Manager |
| GameLift Fleet ID | `fleet-abc123...` | SAM template |
| Matchmaking Config | `jumpnthump-ffa-matchmaker` | SAM template |
| API Gateway URL | `https://abc.execute-api...` | CloudFormation outputs |
| Custom Domain | `https://api.jumpnthump.com` | Route 53 CNAME |
| JWT Secret ARN | `arn:aws:secretsmanager:...` | Secrets Manager |
| Lambda Role ARN | `arn:aws:iam:...` | IAM Console |
| User Pool ID | `us-west-2_abc123` | Cognito (optional) |

## Troubleshooting Common Issues

### Issue: GameLift Fleet Not Starting

**Solution:**
```bash
# Check fleet status
aws gamelift describe-fleet-attributes --fleet-ids fleet-abc123...

# Check fleet events
aws gamelift describe-fleet-events --fleet-id fleet-abc123... --limit 10

# Verify build uploaded correctly
aws gamelift describe-build --build-id build-abc123...
```

### Issue: Lambda Can't Access Secrets

**Solution:**
```bash
# Verify IAM role has SecretsManager permissions
aws iam get-role-policy --role-name jumpnthump-lambda-role

# Test secret retrieval manually
aws secretsmanager get-secret-value --secret-id jumpnthump/jwt-secret
```

### Issue: Matchmaking Times Out

**Solution:**
- Lower player requirements in rule set (minPlayers: 2 instead of 4)
- Increase expansion steps for skill range
- Check fleet has available capacity
- Verify game session queue points to correct fleet

### Issue: CORS Errors

**Solution:**
Update API Gateway CORS:
```bash
aws apigateway update-rest-api \
  --rest-api-id abc123def \
  --patch-operations \
    op=add,path=/*/OPTIONS,value='{"consumes":["application/json"],"produces":["application/json"],"responses":{"200":{"headers":{"Access-Control-Allow-Origin":"*"}}}}'
```

## Estimated Setup Time

- **OAuth Provider Registration:** 1-2 hours
- **GameLift Configuration:** 2-3 hours
- **AWS IAM & Secrets:** 30 minutes
- **Backend Deployment:** 30 minutes
- **Custom Domain & SSL:** 1 hour (plus DNS propagation)
- **Monitoring Setup:** 1 hour
- **Testing:** 2-3 hours

**Total:** 8-12 hours for complete production setup
