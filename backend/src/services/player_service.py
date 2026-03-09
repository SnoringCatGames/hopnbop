"""Player service for DynamoDB operations."""

import os
import uuid
import boto3
import bcrypt
from typing import Optional
from dataclasses import dataclass, field
from datetime import datetime, timedelta


# Refresh tokens expire after 30 days.
_REFRESH_TOKEN_DAYS = 30


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
    auth_providers: dict = field(default_factory=dict)
    is_anonymous: bool = False
    device_id: str = ""
    consent_accepted_at: int = 0
    consent_legal_version: str = ""


class PlayerService:
    """DynamoDB player operations."""

    def __init__(self):
        self.dynamodb = boto3.resource("dynamodb")
        self.table_name = os.environ.get(
            "PLAYERS_TABLE", "hopnbop-players"
        )
        self.table = self.dynamodb.Table(self.table_name)

    @staticmethod
    def generate_player_id() -> str:
        """Generate a stable UUID-based player ID."""
        return f"p_{uuid.uuid4().hex[:12]}"

    async def get_player(
        self, player_id: str
    ) -> Optional[PlayerProfile]:
        """Retrieve player profile."""
        response = self.table.get_item(
            Key={"player_id": player_id}
        )

        if "Item" not in response:
            return None

        item = response["Item"]
        return PlayerProfile(
            player_id=item["player_id"],
            display_name=item["display_name"],
            rating=int(item.get("rating", 1500)),
            matches_played=int(
                item.get("matches_played", 0)
            ),
            wins=int(item.get("wins", 0)),
            losses=int(item.get("losses", 0)),
            created_at=int(item.get("created_at", 0)),
            last_active=int(
                item.get("last_active", 0)
            ),
            auth_providers=item.get("auth_providers", {}),
            is_anonymous=item.get("is_anonymous", False),
            device_id=item.get("device_id", ""),
            consent_accepted_at=int(
                item.get("consent_accepted_at", 0)
            ),
            consent_legal_version=item.get(
                "consent_legal_version", ""
            ),
        )

    async def create_player(
        self,
        player_id: str,
        display_name: str,
        auth_providers: dict,
        is_anonymous: bool = False,
        device_id: str = "",
        consent_accepted_at: int = 0,
        consent_legal_version: str = "",
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
            auth_providers=auth_providers,
            is_anonymous=is_anonymous,
            device_id=device_id,
            consent_accepted_at=consent_accepted_at,
            consent_legal_version=consent_legal_version,
        )

        item = {
            "player_id": profile.player_id,
            "display_name": profile.display_name,
            "rating": profile.rating,
            "matches_played": profile.matches_played,
            "wins": profile.wins,
            "losses": profile.losses,
            "created_at": profile.created_at,
            "last_active": profile.last_active,
            "auth_providers": profile.auth_providers,
            "is_anonymous": profile.is_anonymous,
            "rating_partition": "all",
        }
        if device_id:
            item["device_id"] = device_id
        if consent_accepted_at:
            item["consent_accepted_at"] = (
                consent_accepted_at
            )
            item["consent_legal_version"] = (
                consent_legal_version
            )

        self.table.put_item(Item=item)
        return profile

    async def update_last_active(
        self, player_id: str
    ) -> None:
        """Update player's last active timestamp."""
        now = int(datetime.now().timestamp())
        self.table.update_item(
            Key={"player_id": player_id},
            UpdateExpression="SET last_active = :now",
            ExpressionAttributeValues={":now": now},
        )

    async def add_provider(
        self,
        player_id: str,
        provider: str,
        provider_id: str,
    ) -> None:
        """Add a provider to a player's auth_providers map."""
        self.table.update_item(
            Key={"player_id": player_id},
            UpdateExpression=(
                "SET auth_providers.#prov = :pid,"
                " is_anonymous = :false"
            ),
            ExpressionAttributeNames={"#prov": provider},
            ExpressionAttributeValues={
                ":pid": provider_id,
                ":false": False,
            },
        )

    async def remove_provider(
        self,
        player_id: str,
        provider: str,
    ) -> None:
        """Remove a provider from a player's auth_providers map."""
        self.table.update_item(
            Key={"player_id": player_id},
            UpdateExpression=(
                "REMOVE auth_providers.#prov"
            ),
            ExpressionAttributeNames={"#prov": provider},
        )

    async def get_or_create_player(
        self,
        player_id: str,
        display_name: str,
        auth_providers: dict,
        is_anonymous: bool = False,
        device_id: str = "",
        consent_accepted_at: int = 0,
        consent_legal_version: str = "",
    ) -> PlayerProfile:
        """Get existing player or create if not exists."""
        profile = await self.get_player(player_id)

        if profile is None:
            profile = await self.create_player(
                player_id,
                display_name,
                auth_providers,
                is_anonymous=is_anonymous,
                device_id=device_id,
                consent_accepted_at=consent_accepted_at,
                consent_legal_version=consent_legal_version,
            )
        elif consent_accepted_at > 0:
            await self.store_consent(
                player_id,
                consent_accepted_at,
                consent_legal_version,
            )
            profile.consent_accepted_at = (
                consent_accepted_at
            )
            profile.consent_legal_version = (
                consent_legal_version
            )

        await self.update_last_active(player_id)
        return profile

    async def store_consent(
        self,
        player_id: str,
        consent_accepted_at: int,
        consent_legal_version: str,
    ) -> None:
        """Store consent timestamp and legal version."""
        self.table.update_item(
            Key={"player_id": player_id},
            UpdateExpression=(
                "SET consent_accepted_at = :cat,"
                " consent_legal_version = :ver"
            ),
            ExpressionAttributeValues={
                ":cat": consent_accepted_at,
                ":ver": consent_legal_version,
            },
        )

    # --- Refresh token methods ---

    async def store_refresh_token(
        self,
        player_id: str,
        refresh_token: str,
    ) -> int:
        """Hash and store a refresh token. Returns expiry timestamp."""
        token_hash = bcrypt.hashpw(
            refresh_token.encode(), bcrypt.gensalt()
        ).decode()
        expires_at = int(
            (
                datetime.now()
                + timedelta(days=_REFRESH_TOKEN_DAYS)
            ).timestamp()
        )

        self.table.update_item(
            Key={"player_id": player_id},
            UpdateExpression=(
                "SET refresh_token_hash = :hash,"
                " refresh_token_expires_at = :exp"
            ),
            ExpressionAttributeValues={
                ":hash": token_hash,
                ":exp": expires_at,
            },
        )
        return expires_at

    async def verify_refresh_token(
        self, player_id: str, refresh_token: str
    ) -> bool:
        """Verify a refresh token against the stored hash."""
        response = self.table.get_item(
            Key={"player_id": player_id},
            ProjectionExpression=(
                "refresh_token_hash,"
                " refresh_token_expires_at"
            ),
        )
        item = response.get("Item")
        if not item:
            return False

        stored_hash = item.get("refresh_token_hash", "")
        expires_at = item.get("refresh_token_expires_at", 0)

        if not stored_hash:
            return False

        # Check expiry.
        now = int(datetime.now().timestamp())
        if now >= expires_at:
            return False

        # Verify hash.
        return bcrypt.checkpw(
            refresh_token.encode(), stored_hash.encode()
        )

    async def clear_refresh_token(
        self, player_id: str
    ) -> None:
        """Remove stored refresh token data."""
        self.table.update_item(
            Key={"player_id": player_id},
            UpdateExpression=(
                "REMOVE refresh_token_hash,"
                " refresh_token_expires_at"
            ),
        )

    async def delete_player(self, player_id: str) -> None:
        """Delete a player record entirely."""
        self.table.delete_item(
            Key={"player_id": player_id}
        )
