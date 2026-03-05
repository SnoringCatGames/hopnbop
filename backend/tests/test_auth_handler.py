"""Tests for auth_handler.py - Lambda endpoint handlers."""

import json
import asyncio
from unittest.mock import patch, AsyncMock, MagicMock

import pytest

from services.auth_service import AuthResult, AuthToken
from tests.constants import TEST_JWT_SECRET
from tests.conftest import mock_httpx_client, make_response


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
    return {
        "body": json.dumps(body) if body else "{}",
        "headers": headers or {},
    }


def _parse_response(response):
    """Parse status code and body from Lambda response."""
    return response["statusCode"], json.loads(response["body"])


# =====================================================================
# POST /auth/login
# =====================================================================


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
        """Login with a mocked provider. Exercises the full
        handler flow including provider mapping, player
        creation, and token issuance."""
        from handlers.auth_handler import login

        # Mock only the external HTTP call, not the whole
        # auth_service. This lets the handler exercise real
        # token creation and DB writes.
        auth_resp = make_response(200, {
            "response": {
                "params": {"steamid": "steam_login_test"}
            },
        })
        user_resp = make_response(200, {
            "response": {
                "players": [{"personaname": "LoginPlayer"}]
            },
        })

        with mock_httpx_client([auth_resp, user_resp]):
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
        assert body["player_id"].startswith("p_")
        assert body["is_anonymous"] is False
        assert body["display_name"] == "LoginPlayer"

    def test_returning_player_gets_same_id(self, aws_mock):
        from handlers.auth_handler import login

        auth_resp = make_response(200, {
            "response": {
                "params": {"steamid": "steam_returning"}
            },
        })
        user_resp = make_response(200, {
            "response": {
                "players": [{"personaname": "Returner"}]
            },
        })

        with mock_httpx_client([auth_resp, user_resp]):
            event = _make_event(
                body={
                    "provider": "steam",
                    "auth_code": "TICKET",
                }
            )
            _, body1 = _parse_response(
                login(event, _CONTEXT)
            )

        # Login again with the same steam ID.
        auth_resp2 = make_response(200, {
            "response": {
                "params": {"steamid": "steam_returning"}
            },
        })
        user_resp2 = make_response(200, {
            "response": {
                "players": [{"personaname": "Returner"}]
            },
        })

        with mock_httpx_client([auth_resp2, user_resp2]):
            _, body2 = _parse_response(
                login(event, _CONTEXT)
            )

        assert body1["player_id"] == body2["player_id"]

    def test_auth_failure_returns_401(self, aws_mock):
        from handlers.auth_handler import login

        resp = make_response(403)

        with mock_httpx_client(resp):
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


# =====================================================================
# POST /auth/anon
# =====================================================================


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


# =====================================================================
# POST /auth/refresh
# =====================================================================


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
        # Refresh token must rotate (opaque random hex).
        assert (
            body["refresh_token"]
            != login_body["refresh_token"]
        )

    def test_old_refresh_token_invalid_after_rotation(
        self, aws_mock
    ):
        from handlers.auth_handler import refresh

        login_body = self._create_player_with_token()
        old_refresh = login_body["refresh_token"]

        # First refresh succeeds and rotates.
        event = _make_event(
            body={
                "player_id": login_body["player_id"],
                "refresh_token": old_refresh,
            }
        )
        status, _ = _parse_response(refresh(event, _CONTEXT))
        assert status == 200

        # Second refresh with the old token fails.
        status, body = _parse_response(refresh(event, _CONTEXT))
        assert status == 401
        assert body["error_code"] == "INVALID_REFRESH"


# =====================================================================
# POST /auth/link
# =====================================================================


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
