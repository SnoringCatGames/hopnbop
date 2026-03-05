"""Tests for auth_service.py - AuthToken and AuthService."""

import asyncio
import time
from datetime import datetime, timedelta
from unittest.mock import AsyncMock, patch, MagicMock

import jwt
import pytest

TEST_JWT_SECRET = "test-secret-key-for-unit-tests"


def _run(coro):
    """Run an async coroutine synchronously."""
    return asyncio.run(coro)


# =========================================================================
# AuthToken
# =========================================================================


class TestAuthTokenRoundTrip:
    """AuthToken.to_jwt() and from_jwt() round-trip tests."""

    def test_round_trip(self):
        from services.auth_service import AuthToken

        now = datetime.now()
        token = AuthToken(
            player_id="p_abc123",
            display_name="TestPlayer",
            provider="steam",
            is_anonymous=False,
            issued_at=now,
            expires_at=now + timedelta(hours=24),
        )

        encoded = token.to_jwt(TEST_JWT_SECRET)
        decoded = AuthToken.from_jwt(encoded, TEST_JWT_SECRET)

        assert decoded.player_id == "p_abc123"
        assert decoded.display_name == "TestPlayer"
        assert decoded.provider == "steam"
        assert decoded.is_anonymous is False

    def test_anonymous_flag_preserved(self):
        from services.auth_service import AuthToken

        now = datetime.now()
        token = AuthToken(
            player_id="p_anon999",
            display_name="AnonPlayer",
            provider="anonymous",
            is_anonymous=True,
            issued_at=now,
            expires_at=now + timedelta(hours=24),
        )

        encoded = token.to_jwt(TEST_JWT_SECRET)
        decoded = AuthToken.from_jwt(encoded, TEST_JWT_SECRET)
        assert decoded.is_anonymous is True
        assert decoded.provider == "anonymous"

    def test_expired_token_raises(self):
        from services.auth_service import AuthToken

        now = datetime.now()
        token = AuthToken(
            player_id="p_expired",
            display_name="Expired",
            provider="steam",
            is_anonymous=False,
            issued_at=now - timedelta(hours=25),
            expires_at=now - timedelta(hours=1),
        )

        encoded = token.to_jwt(TEST_JWT_SECRET)

        with pytest.raises(ValueError, match="Token expired"):
            AuthToken.from_jwt(encoded, TEST_JWT_SECRET)

    def test_tampered_token_raises(self):
        from services.auth_service import AuthToken

        now = datetime.now()
        token = AuthToken(
            player_id="p_tampered",
            display_name="Tampered",
            provider="steam",
            is_anonymous=False,
            issued_at=now,
            expires_at=now + timedelta(hours=24),
        )

        encoded = token.to_jwt(TEST_JWT_SECRET)
        # Tamper with the payload.
        tampered = encoded[:-5] + "XXXXX"

        with pytest.raises(ValueError, match="Invalid token"):
            AuthToken.from_jwt(tampered, TEST_JWT_SECRET)

    def test_wrong_secret_raises(self):
        from services.auth_service import AuthToken

        now = datetime.now()
        token = AuthToken(
            player_id="p_wrong",
            display_name="WrongKey",
            provider="steam",
            is_anonymous=False,
            issued_at=now,
            expires_at=now + timedelta(hours=24),
        )

        encoded = token.to_jwt(TEST_JWT_SECRET)

        with pytest.raises(ValueError, match="Invalid token"):
            AuthToken.from_jwt(encoded, "wrong-secret")


# =========================================================================
# AuthService.create_auth_token
# =========================================================================


class TestCreateAuthToken:
    def test_creates_token_with_correct_lifetime(self):
        from services.auth_service import AuthService

        service = AuthService(token_lifetime_hours=12)
        token = service.create_auth_token(
            "p_test123", "TestName", "google"
        )

        assert token.player_id == "p_test123"
        assert token.display_name == "TestName"
        assert token.provider == "google"
        assert token.is_anonymous is False
        delta = token.expires_at - token.issued_at
        assert abs(delta.total_seconds() - 12 * 3600) < 2

    def test_anonymous_flag(self):
        from services.auth_service import AuthService

        service = AuthService()
        token = service.create_auth_token(
            "p_anon", "Anon", "anonymous", is_anonymous=True
        )
        assert token.is_anonymous is True


