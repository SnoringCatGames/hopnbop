# Jump 'n Thump Backend Service

Python-based backend service for GameLift matchmaking and player authentication.

## Architecture

- **Runtime:** AWS Lambda (Python 3.12)
- **API:** API Gateway (REST API)
- **Auth:** JWT tokens with OAuth2 providers (Steam, Epic, Cognito)
- **Database:** DynamoDB (players, match history)
- **GameLift:** boto3 client for FlexMatch matchmaking

## Project Structure

```
backend/
├── src/
│   ├── handlers/          # Lambda function handlers
│   │   ├── auth_handler.py
│   │   └── matchmaking_handler.py
│   ├── services/          # Business logic
│   │   ├── auth_service.py
│   │   ├── gamelift_service.py
│   │   ├── player_service.py
│   │   └── rate_limiter.py
│   ├── models/            # Data models
│   └── utils/             # Utilities
├── tests/
│   ├── unit/
│   └── integration/
├── template.yaml          # AWS SAM template
├── requirements.txt       # Python dependencies
└── README.md
```

## API Endpoints

### Authentication

**POST /auth/login**
```json
Request:
{
  "provider": "steam",
  "auth_code": "abc123..."
}

Response:
{
  "status": "success",
  "jwt_token": "eyJhbGc...",
  "player_id": "steam_76561198012345678",
  "display_name": "PlayerName",
  "rating": 1500,
  "expires_at": 1735689600
}
```

### Matchmaking

**POST /matchmaking/join** (Simplified - blocks until match found)
```json
Request:
{
  "player_count": 2,
  "client_id": "unique_client_id"
}

Response:
{
  "status": "success",
  "game_session_id": "gamesession-xyz789",
  "server_ip": "54.123.45.67",
  "server_port": 4433,
  "player_session_ids": [
    "psess-111111-1111-1111-1111-111111111111",
    "psess-222222-2222-2222-2222-222222222222"
  ]
}
```

**POST /matchmaking/start** (Returns ticket for polling)
```json
Request:
{
  "player_count": 1
}

Response:
{
  "status": "success",
  "ticket_id": "ticket-abc123",
  "estimated_wait_ms": 5000
}
```

**GET /matchmaking/status/{ticket_id}**
```json
Response (in progress):
{
  "status": "searching",
  "ticket_id": "ticket-abc123",
  "estimated_wait_ms": 3000
}

Response (complete):
{
  "status": "success",
  "game_session_id": "gamesession-xyz789",
  "server_ip": "54.123.45.67",
  "server_port": 4433,
  "player_session_ids": ["psess-...", "psess-..."]
}
```

## Local Development

### Prerequisites

1. Python 3.12+
2. AWS CLI configured
3. AWS SAM CLI installed

### Setup

```bash
# Install dependencies
pip install -r requirements.txt

# Install dev dependencies
pip install pytest pytest-asyncio moto

# Run tests
pytest tests/
```

### Local Testing with SAM

```bash
# Start local API
sam local start-api

# Invoke function directly
sam local invoke JoinMatchmakingFunction -e events/join.json
```

## Deployment

### First-Time Deployment

1. **Generate JWT Secret**
```bash
openssl rand -base64 32
```

2. **Deploy with SAM**
```bash
# Build
sam build

# Deploy (guided first time)
sam deploy --guided
```

Parameters to provide:
- `JWTSecret`: Your generated secret
- `SteamAPIKey`: Steam Web API key (optional)
- `SteamAppID`: Steam App ID (optional)
- `MatchmakingConfigName`: GameLift matchmaking config name

3. **Note API Endpoint**
```
Outputs:
ApiEndpoint = https://abc123.execute-api.us-west-2.amazonaws.com/prod
```

4. **Update Godot Settings**

Edit `settings.tres`:
```
gamelift_backend_api_url = "https://abc123.execute-api.us-west-2.amazonaws.com/prod"
```

### Update Existing Deployment

```bash
sam build && sam deploy
```

## Configuration

### Environment Variables

Set in `template.yaml`:
- `JWT_SECRET`: Secret for signing JWT tokens
- `STEAM_API_KEY`: Steam Web API key
- `STEAM_APP_ID`: Steam application ID
- `MATCHMAKING_CONFIG`: GameLift matchmaking configuration name
- `PLAYERS_TABLE`: DynamoDB players table name
- `MATCH_HISTORY_TABLE`: DynamoDB match history table name

