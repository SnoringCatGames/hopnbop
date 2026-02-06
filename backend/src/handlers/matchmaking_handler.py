"""Lambda handlers for matchmaking operations."""

import json
import os
import asyncio
from typing import Dict, Any
from aws_lambda_powertools import Logger, Tracer
from aws_lambda_powertools.utilities.typing import LambdaContext

import sys

sys.path.append(os.path.join(os.path.dirname(__file__), ".."))

from services.gamelift_service import (
    GameLiftService,
    MatchmakingPlayer,
)
from services.auth_service import AuthService, AuthToken
from services.player_service import PlayerService
from services.rate_limiter import RateLimiter
from services.level_selection_service import (
    parse_level_preference,
    select_level_for_match,
)

logger = Logger()
tracer = Tracer()

# Initialize services (cached across invocations).
gamelift = GameLiftService(
    region=os.environ.get("AWS_REGION", "us-west-2"),
    poll_interval_sec=1.0,
    max_poll_time_sec=120.0,
)
player_service = PlayerService()
rate_limiter = RateLimiter()


@tracer.capture_lambda_handler
@logger.inject_lambda_context
def join_matchmaking(event: Dict[str, Any], context: LambdaContext) -> Dict:
    """
    POST /matchmaking/join
    Simplified endpoint that starts matchmaking and polls until complete.
    """
    try:
        # Extract JWT from Authorization header.
        auth_header = event.get("headers", {}).get("Authorization", "")
        if not auth_header.startswith("Bearer "):
            return error_response(401, "MISSING_AUTH", "Missing authorization")

        jwt_token = auth_header[7:]
        jwt_secret = os.environ.get("JWT_SECRET", "")

        # For preview mode, accept debug tokens.
        if jwt_token.startswith("DEBUG_"):
            auth_token = AuthToken(
                player_id=jwt_token,
                display_name=f"Player_{jwt_token[-4:]}",
                provider="debug",
                issued_at=None,
                expires_at=None,
            )
        else:
            auth_token = AuthToken.from_jwt(jwt_token, jwt_secret)

        player_id = auth_token.player_id

        # Rate limiting.
        if not rate_limiter.check_limit(player_id, "matchmaking", max_per_min=5):
            return error_response(
                429, "RATE_LIMIT", "Too many requests", retry_after=60
            )

        # Parse request body.
        body = json.loads(event.get("body", "{}"))
        player_count = body.get("player_count", 1)
        client_id = body.get("client_id", "unknown")
        level_prefs_data = body.get("level_preferences", {})

        # Validate input.
        if player_count < 1 or player_count > 4:
            return error_response(400, "INVALID_INPUT", "player_count must be 1-4")

        # Parse level preferences.
        level_prefs = parse_level_preference(level_prefs_data)

        logger.info(
            f"Matchmaking request from {player_id}: "
            f"{player_count} player(s), client {client_id}, "
            f"level prefs: {level_prefs_data}"
        )

        # Get or create player profile.
        player_profile = asyncio.run(
            player_service.get_or_create_player(
                player_id,
                auth_token.display_name,
                auth_token.provider,
            )
        )

        # Create matchmaking players (one per local player).
        players = [
            MatchmakingPlayer(
                player_id=f"{player_id}_{i}",
                skill_rating=player_profile.rating,
                region="us-west-2",
                latency_map={"us-west-2": 50},
            )
            for i in range(player_count)
        ]

        # Start matchmaking.
        config_name = os.environ.get("MATCHMAKING_CONFIG", "jumpnthump-ffa-matchmaker")
        ticket_id = asyncio.run(
            gamelift.start_matchmaking(config_name=config_name, players=players)
        )

        logger.info(f"Started matchmaking: {ticket_id}")

        # Poll until complete (blocking call).
        try:
            result = asyncio.run(gamelift.poll_matchmaking(ticket_id))

            logger.info(f"Matchmaking complete: {result.game_session_id}")

            # Select level based on player preferences.
            # In a full implementation, we would aggregate preferences from
            # all players in the match. For now, use this player's prefs.
            selected_level_id = select_level_for_match([level_prefs])
            logger.info(f"Selected level: {selected_level_id}")

            return {
                "statusCode": 200,
                "headers": {"Content-Type": "application/json"},
                "body": json.dumps(
                    {
                        "status": "success",
                        "server_version": os.environ.get("GAME_VERSION", "0.1.0"),
                        "game_session_id": result.game_session_id,
                        "server_ip": result.server_ip,
                        "server_port": result.server_port,
                        "player_session_ids": result.player_session_ids,
                        "selected_level_id": selected_level_id,
                    }
                ),
            }

        except TimeoutError as e:
            logger.warning(f"Matchmaking timeout: {ticket_id}")
            return error_response(408, "MATCHMAKING_TIMEOUT", str(e))

    except ValueError as e:
        logger.error(f"Validation error: {e}")
        return error_response(400, "VALIDATION_ERROR", str(e))
    except Exception as e:
        logger.exception("Matchmaking error")
        return error_response(500, "INTERNAL_ERROR", "Internal server error")