# =========================================================================
# AuthService.authenticate - provider dispatch
# =========================================================================


class TestAuthenticateDispatch:
    def test_unsupported_provider_raises(self, aws_mock):
        from services.auth_service import AuthService

        service = AuthService()
        with pytest.raises(
            ValueError, match="Unsupported provider"
        ):
            _run(service.authenticate("foobar", "code123"))


# =========================================================================
# AuthService._auth_steam
# =========================================================================


class TestAuthSteam:
    def test_valid_steam_ticket(self, aws_mock):
        from services.auth_service import AuthService

        mock_auth_response = MagicMock()
        mock_auth_response.status_code = 200
        mock_auth_response.json.return_value = {
            "response": {
                "params": {"steamid": "76561198012345678"}
            }
        }

        mock_user_response = MagicMock()
        mock_user_response.status_code = 200
        mock_user_response.json.return_value = {
            "response": {
                "players": [
                    {"personaname": "SteamPlayer"}
                ]
            }
        }

        with patch(
            "services.auth_service.httpx.AsyncClient"
        ) as mock_client_cls:
            mock_client = AsyncMock()
            mock_client.__aenter__ = AsyncMock(
                return_value=mock_client
            )
            mock_client.__aexit__ = AsyncMock(
                return_value=False
            )
            mock_client.get = AsyncMock(
                side_effect=[
                    mock_auth_response,
                    mock_user_response,
                ]
            )
            mock_client_cls.return_value = mock_client

            service = AuthService()
            result = _run(
                service._auth_steam("FAKE_TICKET")
            )

        assert result.provider == "steam"
        assert result.provider_id == "76561198012345678"
        assert result.display_name == "SteamPlayer"

    def test_invalid_steam_ticket(self, aws_mock):
        from services.auth_service import AuthService

        mock_response = MagicMock()
        mock_response.status_code = 403

        with patch(
            "services.auth_service.httpx.AsyncClient"
        ) as mock_client_cls:
            mock_client = AsyncMock()
            mock_client.__aenter__ = AsyncMock(
                return_value=mock_client
            )
            mock_client.__aexit__ = AsyncMock(
                return_value=False
            )
            mock_client.get = AsyncMock(
                return_value=mock_response
            )
            mock_client_cls.return_value = mock_client

            service = AuthService()
            with pytest.raises(
                ValueError,
                match="Steam authentication failed",
            ):
                _run(service._auth_steam("BAD_TICKET"))


# =========================================================================
# AuthService._auth_google
# =========================================================================


class TestAuthGoogle:
    def test_valid_google_code(self, aws_mock):
        from services.auth_service import AuthService

        # Build a fake Google id_token (unsigned JWT).
        fake_id_token = jwt.encode(
            {"sub": "google_user_123", "name": "GoogleUser"},
            "not-verified",
            algorithm="HS256",
        )

        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.json.return_value = {
            "id_token": fake_id_token,
            "access_token": "fake_access",
        }

        with patch(
            "services.auth_service.httpx.AsyncClient"
        ) as mock_client_cls:
            mock_client = AsyncMock()
            mock_client.__aenter__ = AsyncMock(
                return_value=mock_client
            )
            mock_client.__aexit__ = AsyncMock(
                return_value=False
            )
            mock_client.post = AsyncMock(
                return_value=mock_response
            )
            mock_client_cls.return_value = mock_client

            service = AuthService()
            result = _run(
                service._auth_google(
                    "AUTH_CODE",
                    "http://127.0.0.1:9876/callback",
                )
            )

        assert result.provider == "google"
        assert result.provider_id == "google_user_123"
        assert result.display_name == "GoogleUser"


# =========================================================================
# AuthService._auth_discord
# =========================================================================


