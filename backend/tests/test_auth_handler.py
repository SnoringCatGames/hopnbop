"""Tests for auth_handler.py - Lambda endpoint handlers."""

import json
import asyncio
from unittest.mock import patch, AsyncMock, MagicMock
from datetime import datetime, timedelta

import pytest

TEST_JWT_SECRET = "test-secret-key-for-unit-tests"


class _FakeLambdaContext:
    """Minimal Lambda context for aws_lambda_powertools."""

    function_name = "test-function"
    memory_limit_in_mb = 512
    invoked_function_arn = (
        "arn:aws:lambda:us-east-1:123456789:function:test"
    )
    aws_request_id = "test-request-id"


_CONTEXT = _FakeLambdaContext()


def _make_event(body=None, headers=None):
    """Build a minimal Lambda API Gateway event."""
    event = {
        "body": json.dumps(body) if body else "{}",
        "headers": headers or {},
    }
    return event


def _parse_response(response):
    """Parse status code and body from Lambda response."""
    return response["statusCode"], json.loads(response["body"])


# =========================================================================
# POST /auth/login
# =========================================================================


class TestLogin:
    def test_missing_provider_returns_400(self, aws_mock):
        from handlers.auth_handler import login

        event = _make_event(body={"auth_code": "code123"})
        status, body = _parse_response(login(event, _CONTEXT))

        assert status == 400
        assert body["error_code"] == "MISSING_PARAMS"

    def test_missing_auth_code_returns_400(self, aws_mock):
        from handlers.auth_handler import login

        event = _make_event(body={"provider": "steam"})
        status, body = _parse_response(login(event, _CONTEXT))

        assert status == 400
        assert body["error_code"] == "MISSING_PARAMS"

    def test_valid_auth_returns_200(self, aws_mock):
        from handlers.auth_handler import login
        from services.auth_service import AuthResult

        mock_result = AuthResult(
            provider="steam",
            provider_id="steam_12345",
            display_name="TestPlayer",
        )

        with patch(
            "handlers.auth_handler.auth_service"
        ) as mock_auth:
            mock_auth.authenticate = AsyncMock(
                return_value=mock_result
            )
            mock_auth.jwt_secret = TEST_JWT_SECRET
            mock_auth.create_auth_token = MagicMock()
            # Return a real-ish token.
            from services.auth_service import AuthToken

            now = datetime.now()
            fake_token = AuthToken(
                player_id="p_abc123",
                display_name="TestPlayer",
                provider="steam",
                is_anonymous=False,
                issued_at=now,
                expires_at=now + timedelta(hours=24),
            )
            mock_auth.create_auth_token.return_value = (
                fake_token
            )

            event = _make_event(
                body={
                    "provider": "steam",
                    "auth_code": "TICKET",
                }
            )
            status, body = _parse_response(
                login(event, _CONTEXT)
            )

        assert status == 200
        assert body["status"] == "success"
        assert "jwt_token" in body
        assert "refresh_token" in body
        assert "player_id" in body
        assert body["is_anonymous"] is False

    def test_auth_failure_returns_401(self, aws_mock):
        from handlers.auth_handler import login

        with patch(
            "handlers.auth_handler.auth_service"
        ) as mock_auth:
            mock_auth.authenticate = AsyncMock(
                side_effect=ValueError("Steam auth failed")
            )

            event = _make_event(
                body={
                    "provider": "steam",
                    "auth_code": "BAD",
                }
            )
            status, body = _parse_response(
                login(event, _CONTEXT)
            )

        assert status == 401
        assert body["error_code"] == "AUTH_FAILED"


# =========================================================================
# POST /auth/anon
# =========================================================================


class TestAnonymousLogin:
    def test_missing_device_id_returns_400(self, aws_mock):
        from handlers.auth_handler import anonymous_login

        event = _make_event(body={})
        status, body = _parse_response(
            anonymous_login(event, _CONTEXT)
        )

        assert status == 400
        assert body["error_code"] == "MISSING_PARAMS"

    def test_new_device_creates_player(self, aws_mock):
        from handlers.auth_handler import anonymous_login

        event = _make_event(
            body={"device_id": "test-device-abc"}
        )
        status, body = _parse_response(
            anonymous_login(event, _CONTEXT)
        )

        assert status == 200
        assert body["status"] == "success"
        assert body["is_anonymous"] is True
        assert "jwt_token" in body
        assert "refresh_token" in body
        assert body["player_id"].startswith("p_")

    def test_existing_device_returns_same_player(
        self, aws_mock
    ):
        from handlers.auth_handler import anonymous_login

        event = _make_event(
            body={"device_id": "test-device-xyz"}
        )

        _, body1 = _parse_response(
            anonymous_login(event, _CONTEXT)
        )
        _, body2 = _parse_response(
            anonymous_login(event, _CONTEXT)
        )

        assert body1["player_id"] == body2["player_id"]


# =========================================================================
# POST /auth/refresh
# =========================================================================


