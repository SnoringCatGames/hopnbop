"""Lambda handlers for player data operations."""

import json
import os
import asyncio
from datetime import datetime
from typing import Dict, Any
import boto3
from aws_lambda_powertools import Logger, Tracer
from aws_lambda_powertools.utilities.typing import LambdaContext

import sys

sys.path.append(os.path.join(os.path.dirname(__file__), ".."))

from services.auth_service import AuthService, AuthToken
from services.player_service import PlayerService

logger = Logger()
tracer = Tracer()

auth_service = AuthService(token_lifetime_hours=24)
player_service = PlayerService()

# CORS headers included in every response.
_HEADERS = {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": "*",
}


@tracer.capture_lambda_handler
@logger.inject_lambda_context
def export_player_data(
    event: Dict[str, Any], context: LambdaContext
) -> Dict:
    """GET /player/export - Export all player data."""
    try:
        # Validate JWT from Authorization header.
        auth_header = (
            event.get("headers", {}).get(
                "Authorization", ""
            )
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

        player_id = current_token.player_id

        # Get player profile.
        profile = asyncio.run(
            player_service.get_player(player_id)
        )
        if profile is None:
            return _error(
                404, "NOT_FOUND", "Player not found"
            )

        # Query match history.
        match_history = _get_match_history(player_id)

        # Build export payload.
        export_data = {
            "status": "success",
            "exported_at": int(
                datetime.now().timestamp()
            ),
            "player": {
                "player_id": profile.player_id,
                "display_name": profile.display_name,
                "rating": profile.rating,
                "matches_played": profile.matches_played,
                "wins": profile.wins,
                "losses": profile.losses,
                "created_at": profile.created_at,
                "last_active": profile.last_active,
                "is_anonymous": profile.is_anonymous,
                "linked_providers": list(
                    profile.auth_providers.keys()
                ),
                "consent_accepted_at": (
                    profile.consent_accepted_at
                ),
                "consent_legal_version": (
                    profile.consent_legal_version
                ),
            },
            "match_history": match_history,
        }

        logger.info(f"Data exported: {player_id}")

        return {
            "statusCode": 200,
            "headers": _HEADERS,
            "body": json.dumps(export_data),
        }

    except Exception:
        logger.exception("Export player data error")
        return _error(
            500, "INTERNAL_ERROR", "Internal server error"
        )


def _get_match_history(
    player_id: str,
) -> list:
    """Query all match history for a player."""
    dynamodb = boto3.resource("dynamodb")
    table_name = os.environ.get(
        "MATCH_HISTORY_TABLE", "hopnbop-match-history"
    )
    table = dynamodb.Table(table_name)

    items = []
    response = table.query(
        KeyConditionExpression=(
            boto3.dynamodb.conditions.Key(
                "player_id"
            ).eq(player_id)
        ),
    )
    items.extend(response.get("Items", []))

    while "LastEvaluatedKey" in response:
        response = table.query(
            KeyConditionExpression=(
                boto3.dynamodb.conditions.Key(
                    "player_id"
                ).eq(player_id)
            ),
            ExclusiveStartKey=response[
                "LastEvaluatedKey"
            ],
        )
        items.extend(response.get("Items", []))

    # Convert Decimal types to int/float for JSON.
    results = []
    for item in items:
        entry = {}
        for key, value in item.items():
            if key == "player_id":
                continue
            if hasattr(value, "is_integer"):
                entry[key] = (
                    int(value) if value.is_integer()
                    else float(value)
                )
            else:
                entry[key] = value
        results.append(entry)

    return results


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
