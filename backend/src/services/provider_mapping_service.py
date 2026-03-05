"""Provider-to-player mapping service for multi-provider accounts."""

import os
import boto3
from typing import Optional


class ProviderMappingService:
    """Maps OAuth provider IDs to canonical player IDs.

    Each entry stores a composite key like "steam#76561198012345678"
    pointing to the canonical player_id ("p_a1b2c3d4e5f6").
    """

    def __init__(self):
        self.dynamodb = boto3.resource("dynamodb")
        self.table_name = os.environ.get(
            "PROVIDER_MAPPINGS_TABLE",
            "hopnbop-provider-mappings",
        )
        self.table = self.dynamodb.Table(self.table_name)

    @staticmethod
    def make_composite(provider: str, provider_id: str) -> str:
        """Build composite key from provider and provider ID."""
        return f"{provider}#{provider_id}"

    async def lookup(
        self, provider: str, provider_id: str
    ) -> Optional[str]:
        """Look up canonical player_id by provider.

        Returns player_id or None if not found.
        """
        composite = self.make_composite(provider, provider_id)
        response = self.table.get_item(
            Key={"provider_composite": composite}
        )
        item = response.get("Item")
        if item is None:
            return None
        return item["player_id"]

    async def create(
        self,
        provider: str,
        provider_id: str,
        player_id: str,
    ) -> None:
        """Create a provider-to-player mapping."""
        composite = self.make_composite(provider, provider_id)
        self.table.put_item(
            Item={
                "provider_composite": composite,
                "player_id": player_id,
            }
        )

    async def delete(
        self, provider: str, provider_id: str
    ) -> None:
        """Delete a provider mapping."""
        composite = self.make_composite(provider, provider_id)
        self.table.delete_item(
            Key={"provider_composite": composite}
        )
