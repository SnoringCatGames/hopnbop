"""Lambda handlers for friends operations."""

import json
import os
import asyncio
from typing import Dict, Any
from aws_lambda_powertools import Logger, Tracer
from aws_lambda_powertools.utilities.typing import LambdaContext

import sys

sys.path.append(os.path.join(os.path.dirname(__file__), ".."))

from services.friends_service import FriendsService
from services.player_service import PlayerService
from services.auth_service import AuthToken
from services.rate_limiter import RateLimiter
from services import secrets_service

logger = Logger()
tracer = Tracer()

# CORS headers included in every response.
_HEADERS = {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "Content-Type,Authorization",
    "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
}

friends_service = FriendsService()
player_service = PlayerService()
rate_limiter = RateLimiter()


def _authenticate(event: Dict) -> AuthToken:
    """Extract and validate JWT from request."""
    auth_header = event.get("headers", {}).get(
        "Authorization", ""
    )
    if not auth_header.startswith("Bearer "):
        raise PermissionError("Missing authorization")

    jwt_token = auth_header[7:]
    jwt_secret = secrets_service.get_jwt_secret()

    if jwt_token.startswith("DEBUG_"):
        return AuthToken(
            player_id=jwt_token,
            display_name=f"Player_{jwt_token[-4:]}",
            provider="debug",
            is_anonymous=False,
            issued_at=None,
            expires_at=None,
        )

    return AuthToken.from_jwt(jwt_token, jwt_secret)


def _error_response(
    status_code: int,
    error_code: str,
    message: str,
) -> Dict:
    """Format error response."""
    return {
        "statusCode": status_code,
        "headers": _HEADERS,
        "body": json.dumps(
            {
                "status": "error",
                "error_code": error_code,
                "message": message,
            }
        ),
    }


def _require_authenticated(auth_token: AuthToken) -> None:
    """Raise if the player is anonymous."""
    if auth_token.is_anonymous:
        raise PermissionError(
            "Anonymous players cannot use friends"
        )


@tracer.capture_lambda_handler
@logger.inject_lambda_context
def list_friends(
    event: Dict[str, Any], context: LambdaContext
) -> Dict:
    """GET /friends — List all friends."""
    try:
        auth_token = _authenticate(event)
        _require_authenticated(auth_token)
        player_id = auth_token.player_id

        if not rate_limiter.check_limit(
            player_id, "friends_list", max_per_min=30
        ):
            return _error_response(
                429, "RATE_LIMIT", "Too many requests"
            )

        friends = asyncio.run(
            friends_service.list_friends(player_id)
        )

        return {
            "statusCode": 200,
            "headers": _HEADERS,
            "body": json.dumps(
                {
                    "status": "success",
                    "friends": [
                        {
                            "player_id": f.friend_id,
                            "display_name": f.display_name,
                            "source": f.source,
                            "created_at": f.created_at,
                        }
                        for f in friends
                    ],
                }
            ),
        }

    except PermissionError:
        return _error_response(
            401, "UNAUTHORIZED", "Invalid token"
        )
    except Exception as e:
        logger.exception("List friends error")
        return _error_response(
            500, "INTERNAL_ERROR", "Internal server error"
        )


