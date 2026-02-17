"""Player service for DynamoDB operations."""

import os
import boto3
from typing import Optional
from dataclasses import dataclass
from datetime import datetime


@dataclass
class PlayerProfile:
    """Player profile data."""

    player_id: str
    display_name: str
    rating: int
    matches_played: int
    wins: int
    losses: int
    created_at: int
    last_active: int
    auth_provider: str


class PlayerService:
    """DynamoDB player operations."""

    def __init__(self):
        self.dynamodb = boto3.resource("dynamodb")
        self.table_name = os.environ.get(
            "PLAYERS_TABLE", "hopnbop-players"
        )
        self.table = self.dynamodb.Table(self.table_name)

    async def get_player(
        self, player_id: str
    ) -> Optional[PlayerProfile]:
        """Retrieve player profile."""
        response = self.table.get_item(Key={"player_id": player_id})

        if "Item" not in response:
            return None

        item = response["Item"]
        return PlayerProfile(
            player_id=item["player_id"],
            display_name=item["display_name"],
            rating=item.get("rating", 1500),
            matches_played=item.get("matches_played", 0),
            wins=item.get("wins", 0),
            losses=item.get("losses", 0),
            created_at=item.get("created_at", 0),
            last_active=item.get("last_active", 0),
            auth_provider=item.get("auth_provider", "unknown"),
        )

    async def create_player(
        self, player_id: str, display_name: str, auth_provider: str
    ) -> PlayerProfile:
        """Create new player profile."""
        now = int(datetime.now().timestamp())

        profile = PlayerProfile(
            player_id=player_id,
            display_name=display_name,
            rating=1500,
            matches_played=0,
            wins=0,
            losses=0,
            created_at=now,
            last_active=now,
            auth_provider=auth_provider,
        )

        self.table.put_item(
            Item={
                "player_id": profile.player_id,
                "display_name": profile.display_name,
                "rating": profile.rating,
                "matches_played": profile.matches_played,
                "wins": profile.wins,
                "losses": profile.losses,
                "created_at": profile.created_at,
                "last_active": profile.last_active,
                "auth_provider": profile.auth_provider,
            }
        )

        return profile

    async def update_last_active(self, player_id: str) -> None:
        """Update player's last active timestamp."""
        now = int(datetime.now().timestamp())

        self.table.update_item(
            Key={"player_id": player_id},
            UpdateExpression="SET last_active = :now",
            ExpressionAttributeValues={":now": now},
        )

    async def get_or_create_player(
        self, player_id: str, display_name: str, auth_provider: str
    ) -> PlayerProfile:
        """Get existing player or create if not exists."""
        profile = await self.get_player(player_id)

        if profile is None:
            profile = await self.create_player(
                player_id, display_name, auth_provider
            )

        # Update last active.
        await self.update_last_active(player_id)

        return profile