@tracer.capture_lambda_handler
@logger.inject_lambda_context
def start_matchmaking(event: Dict[str, Any], context: LambdaContext) -> Dict:
    """
    POST /matchmaking/start
    Start matchmaking and return ticket ID for polling.
    """
    try:
        # Extract JWT.
        auth_header = event.get("headers", {}).get("Authorization", "")
        if not auth_header.startswith("Bearer "):
            return error_response(401, "MISSING_AUTH", "Missing authorization")

        jwt_token = auth_header[7:]
        jwt_secret = os.environ.get("JWT_SECRET", "")

        # For preview mode, accept debug tokens.
        if jwt_token.startswith("DEBUG_"):
            auth_token = AuthToken(
                player_id=jwt_token,
                display_name=f"Player_{jwt_token[-4:]}",
                provider="debug",
                issued_at=None,
                expires_at=None,
            )
        else:
            auth_token = AuthToken.from_jwt(jwt_token, jwt_secret)

        player_id = auth_token.player_id

        # Rate limiting.
        if not rate_limiter.check_limit(player_id, "matchmaking", max_per_min=5):
            return error_response(
                429, "RATE_LIMIT", "Too many requests", retry_after=60
            )

        # Parse request body.
        body = json.loads(event.get("body", "{}"))
        player_count = body.get("player_count", 1)

        # Validate input.
        if player_count < 1 or player_count > 4:
            return error_response(400, "INVALID_INPUT", "player_count must be 1-4")

        # Get player profile.
        player_profile = asyncio.run(
            player_service.get_or_create_player(
                player_id,
                auth_token.display_name,
                auth_token.provider,
            )
        )

        # Create matchmaking players.
        players = [
            MatchmakingPlayer(
                player_id=f"{player_id}_{i}",
                skill_rating=player_profile.rating,
                region="us-west-2",
                latency_map={"us-west-2": 50},
            )
            for i in range(player_count)
        ]

        # Start matchmaking.
        config_name = os.environ.get("MATCHMAKING_CONFIG", "jumpnthump-ffa-matchmaker")
        ticket_id = asyncio.run(
            gamelift.start_matchmaking(config_name=config_name, players=players)
        )

        logger.info(f"Started matchmaking for {player_id}: {ticket_id}")

        return {
            "statusCode": 200,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps(
                {
                    "status": "success",
                    "ticket_id": ticket_id,
                    "estimated_wait_ms": 5000,
                }
            ),
        }

    except ValueError as e:
        return error_response(400, "VALIDATION_ERROR", str(e))
    except Exception as e:
        logger.exception("Matchmaking error")
        return error_response(500, "INTERNAL_ERROR", "Internal server error")


@tracer.capture_lambda_handler
@logger.inject_lambda_context
def get_matchmaking_status(event: Dict[str, Any], context: LambdaContext) -> Dict:
    """
    GET /matchmaking/status/{ticket_id}
    Poll matchmaking ticket status.
    """
    try:
        # Auth.
        auth_header = event.get("headers", {}).get("Authorization", "")
        jwt_token = auth_header[7:]
        jwt_secret = os.environ.get("JWT_SECRET", "")

        # Accept debug tokens.
        if not jwt_token.startswith("DEBUG_"):
            AuthToken.from_jwt(jwt_token, jwt_secret)

        # Get ticket ID from path.
        ticket_id = event.get("pathParameters", {}).get("ticket_id")
        if not ticket_id:
            return error_response(400, "MISSING_TICKET", "Missing ticket_id")

        # Try non-blocking status check first.
        status = asyncio.run(gamelift.get_ticket_status(ticket_id))

        # If still in progress, return current status.
        if status["status"] in ["queued", "searching", "placing"]:
            return {
                "statusCode": 200,
                "headers": {"Content-Type": "application/json"},
                "body": json.dumps(status),
            }

        # If completed, do full poll to get connection info.
        if status["status"] == "completed":
            result = asyncio.run(gamelift.poll_matchmaking(ticket_id))

            return {
                "statusCode": 200,
                "headers": {"Content-Type": "application/json"},
                "body": json.dumps(
                    {
                        "status": "success",
                        "ticket_id": ticket_id,
                        "game_session_id": result.game_session_id,
                        "server_ip": result.server_ip,
                        "server_port": result.server_port,
                        "player_session_ids": result.player_session_ids,
                    }
                ),
            }

        # Failed/cancelled/timeout.
        return {
            "statusCode": 200,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps(
                {
                    "status": "failed",
                    "error_code": status["status"].upper(),
                    "message": f"Matchmaking {status['status']}",
                }
            ),
        }

    except ValueError as e:
        return error_response(400, "VALIDATION_ERROR", str(e))
    except Exception as e:
        logger.exception("Status check error")
        return error_response(500, "INTERNAL_ERROR", "Internal server error")


def error_response(
    status_code: int,
    error_code: str,
    message: str,
    retry_after: int = None,
) -> Dict:
    """Format error response."""
    body = {
        "status": "error",
        "error_code": error_code,
        "message": message,
    }

    headers = {"Content-Type": "application/json"}
    if retry_after:
        headers["Retry-After"] = str(retry_after)

    return {
        "statusCode": status_code,
        "headers": headers,
        "body": json.dumps(body),
    }
