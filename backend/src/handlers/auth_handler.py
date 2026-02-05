"""Lambda handlers for authentication operations."""

import json
import os
import asyncio
from typing import Dict, Any
from aws_lambda_powertools import Logger, Tracer
from aws_lambda_powertools.utilities.typing import LambdaContext

import sys

sys.path.append(os.path.join(os.path.dirname(__file__), ".."))

from services.auth_service import AuthService
from services.player_service import PlayerService

logger = Logger()
tracer = Tracer()

# Initialize services.
auth_service = AuthService(
    jwt_secret=os.environ.get("JWT_SECRET", ""),
    token_lifetime_hours=24,
)
player_service = PlayerService()


@tracer.capture_lambda_handler
@logger.inject_lambda_context
def login(event: Dict[str, Any], context: LambdaContext) -> Dict:
    """
    POST /auth/login
    Authenticate user with OAuth provider.
    """
    try:
        # Parse request body.
        body = json.loads(event.get("body", "{}"))
        provider = body.get("provider", "")
        auth_code = body.get("auth_code", "")

        if not provider or not auth_code:
            return error_response(
                400,
                "MISSING_PARAMS",
                "Missing provider or auth_code",
            )

        # Authenticate with provider.
        if provider == "steam":
            auth_token = asyncio.run(auth_service.authenticate_steam(auth_code))
        elif provider == "epic":
            auth_token = asyncio.run(auth_service.authenticate_epic(auth_code))
        elif provider == "cognito":
            auth_token = asyncio.run(auth_service.authenticate_cognito(auth_code))
        else:
            return error_response(
                400,
                "INVALID_PROVIDER",
                f"Unsupported provider: {provider}",
            )

        # Get or create player profile.
        player_profile = asyncio.run(
            player_service.get_or_create_player(
                auth_token.player_id,
                auth_token.display_name,
                auth_token.provider,
            )
        )

        # Issue JWT.
        jwt_token = auth_token.to_jwt(auth_service.jwt_secret)

        logger.info(f"User authenticated: {auth_token.player_id} " f"via {provider}")

        return {
            "statusCode": 200,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps(
                {
                    "status": "success",
                    "jwt_token": jwt_token,
                    "player_id": auth_token.player_id,
                    "display_name": auth_token.display_name,
                    "rating": player_profile.rating,
                    "expires_at": int(auth_token.expires_at.timestamp()),
                }
            ),
        }

    except ValueError as e:
        logger.error(f"Authentication failed: {e}")
        return error_response(401, "AUTH_FAILED", str(e))
    except Exception as e:
        logger.exception("Login error")
        return error_response(500, "INTERNAL_ERROR", "Internal server error")


def error_response(status_code: int, error_code: str, message: str) -> Dict:
    """Format error response."""
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(
            {
                "status": "error",
                "error_code": error_code,
                "message": message,
            }
        ),
    }