### Preview Mode

For local testing without backend, the client generates debug session IDs automatically when `should_connect_to_remote_server = false` and running in Godot editor.

The backend also accepts `DEBUG_` prefixed tokens for testing.

## GameLift Configuration

Before deploying, you must:

1. **Create GameLift Fleet**
   - Build and upload game server build
   - Create fleet with server executable

2. **Create Matchmaking Configuration**
   - Define FlexMatch rule set
   - Create matchmaking configuration
   - Create game session queue

3. **Note Configuration Names**
   - Set `MatchmakingConfigName` parameter in deployment

See `../GAMELIFT_INTEGRATION_PLAN.md` Part 3 for detailed setup instructions.

## Authentication Providers

### Steam

1. Register Steam Partner account
2. Create Steam App
3. Generate Web API key at https://steamcommunity.com/dev/apikey
4. Set `STEAM_API_KEY` and `STEAM_APP_ID` in deployment parameters

### Epic Games

1. Register Epic Developer account
2. Create application in Developer Portal
3. Configure OAuth client
4. Add redirect URIs

### AWS Cognito

1. Create Cognito User Pool
2. Create App Client
3. Configure identity providers
4. Use Cognito JWT tokens directly

## Security

### Rate Limiting

- Matchmaking: 5 requests per minute per player
- Auth: 10 requests per hour per IP (recommended to add)

### Token Validation

- All protected endpoints require `Authorization: Bearer <jwt>` header
- JWTs expire after 24 hours (configurable)
- Server validates token signature

### Recommendations

- Enable AWS WAF on API Gateway
- Use HTTPS only (enforced by API Gateway)
- Rotate JWT secret regularly
- Store secrets in AWS Secrets Manager
- Enable CloudWatch logging

## Monitoring

### CloudWatch Metrics

Monitor:
- Lambda invocation count and errors
- Lambda duration
- API Gateway 4xx/5xx responses
- DynamoDB throttling

### CloudWatch Logs

Structured logging with AWS Lambda Powertools:
```python
logger.info("Matchmaking started", extra={
    "player_id": player_id,
    "ticket_id": ticket_id
})
```

### Alarms

Set up alarms for:
- Lambda errors > 10 in 5 minutes
- API Gateway 5xx > 50 in 5 minutes
- Matchmaking timeout rate > 20%

## Cost Estimates

Monthly costs for 1000 active players:

| Service | Usage | Cost |
|---------|-------|------|
| Lambda | 100K invocations, 2s avg | ~$1.00 |
| API Gateway | 100K requests | ~$0.35 |
| DynamoDB | 10MB storage, 100K R/W | ~$1.25 |
| **Total Backend** | | **~$2.60/month** |

*Note: GameLift server costs are separate (~$700/month for 10 c5.large instances)*

## Testing

### Unit Tests

```bash
pytest tests/unit/
```

### Integration Tests

Requires AWS credentials:
```bash
pytest tests/integration/
```

### Load Testing

Use Locust or similar:
```python
from locust import HttpUser, task

class BackendUser(HttpUser):
    @task
    def join_matchmaking(self):
        self.client.post("/matchmaking/join", json={
            "player_count": 1
        }, headers={"Authorization": f"Bearer {self.jwt}"})
```

## Troubleshooting

### Lambda Timeout

If matchmaking times out:
- Check GameLift fleet has available capacity
- Verify matchmaking rule set isn't too restrictive
- Increase Lambda timeout in `template.yaml`

### Authentication Failed

- Verify OAuth provider credentials are correct
- Check JWT secret matches between deployment and requests
- Ensure token hasn't expired

### GameLift Errors

- Check IAM role has GameLift permissions
- Verify matchmaking configuration name is correct
- Check CloudWatch logs for detailed error messages

## Additional Resources

- [AWS SAM Documentation](https://docs.aws.amazon.com/serverless-application-model/)
- [GameLift FlexMatch Guide](https://docs.aws.amazon.com/gamelift/latest/flexmatchguide/)
- [AWS Lambda Powertools](https://docs.powertools.aws.dev/lambda/python/)
- Full integration plan: `../GAMELIFT_INTEGRATION_PLAN.md`