class TestAuthDiscord:
    def test_valid_discord_code(self, aws_mock):
        from services.auth_service import AuthService

        mock_token_resp = MagicMock()
        mock_token_resp.status_code = 200
        mock_token_resp.json.return_value = {
            "access_token": "discord_access_token"
        }

        mock_user_resp = MagicMock()
        mock_user_resp.status_code = 200
        mock_user_resp.json.return_value = {
            "id": "discord_user_456",
            "global_name": "DiscordUser",
            "username": "discorduser",
        }

        with patch(
            "services.auth_service.httpx.AsyncClient"
        ) as mock_client_cls:
            mock_client = AsyncMock()
            mock_client.__aenter__ = AsyncMock(
                return_value=mock_client
            )
            mock_client.__aexit__ = AsyncMock(
                return_value=False
            )
            mock_client.post = AsyncMock(
                return_value=mock_token_resp
            )
            mock_client.get = AsyncMock(
                return_value=mock_user_resp
            )
            mock_client_cls.return_value = mock_client

            service = AuthService()
            result = _run(
                service._auth_discord(
                    "AUTH_CODE",
                    "http://127.0.0.1:9876/callback",
                )
            )

        assert result.provider == "discord"
        assert result.provider_id == "discord_user_456"
        assert result.display_name == "DiscordUser"


# =========================================================================
# AuthService._auth_twitch
# =========================================================================


class TestAuthTwitch:
    def test_valid_twitch_code(self, aws_mock):
        from services.auth_service import AuthService

        mock_token_resp = MagicMock()
        mock_token_resp.status_code = 200
        mock_token_resp.json.return_value = {
            "access_token": "twitch_access_token"
        }

        mock_user_resp = MagicMock()
        mock_user_resp.status_code = 200
        mock_user_resp.json.return_value = {
            "data": [
                {
                    "id": "twitch_user_789",
                    "display_name": "TwitchStreamer",
                }
            ]
        }

        with patch(
            "services.auth_service.httpx.AsyncClient"
        ) as mock_client_cls:
            mock_client = AsyncMock()
            mock_client.__aenter__ = AsyncMock(
                return_value=mock_client
            )
            mock_client.__aexit__ = AsyncMock(
                return_value=False
            )
            mock_client.post = AsyncMock(
                return_value=mock_token_resp
            )
            mock_client.get = AsyncMock(
                return_value=mock_user_resp
            )
            mock_client_cls.return_value = mock_client

            service = AuthService()
            result = _run(
                service._auth_twitch(
                    "AUTH_CODE",
                    "http://127.0.0.1:9876/callback",
                )
            )

        assert result.provider == "twitch"
        assert result.provider_id == "twitch_user_789"
        assert result.display_name == "TwitchStreamer"


# =========================================================================
# AuthService._auth_epic
# =========================================================================


class TestAuthEpic:
    def test_valid_epic_token(self, aws_mock):
        from services.auth_service import AuthService

        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.json.return_value = {
            "account_id": "epic_acc_321",
            "display_name": "EpicGamer",
        }

        with patch(
            "services.auth_service.httpx.AsyncClient"
        ) as mock_client_cls:
            mock_client = AsyncMock()
            mock_client.__aenter__ = AsyncMock(
                return_value=mock_client
            )
            mock_client.__aexit__ = AsyncMock(
                return_value=False
            )
            mock_client.get = AsyncMock(
                return_value=mock_response
            )
            mock_client_cls.return_value = mock_client

            service = AuthService()
            result = _run(
                service._auth_epic("FAKE_ACCESS_TOKEN")
            )

        assert result.provider == "epic"
        assert result.provider_id == "epic_acc_321"
        assert result.display_name == "EpicGamer"

    def test_invalid_epic_token(self, aws_mock):
        from services.auth_service import AuthService

        mock_response = MagicMock()
        mock_response.status_code = 401

        with patch(
            "services.auth_service.httpx.AsyncClient"
        ) as mock_client_cls:
            mock_client = AsyncMock()
            mock_client.__aenter__ = AsyncMock(
                return_value=mock_client
            )
            mock_client.__aexit__ = AsyncMock(
                return_value=False
            )
            mock_client.get = AsyncMock(
                return_value=mock_response
            )
            mock_client_cls.return_value = mock_client

            service = AuthService()
            with pytest.raises(
                ValueError,
                match="Epic authentication failed",
            ):
                _run(
                    service._auth_epic("BAD_TOKEN")
                )