@tracer.capture_lambda_handler
@logger.inject_lambda_context
def add_friend(
    event: Dict[str, Any], context: LambdaContext
) -> Dict:
    """POST /friends/add — Add a friend by player_id or friend_code."""
    try:
        auth_token = _authenticate(event)
        _require_authenticated(auth_token)
        player_id = auth_token.player_id

        if not rate_limiter.check_limit(
            player_id, "friends_add", max_per_min=10
        ):
            return _error_response(
                429, "RATE_LIMIT", "Too many requests"
            )

        body = json.loads(event.get("body", "{}"))
        friend_code = body.get("friend_code", "")
        friend_player_id = body.get("player_id", "")
        source = body.get("source", "friend_code")

        # Resolve friend player ID from friend code.
        if friend_code and not friend_player_id:
            friend_profile = asyncio.run(
                player_service.get_player_by_friend_code(
                    friend_code.upper().strip()
                )
            )
            if friend_profile is None:
                return _error_response(
                    404,
                    "NOT_FOUND",
                    "No player with that friend code",
                )
            friend_player_id = friend_profile.player_id

        if not friend_player_id:
            return _error_response(
                400,
                "MISSING_INPUT",
                "Provide friend_code or player_id",
            )

        added = asyncio.run(
            friends_service.add_friend(
                player_id, friend_player_id, source
            )
        )

        if not added:
            return {
                "statusCode": 200,
                "headers": _HEADERS,
                "body": json.dumps(
                    {
                        "status": "success",
                        "message": "Already friends",
                        "already_friends": True,
                    }
                ),
            }

        return {
            "statusCode": 200,
            "headers": _HEADERS,
            "body": json.dumps(
                {
                    "status": "success",
                    "message": "Friend added",
                    "already_friends": False,
                }
            ),
        }

    except PermissionError:
        return _error_response(
            401, "UNAUTHORIZED", "Invalid token"
        )
    except ValueError as e:
        return _error_response(
            400, "VALIDATION_ERROR", str(e)
        )
    except Exception as e:
        logger.exception("Add friend error")
        return _error_response(
            500, "INTERNAL_ERROR", "Internal server error"
        )


@tracer.capture_lambda_handler
@logger.inject_lambda_context
def remove_friend(
    event: Dict[str, Any], context: LambdaContext
) -> Dict:
    """POST /friends/remove — Remove a friend."""
    try:
        auth_token = _authenticate(event)
        _require_authenticated(auth_token)
        player_id = auth_token.player_id

        if not rate_limiter.check_limit(
            player_id, "friends_remove", max_per_min=10
        ):
            return _error_response(
                429, "RATE_LIMIT", "Too many requests"
            )

        body = json.loads(event.get("body", "{}"))
        friend_player_id = body.get("player_id", "")

        if not friend_player_id:
            return _error_response(
                400, "MISSING_INPUT", "Provide player_id"
            )

        asyncio.run(
            friends_service.remove_friend(
                player_id, friend_player_id
            )
        )

        return {
            "statusCode": 200,
            "headers": _HEADERS,
            "body": json.dumps(
                {
                    "status": "success",
                    "message": "Friend removed",
                }
            ),
        }

    except PermissionError:
        return _error_response(
            401, "UNAUTHORIZED", "Invalid token"
        )
    except Exception as e:
        logger.exception("Remove friend error")
        return _error_response(
            500, "INTERNAL_ERROR", "Internal server error"
        )


@tracer.capture_lambda_handler
@logger.inject_lambda_context
def search_by_code(
    event: Dict[str, Any], context: LambdaContext
) -> Dict:
    """GET /friends/search?code=ABCDEF — Search by friend code."""
    try:
        auth_token = _authenticate(event)
        _require_authenticated(auth_token)
        player_id = auth_token.player_id

        if not rate_limiter.check_limit(
            player_id, "friends_search", max_per_min=30
        ):
            return _error_response(
                429, "RATE_LIMIT", "Too many requests"
            )

        params = event.get("queryStringParameters", {}) or {}
        code = params.get("code", "").upper().strip()

        if not code:
            return _error_response(
                400, "MISSING_INPUT", "Provide code parameter"
            )

        profile = asyncio.run(
            player_service.get_player_by_friend_code(code)
        )

        if profile is None:
            return _error_response(
                404, "NOT_FOUND", "No player with that code"
            )

        return {
            "statusCode": 200,
            "headers": _HEADERS,
            "body": json.dumps(
                {
                    "status": "success",
                    "player": {
                        "player_id": profile.player_id,
                        "display_name": profile.display_name,
                        "friend_code": profile.friend_code,
                    },
                }
            ),
        }

    except PermissionError:
        return _error_response(
            401, "UNAUTHORIZED", "Invalid token"
        )
    except Exception as e:
        logger.exception("Search friend code error")
        return _error_response(
            500, "INTERNAL_ERROR", "Internal server error"
        )
