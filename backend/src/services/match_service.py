"""Match service for recording results and querying stats."""

import math
import os
from datetime import datetime
from decimal import Decimal
from typing import Any, Optional

import boto3
from boto3.dynamodb.conditions import Key


# Elo rating constants.
_ELO_K = 32
_ELO_FLOOR = 100

# Leaderboard defaults.
_DEFAULT_LEADERBOARD_LIMIT = 50
_MAX_LEADERBOARD_LIMIT = 100

# Match history defaults.
_DEFAULT_HISTORY_LIMIT = 20


class MatchService:
    """DynamoDB operations for match results and leaderboards."""

    def __init__(self):
        self.dynamodb = boto3.resource("dynamodb")
        self.players_table_name = os.environ.get(
            "PLAYERS_TABLE", "hopnbop-players"
        )
        self.history_table_name = os.environ.get(
            "MATCH_HISTORY_TABLE", "hopnbop-match-history"
        )
        self.players_table = self.dynamodb.Table(
            self.players_table_name
        )
        self.history_table = self.dynamodb.Table(
            self.history_table_name
        )

    def record_match_result(
        self,
        game_session_id: str,
        match_duration_sec: float,
        level_id: str,
        player_results: list[dict],
    ) -> None:
        """Record match results for all players.

        Writes one match history item per player and
        atomically updates each player's stats.
        """
        now = int(datetime.now().timestamp())
        player_count = len(player_results)

        # Calculate average rating for Elo.
        ratings = []
        for pr in player_results:
            player = self.players_table.get_item(
                Key={"player_id": pr["player_id"]},
                ProjectionExpression="rating",
            )
            item = player.get("Item", {})
            ratings.append(int(item.get("rating", 1500)))

        avg_rating = (
            sum(ratings) / len(ratings) if ratings else 1500
        )

        # Write match history and update stats per player.
        for i, pr in enumerate(player_results):
            player_id = pr["player_id"]
            is_win = pr["rank"] == 1
            player_rating = ratings[i]
            rating_delta = self._calculate_rating_delta(
                player_rating, avg_rating, is_win
            )

            # Write match history item.
            self.history_table.put_item(
                Item={
                    "player_id": player_id,
                    "match_timestamp": now,
                    "game_session_id": game_session_id,
                    "level_id": level_id,
                    "match_duration_sec": Decimal(
                        str(round(match_duration_sec, 1))
                    ),
                    "rank": pr["rank"],
                    "player_count": player_count,
                    "score": pr.get("score", 0),
                    "kill_count": pr.get("kill_count", 0),
                    "death_count": pr.get("death_count", 0),
                    "bump_count": pr.get("bump_count", 0),
                    "crown_time_sec": Decimal(
                        str(
                            round(
                                pr.get("crown_time_sec", 0),
                                1,
                            )
                        )
                    ),
                    "regicide_count": pr.get(
                        "regicide_count", 0
                    ),
                    "is_win": is_win,
                }
            )

            # Atomically update player stats.
            win_expr = (
                "wins = wins + :one"
                if is_win
                else "losses = losses + :one"
            )
            new_rating = max(
                _ELO_FLOOR, player_rating + rating_delta
            )
            self.players_table.update_item(
                Key={"player_id": player_id},
                UpdateExpression=(
                    f"SET matches_played ="
                    f" matches_played + :one,"
                    f" {win_expr},"
                    f" rating = :new_rating,"
                    f" last_active = :now,"
                    f" rating_partition = :all"
                ),
                ExpressionAttributeValues={
                    ":one": 1,
                    ":new_rating": new_rating,
                    ":now": now,
                    ":all": "all",
                },
            )

    def get_recent_matches(
        self,
        player_id: str,
        limit: int = _DEFAULT_HISTORY_LIMIT,
    ) -> list[dict]:
        """Query recent match history for a player."""
        response = self.history_table.query(
            KeyConditionExpression=Key("player_id").eq(
                player_id
            ),
            ScanIndexForward=False,
            Limit=limit,
        )
        items = response.get("Items", [])
        # Convert Decimal to float/int for JSON.
        return [self._convert_decimals(item) for item in items]

    def get_leaderboard(
        self,
        limit: int = _DEFAULT_LEADERBOARD_LIMIT,
    ) -> list[dict]:
        """Query top players by rating."""
        capped_limit = min(limit, _MAX_LEADERBOARD_LIMIT)
        response = self.players_table.query(
            IndexName="rating-index",
            KeyConditionExpression=Key(
                "rating_partition"
            ).eq("all"),
            ScanIndexForward=False,
            Limit=capped_limit,
            ProjectionExpression=(
                "player_id, display_name, rating,"
                " matches_played, wins, losses"
            ),
        )
        items = response.get("Items", [])
        result = []
        for rank, item in enumerate(items, start=1):
            result.append(
                {
                    "rank": rank,
                    "player_id": item["player_id"],
                    "display_name": item.get(
                        "display_name", ""
                    ),
                    "rating": int(item.get("rating", 1500)),
                    "matches_played": int(
                        item.get("matches_played", 0)
                    ),
                    "wins": int(item.get("wins", 0)),
                    "losses": int(item.get("losses", 0)),
                }
            )
        return result

    def get_player_rank(
        self, player_id: str, rating: int
    ) -> int:
        """Count players with rating higher than given value.

        Returns 1-based rank.
        """
        response = self.players_table.query(
            IndexName="rating-index",
            KeyConditionExpression=(
                Key("rating_partition").eq("all")
                & Key("rating").gt(rating)
            ),
            Select="COUNT",
        )
        return response.get("Count", 0) + 1

    @staticmethod
    def _calculate_rating_delta(
        player_rating: int,
        avg_opponent_rating: int,
        is_win: bool,
    ) -> int:
        """Calculate Elo rating change.

        Uses standard Elo formula with K=32.
        """
        expected = 1.0 / (
            1.0
            + math.pow(
                10,
                (avg_opponent_rating - player_rating)
                / 400.0,
            )
        )
        actual = 1.0 if is_win else 0.0
        return round(_ELO_K * (actual - expected))

    @staticmethod
    def _convert_decimals(
        item: dict,
    ) -> dict:
        """Convert Decimal values to int or float."""
        result = {}
        for key, value in item.items():
            if isinstance(value, Decimal):
                if value == int(value):
                    result[key] = int(value)
                else:
                    result[key] = float(value)
            else:
                result[key] = value
        return result
