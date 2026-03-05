"""Lambda handlers for authentication operations."""

import json
import os
import secrets
import asyncio
from typing import Dict, Any
from aws_lambda_powertools import Logger, Tracer
from aws_lambda_powertools.utilities.typing import LambdaContext

import sys

sys.path.append(os.path.join(os.path.dirname(__file__), ".."))

from services.auth_service import AuthService, AuthToken
from services.player_service import PlayerService
from services.provider_mapping_service import ProviderMappingService

logger = Logger()
tracer = Tracer()

# Initialize services.
auth_service = AuthService(token_lifetime_hours=24)
player_service = PlayerService()
provider_mapping_service = ProviderMappingService()

_GAME_VERSION = os.environ.get("GAME_VERSION", "0.1.0")

# CORS headers included in every response.
_HEADERS = {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": "*",
}


@tracer.capture_lambda_handler
@logger.inject_lambda_context
def login(
    event: Dict[str, Any], context: LambdaContext
) -> Dict:
    """POST /auth/login - Authenticate with an OAuth provider."""
    try:
        body = json.loads(event.get("body", "{}"))
        provider = body.get("provider", "")
        auth_code = body.get("auth_code", "")
        redirect_uri = body.get("redirect_uri", "")

        if not provider or not auth_code:
            return _error(
                400,
                "MISSING_PARAMS",
                "Missing provider or auth_code",
            )

        # Authenticate with provider. Returns provider_id
        # and display_name.
        auth_result = asyncio.run(
            auth_service.authenticate(
                provider, auth_code, redirect_uri
            )
        )

        # Look up canonical player_id.
        player_id = asyncio.run(
            provider_mapping_service.lookup(
                auth_result.provider,
                auth_result.provider_id,
            )
        )

        if player_id is None:
            # New player.
            player_id = PlayerService.generate_player_id()
            asyncio.run(
                provider_mapping_service.create(
                    auth_result.provider,
                    auth_result.provider_id,
                    player_id,
                )
            )

        # Get or create player profile.
        player_profile = asyncio.run(
            player_service.get_or_create_player(
                player_id,
                auth_result.display_name,
                {auth_result.provider: auth_result.provider_id},
            )
        )

        # Issue tokens.
        auth_token = auth_service.create_auth_token(
            player_id,
            auth_result.display_name,
            auth_result.provider,
        )
        jwt_token = auth_token.to_jwt(
            auth_service.jwt_secret
        )
        refresh_token = secrets.token_hex(32)
        asyncio.run(
            player_service.store_refresh_token(
                player_id, refresh_token
            )
        )

        logger.info(
            f"User authenticated: {player_id} "
            f"via {provider}"
        )

        return {
            "statusCode": 200,
            "headers": _HEADERS,
            "body": json.dumps(
                {
                    "status": "success",
                    "jwt_token": jwt_token,
                    "refresh_token": refresh_token,
                    "player_id": player_id,
                    "display_name": auth_result.display_name,
                    "is_anonymous": False,
                    "rating": player_profile.rating,
                    "game_version": _GAME_VERSION,
                    "expires_at": int(
                        auth_token.expires_at.timestamp()
                    ),
                }
            ),
        }

    except ValueError as e:
        logger.error(f"Authentication failed: {e}")
        return _error(401, "AUTH_FAILED", str(e))
    except Exception:
        logger.exception("Login error")
        return _error(
            500, "INTERNAL_ERROR", "Internal server error"
        )


@tracer.capture_lambda_handler
@logger.inject_lambda_context
def anonymous_login(
    event: Dict[str, Any], context: LambdaContext
) -> Dict:
    """POST /auth/anon - Create or retrieve anonymous session."""
    try:
        body = json.loads(event.get("body", "{}"))
        device_id = body.get("device_id", "")

        if not device_id:
            return _error(
                400,
                "MISSING_PARAMS",
                "Missing device_id",
            )

        # Look up existing anonymous player by device_id
        # via provider mapping (provider="anonymous").
        player_id = asyncio.run(
            provider_mapping_service.lookup(
                "anonymous", device_id
            )
        )

        if player_id is None:
            player_id = PlayerService.generate_player_id()
            asyncio.run(
                provider_mapping_service.create(
                    "anonymous", device_id, player_id
                )
            )

        display_name = f"Player_{player_id[2:10]}"

        player_profile = asyncio.run(
            player_service.get_or_create_player(
                player_id,
                display_name,
                {},
                is_anonymous=True,
                device_id=device_id,
            )
        )

        # Issue tokens.
        auth_token = auth_service.create_auth_token(
            player_id,
            display_name,
            "anonymous",
            is_anonymous=True,
        )
        jwt_token = auth_token.to_jwt(
            auth_service.jwt_secret
        )
        refresh_token = secrets.token_hex(32)
        asyncio.run(
            player_service.store_refresh_token(
                player_id, refresh_token
            )
        )

        logger.info(f"Anonymous login: {player_id}")

        return {
            "statusCode": 200,
            "headers": _HEADERS,
            "body": json.dumps(
                {
                    "status": "success",
                    "jwt_token": jwt_token,
                    "refresh_token": refresh_token,
                    "player_id": player_id,
                    "display_name": display_name,
                    "is_anonymous": True,
                    "rating": player_profile.rating,
                    "game_version": _GAME_VERSION,
                    "expires_at": int(
                        auth_token.expires_at.timestamp()
                    ),
                }
            ),
        }

    except Exception:
        logger.exception("Anonymous login error")
        return _error(
            500, "INTERNAL_ERROR", "Internal server error"
        )