class TestRefresh:
    def _create_player_with_token(self):
        """Helper: create anonymous player, return body."""
        from handlers.auth_handler import anonymous_login

        event = _make_event(
            body={"device_id": "refresh-test-device"}
        )
        _, body = _parse_response(
            anonymous_login(event, _CONTEXT)
        )
        return body

    def test_missing_params_returns_400(self, aws_mock):
        from handlers.auth_handler import refresh

        event = _make_event(body={})
        status, body = _parse_response(refresh(event, _CONTEXT))

        assert status == 400
        assert body["error_code"] == "MISSING_PARAMS"

    def test_invalid_refresh_token_returns_401(
        self, aws_mock
    ):
        from handlers.auth_handler import refresh

        login_body = self._create_player_with_token()

        event = _make_event(
            body={
                "player_id": login_body["player_id"],
                "refresh_token": "wrong-token",
            }
        )
        status, body = _parse_response(refresh(event, _CONTEXT))

        assert status == 401
        assert body["error_code"] == "INVALID_REFRESH"

    def test_valid_refresh_rotates_tokens(self, aws_mock):
        from handlers.auth_handler import refresh

        login_body = self._create_player_with_token()

        event = _make_event(
            body={
                "player_id": login_body["player_id"],
                "refresh_token": login_body["refresh_token"],
            }
        )
        status, body = _parse_response(refresh(event, _CONTEXT))

        assert status == 200
        assert body["status"] == "success"
        assert "jwt_token" in body
        assert "refresh_token" in body
        # New tokens should differ from old ones.
        assert body["jwt_token"] != login_body["jwt_token"]
        assert (
            body["refresh_token"]
            != login_body["refresh_token"]
        )


# =========================================================================
# POST /auth/link
# =========================================================================


class TestLinkAccount:
    def test_missing_auth_header_returns_401(self, aws_mock):
        from handlers.auth_handler import link_account

        event = _make_event(
            body={"provider": "google", "auth_code": "CODE"}
        )
        status, body = _parse_response(
            link_account(event, _CONTEXT)
        )

        assert status == 401
        assert body["error_code"] == "UNAUTHORIZED"

    def test_missing_provider_returns_400(self, aws_mock):
        from handlers.auth_handler import (
            link_account,
            anonymous_login,
        )

        # Create a player first to get a valid JWT.
        login_event = _make_event(
            body={"device_id": "link-test-device"}
        )
        _, login_body = _parse_response(
            anonymous_login(login_event, _CONTEXT)
        )

        event = _make_event(
            body={"auth_code": "CODE"},
            headers={
                "Authorization": (
                    f"Bearer {login_body['jwt_token']}"
                )
            },
        )
        status, body = _parse_response(
            link_account(event, _CONTEXT)
        )

        assert status == 400
        assert body["error_code"] == "MISSING_PARAMS"

    def test_successful_link(self, aws_mock):
        from handlers.auth_handler import (
            link_account,
            anonymous_login,
        )
        from services.auth_service import AuthResult

        # Create anonymous player.
        login_event = _make_event(
            body={"device_id": "link-test-device-2"}
        )
        _, login_body = _parse_response(
            anonymous_login(login_event, _CONTEXT)
        )

        mock_result = AuthResult(
            provider="google",
            provider_id="google_new_123",
            display_name="GoogleUser",
        )

        with patch(
            "handlers.auth_handler.auth_service"
        ) as mock_auth:
            mock_auth.authenticate = AsyncMock(
                return_value=mock_result
            )
            mock_auth.jwt_secret = TEST_JWT_SECRET

            event = _make_event(
                body={
                    "provider": "google",
                    "auth_code": "VALID_CODE",
                    "redirect_uri": "http://127.0.0.1:9876",
                },
                headers={
                    "Authorization": (
                        f"Bearer {login_body['jwt_token']}"
                    )
                },
            )
            status, body = _parse_response(
                link_account(event, _CONTEXT)
            )

        assert status == 200
        assert body["status"] == "success"

    def test_provider_conflict_returns_409(self, aws_mock):
        from handlers.auth_handler import (
            link_account,
            anonymous_login,
        )
        from services.auth_service import AuthResult
        from services.provider_mapping_service import (
            ProviderMappingService,
        )

        # Create two anonymous players.
        _, body1 = _parse_response(
            anonymous_login(
                _make_event(
                    body={"device_id": "conflict-dev-1"}
                ),
                _CONTEXT,
            )
        )
        _, body2 = _parse_response(
            anonymous_login(
                _make_event(
                    body={"device_id": "conflict-dev-2"}
                ),
                _CONTEXT,
            )
        )

        # Pre-link Google to player 1.
        pms = ProviderMappingService()
        asyncio.run(
            pms.create(
                "google",
                "google_conflict",
                body1["player_id"],
            )
        )

        mock_result = AuthResult(
            provider="google",
            provider_id="google_conflict",
            display_name="ConflictUser",
        )

        with patch(
            "handlers.auth_handler.auth_service"
        ) as mock_auth:
            mock_auth.authenticate = AsyncMock(
                return_value=mock_result
            )
            mock_auth.jwt_secret = TEST_JWT_SECRET

            event = _make_event(
                body={
                    "provider": "google",
                    "auth_code": "CODE",
                },
                headers={
                    "Authorization": (
                        f"Bearer {body2['jwt_token']}"
                    )
                },
            )
            status, body = _parse_response(
                link_account(event, _CONTEXT)
            )

        assert status == 409
        assert body["error_code"] == "PROVIDER_CONFLICT"
