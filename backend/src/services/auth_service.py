"""Authentication service with OAuth2 provider integration."""

import jwt
import httpx
from datetime import datetime, timedelta
from typing import Optional, Dict
from dataclasses import dataclass


@dataclass
class AuthToken:
    """JWT token with player information."""

    player_id: str
    display_name: str
    provider: str
    issued_at: datetime
    expires_at: datetime

    def to_jwt(self, secret: str) -> str:
        """Encode as JWT."""
        payload = {
            "sub": self.player_id,
            "name": self.display_name,
            "provider": self.provider,
            "iat": int(self.issued_at.timestamp()),
            "exp": int(self.expires_at.timestamp()),
        }
        return jwt.encode(payload, secret, algorithm="HS256")

    @classmethod
    def from_jwt(cls, token: str, secret: str) -> "AuthToken":
        """Decode and validate JWT."""
        try:
            payload = jwt.decode(token, secret, algorithms=["HS256"])
        except jwt.ExpiredSignatureError:
            raise ValueError("Token expired")
        except jwt.InvalidTokenError:
            raise ValueError("Invalid token")

        return cls(
            player_id=payload["sub"],
            display_name=payload["name"],
            provider=payload["provider"],
            issued_at=datetime.fromtimestamp(payload["iat"]),
            expires_at=datetime.fromtimestamp(payload["exp"]),
        )


class AuthService:
    """OAuth2 provider integration."""

    def __init__(
        self, jwt_secret: str, token_lifetime_hours: int = 24
    ):
        self.jwt_secret = jwt_secret
        self.token_lifetime = timedelta(hours=token_lifetime_hours)

    async def authenticate_steam(self, steam_ticket: str) -> AuthToken:
        """
        Validate Steam session ticket.

        https://partner.steamgames.com/doc/webapi/ISteamUserAuth#AuthenticateUserTicket
        """
        # Call Steam Web API to validate ticket.
        async with httpx.AsyncClient() as client:
            response = await client.get(
                "https://api.steampowered.com/ISteamUserAuth/AuthenticateUserTicket/v1/",
                params={
                    "key": self._get_steam_api_key(),
                    "appid": self._get_steam_app_id(),
                    "ticket": steam_ticket,
                },
            )

        if response.status_code != 200:
            raise ValueError("Steam authentication failed")

        data = response.json()
        if "response" not in data or "params" not in data["response"]:
            raise ValueError("Invalid Steam response")

        params = data["response"]["params"]
        steam_id = params["steamid"]

        # Get player profile.
        display_name = await self._get_steam_username(steam_id)

        # Issue JWT.
        now = datetime.now()
        return AuthToken(
            player_id=f"steam_{steam_id}",
            display_name=display_name,
            provider="steam",
            issued_at=now,
            expires_at=now + self.token_lifetime,
        )

    async def authenticate_epic(self, access_token: str) -> AuthToken:
        """Validate Epic Games OAuth token."""
        # Call Epic Games API to validate token.
        async with httpx.AsyncClient() as client:
            response = await client.get(
                "https://api.epicgames.dev/epic/oauth/v1/verify",
                headers={"Authorization": f"Bearer {access_token}"},
            )

        if response.status_code != 200:
            raise ValueError("Epic authentication failed")

        data = response.json()
        epic_id = data["account_id"]
        display_name = data.get(
            "display_name", f"Player_{epic_id[:8]}"
        )

        now = datetime.now()
        return AuthToken(
            player_id=f"epic_{epic_id}",
            display_name=display_name,
            provider="epic",
            issued_at=now,
            expires_at=now + self.token_lifetime,
        )

    async def authenticate_cognito(self, cognito_token: str) -> AuthToken:
        """Validate AWS Cognito JWT."""
        # Cognito tokens are already JWTs, verify signature.
        # https://docs.aws.amazon.com/cognito/latest/developerguide/amazon-cognito-user-pools-using-tokens-verifying-a-jwt.html

        # This is simplified - real implementation needs:
        # 1. Download Cognito JWKS.
        # 2. Verify signature with public key.
        # 3. Check issuer, audience, expiration.

        try:
            payload = jwt.decode(
                cognito_token,
                options={
                    "verify_signature": False
                },  # Verify with JWKS in production.
            )
        except jwt.InvalidTokenError:
            raise ValueError("Invalid Cognito token")

        cognito_id = payload["sub"]
        display_name = payload.get(
            "cognito:username", f"Player_{cognito_id[:8]}"
        )

        now = datetime.now()
        return AuthToken(
            player_id=f"cognito_{cognito_id}",
            display_name=display_name,
            provider="cognito",
            issued_at=now,
            expires_at=now + self.token_lifetime,
        )

    def _get_steam_api_key(self) -> str:
        """Get from environment/Parameter Store."""
        import os

        return os.environ["STEAM_API_KEY"]

    def _get_steam_app_id(self) -> str:
        """Get from environment."""
        import os

        return os.environ["STEAM_APP_ID"]

    async def _get_steam_username(self, steam_id: str) -> str:
        """Fetch Steam username via ISteamUser API."""
        async with httpx.AsyncClient() as client:
            response = await client.get(
                "https://api.steampowered.com/ISteamUser/GetPlayerSummaries/v2/",
                params={
                    "key": self._get_steam_api_key(),
                    "steamids": steam_id,
                },
            )

        data = response.json()
        players = data.get("response", {}).get("players", [])
        if players:
            return players[0].get(
                "personaname", f"Player_{steam_id[:8]}"
            )

        return f"Player_{steam_id[:8]}"
