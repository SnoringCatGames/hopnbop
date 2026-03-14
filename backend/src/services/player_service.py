"""Player service for DynamoDB operations."""

import os
import secrets
import uuid
import boto3
import bcrypt
from typing import Optional
from dataclasses import dataclass, field
from datetime import datetime, timedelta

from boto3.dynamodb.conditions import Key


# Refresh tokens expire after 30 days.
_REFRESH_TOKEN_DAYS = 30

# Friend code length and max generation retries.
_FRIEND_CODE_LENGTH = 6
_FRIEND_CODE_MAX_RETRIES = 5


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
    friend_code: str = ""
    first_play_time: int = 0
    last_play_time: int = 0
    total_time_played_sec: float = 0.0
    updated_at: int = 0
    total_kills: int = 0
    total_deaths: int = 0
    total_bumps: int = 0
    total_crown_time_sec: float = 0.0
    total_regicide_count: int = 0
    total_jumps: int = 0
    total_water_count: int = 0
    total_ice_count: int = 0
    total_spring_count: int = 0
    total_direction_changes: int = 0
    total_snail_crushes: int = 0
    total_cricket_disturbances: int = 0
    total_fish_disturbances: int = 0
    total_butterfly_disturbances: int = 0
    total_fly_proximity_time_sec: float = 0.0
    total_poop_count: int = 0
    profile_image_url: str = ""


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
            friend_code=item.get("friend_code", ""),
            first_play_time=int(
                item.get("first_play_time", 0)
            ),
            last_play_time=int(
                item.get("last_play_time", 0)
            ),
            total_time_played_sec=float(
                item.get("total_time_played_sec", 0)
            ),
            updated_at=int(item.get("updated_at", 0)),
            total_kills=int(
                item.get("total_kills", 0)
            ),
            total_deaths=int(
                item.get("total_deaths", 0)
            ),
            total_bumps=int(
                item.get("total_bumps", 0)
            ),
            total_crown_time_sec=float(
                item.get("total_crown_time_sec", 0)
            ),
            total_regicide_count=int(
                item.get("total_regicide_count", 0)
            ),
            total_jumps=int(
                item.get("total_jumps", 0)
            ),
            total_water_count=int(
                item.get("total_water_count", 0)
            ),
            total_ice_count=int(
                item.get("total_ice_count", 0)
            ),
            total_spring_count=int(
                item.get("total_spring_count", 0)
            ),
            total_direction_changes=int(
                item.get("total_direction_changes", 0)
            ),
            total_snail_crushes=int(
                item.get("total_snail_crushes", 0)
            ),
            total_cricket_disturbances=int(
                item.get("total_cricket_disturbances", 0)
            ),
            total_fish_disturbances=int(
                item.get("total_fish_disturbances", 0)
            ),
            total_butterfly_disturbances=int(
                item.get(
                    "total_butterfly_disturbances", 0
                )
            ),
            total_fly_proximity_time_sec=float(
                item.get(
                    "total_fly_proximity_time_sec", 0
                )
            ),
            total_poop_count=int(
                item.get("total_poop_count", 0)
            ),
            profile_image_url=item.get(
                "profile_image_url", ""
            ),
        )

    @staticmethod
    def _generate_friend_code() -> str:
        """Generate a random 6-character uppercase alphanumeric code."""
        alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return "".join(
            secrets.choice(alphabet)
            for _ in range(_FRIEND_CODE_LENGTH)
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
        profile_image_url: str = "",
    ) -> PlayerProfile:
        """Create new player profile."""
        now = int(datetime.now().timestamp())
        friend_code = self._generate_friend_code()

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
            friend_code=friend_code,
            first_play_time=now,
            updated_at=now,
            profile_image_url=profile_image_url,
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
            "friend_code": profile.friend_code,
            "first_play_time": profile.first_play_time,
            "updated_at": profile.updated_at,
        }
        if device_id:
            item["device_id"] = device_id
        if profile_image_url:
            item["profile_image_url"] = profile_image_url
        if consent_accepted_at:
            item["consent_accepted_at"] = (
                consent_accepted_at
            )
            item["consent_legal_version"] = (
                consent_legal_version
            )

        self.table.put_item(Item=item)
        return profile

    async def update_profile_image_url(
        self, player_id: str, profile_image_url: str
    ) -> None:
        """Update player's profile image URL."""
        self.table.update_item(
            Key={"player_id": player_id},
            UpdateExpression=(
                "SET profile_image_url = :url"
            ),
            ExpressionAttributeValues={
                ":url": profile_image_url,
            },
        )

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
        profile_image_url: str = "",
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
                profile_image_url=profile_image_url,
            )
        else:
            # Update profile image URL on each login in
            # case the user changed their avatar.
            if profile_image_url:
                await self.update_profile_image_url(
                    player_id, profile_image_url
                )
                profile.profile_image_url = (
                    profile_image_url
                )
            if consent_accepted_at > 0:
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

    async def get_player_by_friend_code(
        self, friend_code: str
    ) -> Optional[PlayerProfile]:
        """Look up a player by their friend code using the GSI."""
        response = self.table.query(
            IndexName="friend-code-index",
            KeyConditionExpression=Key("friend_code").eq(
                friend_code
            ),
            Limit=1,
        )
        items = response.get("Items", [])
        if not items:
            return None
        # GSI is KEYS_ONLY so we need a full get_item.
        return await self.get_player(
            items[0]["player_id"]
        )

    async def delete_player(self, player_id: str) -> None:
        """Delete a player record entirely."""
        self.table.delete_item(
            Key={"player_id": player_id}
        )
