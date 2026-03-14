"""Friends service for DynamoDB operations."""

import os
import boto3
from typing import List, Optional
from dataclasses import dataclass
from datetime import datetime


@dataclass
class FriendEntry:
    """A single friend relationship."""

    friend_id: str
    display_name: str
    source: str
    created_at: int


class FriendsService:
    """DynamoDB friends operations."""

    def __init__(self):
        self.dynamodb = boto3.resource("dynamodb")
        self.friends_table_name = os.environ.get(
            "FRIENDS_TABLE", "hopnbop-friends"
        )
        self.players_table_name = os.environ.get(
            "PLAYERS_TABLE", "hopnbop-players"
        )
        self.friends_table = self.dynamodb.Table(
            self.friends_table_name
        )
        self.players_table = self.dynamodb.Table(
            self.players_table_name
        )

    async def add_friend(
        self,
        player_id: str,
        friend_id: str,
        source: str = "friend_code",
    ) -> bool:
        """Add a bidirectional friend relationship.

        Returns True if the friend was added, False if
        already friends.
        """
        if player_id == friend_id:
            raise ValueError("Cannot add yourself as a friend")

        # Verify both players exist and neither is anonymous.
        player = self.players_table.get_item(
            Key={"player_id": player_id},
            ProjectionExpression="player_id, is_anonymous",
        )
        friend = self.players_table.get_item(
            Key={"player_id": friend_id},
            ProjectionExpression="player_id, is_anonymous",
        )
        if "Item" not in player:
            raise ValueError("Player not found")
        if "Item" not in friend:
            raise ValueError("Friend not found")
        if player["Item"].get("is_anonymous", False):
            raise ValueError(
                "Anonymous players cannot add friends"
            )
        if friend["Item"].get("is_anonymous", False):
            raise ValueError(
                "Cannot add an anonymous player as a friend"
            )

        # Check if already friends.
        existing = self.friends_table.get_item(
            Key={
                "player_id": player_id,
                "friend_id": friend_id,
            },
            ProjectionExpression="player_id",
        )
        if "Item" in existing:
            return False

        now = int(datetime.now().timestamp())

        # Write both directions.
        with self.friends_table.batch_writer() as batch:
            batch.put_item(
                Item={
                    "player_id": player_id,
                    "friend_id": friend_id,
                    "source": source,
                    "created_at": now,
                }
            )
            batch.put_item(
                Item={
                    "player_id": friend_id,
                    "friend_id": player_id,
                    "source": source,
                    "created_at": now,
                }
            )

        return True

    async def remove_friend(
        self,
        player_id: str,
        friend_id: str,
    ) -> None:
        """Remove a bidirectional friend relationship."""
        with self.friends_table.batch_writer() as batch:
            batch.delete_item(
                Key={
                    "player_id": player_id,
                    "friend_id": friend_id,
                }
            )
            batch.delete_item(
                Key={
                    "player_id": friend_id,
                    "friend_id": player_id,
                }
            )

    async def list_friends(
        self, player_id: str
    ) -> List[FriendEntry]:
        """List all friends for a player."""
        response = self.friends_table.query(
            KeyConditionExpression=(
                boto3.dynamodb.conditions.Key("player_id")
                .eq(player_id)
            ),
        )

        friend_ids = [
            item["friend_id"] for item in response["Items"]
        ]
        if not friend_ids:
            return []

        # Batch-get display names from PlayersTable.
        keys = [
            {"player_id": fid} for fid in friend_ids
        ]
        batch_response = self.dynamodb.batch_get_item(
            RequestItems={
                self.players_table_name: {
                    "Keys": keys,
                    "ProjectionExpression": (
                        "player_id, display_name"
                    ),
                }
            }
        )

        name_map = {}
        for item in batch_response.get(
            "Responses", {}
        ).get(self.players_table_name, []):
            name_map[item["player_id"]] = item.get(
                "display_name", ""
            )

        entries = []
        for item in response["Items"]:
            fid = item["friend_id"]
            entries.append(
                FriendEntry(
                    friend_id=fid,
                    display_name=name_map.get(fid, ""),
                    source=item.get("source", ""),
                    created_at=int(
                        item.get("created_at", 0)
                    ),
                )
            )

        return entries

    async def delete_all_friends(
        self, player_id: str
    ) -> None:
        """Delete all friend relationships for a player.

        Used for GDPR account deletion. Removes both
        directions for every friend.
        """
        friends = await self.list_friends(player_id)

        with self.friends_table.batch_writer() as batch:
            for friend in friends:
                batch.delete_item(
                    Key={
                        "player_id": player_id,
                        "friend_id": friend.friend_id,
                    }
                )
                batch.delete_item(
                    Key={
                        "player_id": friend.friend_id,
                        "friend_id": player_id,
                    }
                )

    async def get_friends_data_for_export(
        self, player_id: str
    ) -> List[dict]:
        """Get friends data for GDPR export."""
        friends = await self.list_friends(player_id)
        return [
            {
                "friend_id": f.friend_id,
                "display_name": f.display_name,
                "source": f.source,
                "created_at": f.created_at,
            }
            for f in friends
        ]