@tracer.capture_lambda_handler
@logger.inject_lambda_context
def refresh(
    event: Dict[str, Any], context: LambdaContext
) -> Dict:
    """POST /auth/refresh - Refresh an expired JWT."""
    try:
        body = json.loads(event.get("body", "{}"))
        player_id = body.get("player_id", "")
        refresh_token = body.get("refresh_token", "")

        if not player_id or not refresh_token:
            return _error(
                400,
                "MISSING_PARAMS",
                "Missing player_id or refresh_token",
            )

        # Verify refresh token.
        is_valid = asyncio.run(
            player_service.verify_refresh_token(
                player_id, refresh_token
            )
        )
        if not is_valid:
            return _error(
                401,
                "INVALID_REFRESH",
                "Invalid or expired refresh token",
            )

        # Get player profile for display name and provider.
        profile = asyncio.run(
            player_service.get_player(player_id)
        )
        if profile is None:
            return _error(
                404, "NOT_FOUND", "Player not found"
            )

        # Determine primary provider.
        provider = "anonymous"
        if profile.auth_providers:
            provider = next(iter(profile.auth_providers))

        # Rotate: issue new tokens and invalidate old.
        auth_token = auth_service.create_auth_token(
            player_id,
            profile.display_name,
            provider,
            is_anonymous=profile.is_anonymous,
        )
        new_jwt = auth_token.to_jwt(
            auth_service.jwt_secret
        )
        new_refresh = secrets.token_hex(32)
        asyncio.run(
            player_service.store_refresh_token(
                player_id, new_refresh
            )
        )

        logger.info(f"Token refreshed: {player_id}")

        return {
            "statusCode": 200,
            "headers": _HEADERS,
            "body": json.dumps(
                {
                    "status": "success",
                    "jwt_token": new_jwt,
                    "refresh_token": new_refresh,
                    "player_id": player_id,
                    "display_name": profile.display_name,
                    "is_anonymous": profile.is_anonymous,
                    "rating": profile.rating,
                    "game_version": _GAME_VERSION,
                    "expires_at": int(
                        auth_token.expires_at.timestamp()
                    ),
                }
            ),
        }

    except Exception:
        logger.exception("Refresh error")
        return _error(
            500, "INTERNAL_ERROR", "Internal server error"
        )


@tracer.capture_lambda_handler
@logger.inject_lambda_context
def link_account(
    event: Dict[str, Any], context: LambdaContext
) -> Dict:
    """POST /auth/link - Link a new provider to an existing account."""
    try:
        # Validate JWT from Authorization header.
        auth_header = (
            event.get("headers", {}).get("Authorization", "")
            or event.get("headers", {}).get(
                "authorization", ""
            )
        )
        if not auth_header.startswith("Bearer "):
            return _error(
                401, "UNAUTHORIZED", "Missing auth token"
            )

        token_str = auth_header[7:]
        try:
            current_token = AuthToken.from_jwt(
                token_str, auth_service.jwt_secret
            )
        except ValueError as e:
            return _error(401, "UNAUTHORIZED", str(e))

        body = json.loads(event.get("body", "{}"))
        provider = body.get("provider", "")
        auth_code = body.get("auth_code", "")
        redirect_uri = body.get("redirect_uri", "")

        if not provider or not auth_code:
            return _error(
                400,
                "MISSING_PARAMS",
                "Missing provider or auth_code",
            )

        # Authenticate with the new provider.
        auth_result = asyncio.run(
            auth_service.authenticate(
                provider, auth_code, redirect_uri
            )
        )

        # Check if this provider ID is already mapped.
        existing_player_id = asyncio.run(
            provider_mapping_service.lookup(
                auth_result.provider,
                auth_result.provider_id,
            )
        )

        if existing_player_id is not None:
            if existing_player_id == current_token.player_id:
                # Already linked to this account.
                return {
                    "statusCode": 200,
                    "headers": _HEADERS,
                    "body": json.dumps(
                        {
                            "status": "success",
                            "message": "Provider already linked",
                        }
                    ),
                }
            else:
                return _error(
                    409,
                    "PROVIDER_CONFLICT",
                    "This provider account is already "
                    "linked to a different player",
                )

        # Add provider to current player.
        asyncio.run(
            provider_mapping_service.create(
                auth_result.provider,
                auth_result.provider_id,
                current_token.player_id,
            )
        )
        asyncio.run(
            player_service.add_provider(
                current_token.player_id,
                auth_result.provider,
                auth_result.provider_id,
            )
        )

        logger.info(
            f"Linked {provider} to {current_token.player_id}"
        )

        return {
            "statusCode": 200,
            "headers": _HEADERS,
            "body": json.dumps(
                {
                    "status": "success",
                    "message": "Provider linked",
                    "provider": auth_result.provider,
                }
            ),
        }

    except ValueError as e:
        logger.error(f"Link failed: {e}")
        return _error(401, "AUTH_FAILED", str(e))
    except Exception:
        logger.exception("Link account error")
        return _error(
            500, "INTERNAL_ERROR", "Internal server error"
        )


def _error(
    status_code: int, error_code: str, message: str
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
