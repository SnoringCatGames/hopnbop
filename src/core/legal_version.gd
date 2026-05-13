class_name LegalVersion
extends Object
## Game-side legal-consent version tracking.
##
## The platform addon's `PlatformAuthTokenStore` (Stage 6.3) is
## game-agnostic and no longer carries a hardcoded legal version —
## different games may publish different terms/privacy/data-deletion
## texts and so need different consent versions. This file owns the
## game's compile-time fallback and the resolver that prefers the
## runtime-reported value.

## Compile-time fallback for the legal-consent version. The
## authoritative value comes from `games.legal.legal_version` and
## is delivered to the client via the runtime's `version_check`
## RPC (cached at `G.backend_api_client.server_legal_version`).
## Callers should use `get_current()` instead of referencing this
## constant directly so they pick up server-side bumps without a
## client rebuild.
##
## Keep this constant aligned with `game.yaml`'s
## `legal.legal_version` so offline boots / pre-version-check
## flows present the right copy. CI doesn't currently guard this
## parity; a mismatch surfaces as the consent screen forcing a
## re-consent on first online boot, which is annoying but safe.
const LEGAL_VERSION := "1.1"


## Returns the legal-consent version the consent gate should
## check against. Prefers the runtime-reported value (game.yaml
## via version_check) and falls back to the compile-time
## constant when no version_check response has arrived yet.
static func get_current() -> String:
	# Safe to access G during the consent flow — global.gd
	# autoloads before any screen activates. The backend client
	# is created in _enter_tree, so it's always non-null here.
	# `server_legal_version` starts as "" and is populated on
	# the first successful check_version.
	if (is_instance_valid(G.backend_api_client)
			and not G.backend_api_client.server_legal_version
				.is_empty()):
		return G.backend_api_client.server_legal_version
	return LEGAL_VERSION
