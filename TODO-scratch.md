# TODO scratch

Levi's manual notes, moved verbatim from the top of
`addons/rollback_netcode/core/frame_driver.gd` on 2026-10-14. The fence
only keeps Markdown from rendering the `#` lines as headings. Triage and
a suggested order: `docs/design/H37_systems_audit.md`.

```text
# FIXME: LEFT OFF HERE: Main list: --------------------------------------------

# ---


# - Getting the crown that changes bunny color.
# - Dying shows player sprite blink briefly at level origin.
# - Respawning after dying in water shows splash animation at bad position at spawn time.
# - I want to update the player display card to show the resting bunny sprite for the player. Let's show it next to the player profile image.
# - Bunnies aren't hitting springs when invincible (they should).
# - I just updated to godot 4.7.2. Research whether there's anything worth changing in our projects accordingly.


# - play offline; end match; play again
# - Also, colors not working offline
# - Add alt+enter to scaffolder, bootstrapper, and hop-n-bop
# - Change the rainbow transition effect of the gore to be a random sequence from a set of predefined sequences.
# - And start at a random offset.
# - Make the sprites white


# - Implement the big refactor to generalize multi-game architecture:
# C:\Users\lsl\.claude\plans\in-general-i-ve-been-snoopy-pearl.md

# - Test the new warm-up logic.
#   - Test the warming-up label in the lobby.
#   - Test the warming-up label in the loading screen.
#   - Test that warming-up actually ends at the right amount of time.
#   - Test that warming-up isn't needed after 15 minutes.
#   - Test that warming-up IS needed after 45 minutes.

# - Finish working on the foobar image.
#   - Reducing in-between shades.
#   - Cleaning up rough shapes.

# - Fix level_0 art.
#   - More detailed version.
#   - Remove any sky blue color from the occlusion layer.

# - FIX REMOTE PLAYER ANIMATION GLITCHES

# - Don't use Google or Apple account usernames! That's not something players want to expose.

# Image prompts:
# - level_0:
# Add more texture and shading to rocks, dirt, and sand. Keep the border rocks gradually transitioning out to a solid color. Add more vegetation. Make the background clouds and mountains a bit more interesting, but also still faded.
# - level_4, with level_0 fixed-up as a reference:
# This image uses placeholder dirt, rock, sand, and ice tiles. Please add a lot more variation to their textures and tile-interior shapes. Also add more texture and shading to rocks, dirt, and sand. Also add moss to rocks. Keep the border rocks gradually transitioning out to a solid color. Also add grass and vegetation. Make the background clouds and mountains a bit more interesting, but also still faded.


# Give shape, texture, and shading to these placeholder rock, dirt, and grasse regions. Also add moss to rocks. Keep the border rocks gradually transitioning out to a solid color.

# Add grass and vegetation. Make the background clouds and mountains a bit more interesting, but also still faded.


# Platformer level.
# Border made of rough natural stone and rocks. Dark gray and brown stone with cracks, moss, and subtle lighting. The rocks gradually transition from detailed textured stone on the inside edge to a solid dark gray color on the outer edge.
# Grass and dirt platforms on tree branches have rich brown soil with visible layers, small pebbles, and root textures, with bright green grass tufts on top with varied heights, with occasional small yellow wildflowers, and with warm natural lighting.
# Sand platforms have yellow sand with visible layers and a grainy texture, with thick somewhat viney grass-like vegetation, with occasional bright red flowers.
# Background has soft blue sky with layered fluffy white clouds at different heights. Faded blue-purple mountain silhouettes in the distance with subtle snow caps and ridgelines. Atmospheric perspective with lighter colors further away. Dreamy, serene mood.


### PROMPT FOR MAIN LAYER:
# - First, remove the decoration/occlusion layer.
# Add more texture and shading to rocks, dirt, and sand. Keep the border rocks gradually transitioning out to a solid color. Add more moss to rocks. Make the background a bit more interesting, but also still faded. Keep colors across the level bright.

### PROMPT FOR DECORATION/OCCLUSION LAYER:
# - First, remove the background, and platform support layers.
# Add more texture and shading to rocks, dirt, and sand. Keep the border rocks gradually transitioning out to a solid color. Add more moss to rocks. Add more vegetation. Keep colors across the level bright.


# - Test repsonsive layout with PlayerDisplay list.
# - Test friends presence tracking.
# - Test everything with anonymous users.
# - Test party matchmaking.
# - Test play again.
# - Stats screen...
# - Test sometimes being able to stand on players if approaching from an angle.
# - Test leaderboard screen.

# Spring jump is still broken sometimes
# Improve level0 art.
# Add level5 art.
# Add level4 art.
# Player overhead labels are not at all centered over the players. And They are inconsistent on different clients.

# Let's fix the leaderboard screen.
# - It should use the same patterns as other UIs and screens.
#   - It should be a proper registered Screen type.
#   - It should have a vertical list of horizontal rows/buttons for interactions.
#   - It should have a close button with the x icon at the bottom.
#   - It should also support closing with X (which it currenty states that it supports, but it is broken).
# - Also, we should double the font size.
# - Also, in general, we should not include anonymous players in leaderboard rankings.
# - Also, what is "filter" supposed to mean?
# - Also, what is "tab" supposed to do?
# - Also, what is the number in parens after "Your rank:"?

# Let's fix the friends panel.
# -

# - Test one client replays and the other doesn't.

# - Test trying to login on two devices at the same time for a given player. Also prevent at matchmaking time.

# - Test players disconnecting:
#   - Should be removed from match.
#   - If one player remains, match ends, they "Wins by default".
#   - Disconnected players should lose in the game-over screen.
#   - If all other _clients_ disconnect during matchmaking, the remaining client should go back to the lobby.

# - Fix crossplay auth.

# - Test/fix party formation, matchmaking, and lobbying
#   - The panel UI?
#   - Matchmaking
#   - Forming
#   - Disbanding
#   - Who gets control?

# ---

# - Check what's next for Steam and Epic Games.
#   - Get Alden and Ben added as testers.

# - Set up Android build.

# - Set up iOS build.

# - Test local mode.

# - Add additional delay or whatever it takes to ensure the snore sound plays on the SCG screen.

# - Check that we trigger sfx on all button clicks.

# - Polish
#   - credits screen
#   - game over screen
#   - friends panel
#   - leaderboard screen
#   - all other side-panel UI
#   - Consent screen
#   - Auth screen
#   - Toast
#     - Background opacity
#     - Alert icon
#   - Loading screen.
# - Look for:
#   - Icons
#   - L/R interactions
#   - Spacing
#   - Should we add images anywhere?

# - Test offline mode.

# - Test with a controller.

# - Should we include copies of legal docs in-game?
#   - Is it sufficent to have them online only?
#   - What if the user doesn't have an internet connection?

# I believe AWS has a $100 free for new accounts deal. I believe they also mentioned an additional $100 if you meet some requirements. What are those requirements and what would we need to do? Check what I've already done in my AWS account.


# Tasks to perform when releasing a new version.
# - Carefully survey the entire codebase.
#   - Make sure all displayed text is properly connected to i18n, and ensure each supported language has correct translations for each piece of text.
#   - Ensure we bump all version references to the correct values.
#   - Ensure we reset all Settings flags to release values.
#   - Ensure all legal documents are up-to-date and cover any recent changes.
#   - Ensure all RPCs use appropriate channels.
#   - Ensure all log/print/verbose/warning/error statements go through a utility in G or Netcode, use the correct category tag, and are guarded in an if-statement on Netcode.log.is_verbose if they are verbose.
#   -


# - Check whether there is a hard billing limit on AWS, or if it just alerts at the thresholds.


# Ideally, if we have a large enough player pool to choose from, we'd try to pair players together into a match according to their relative skill/rank levels. Is that feasible to add?


# ---

# - Tell Claude no. The jitter is, I think, because the remote players input is stale. Or maybe velocity?
# We just didn't see constant rubber banding like this, since rollback is based off past frames and so the current frame shouldn't regress backward!
# .... Extrapolating forward.
# ASK IN A NEW SESSION
# I wonder if this relates to our use of three state nodes. That third node...


# ---


# All M3 code changes are complete. The remaining items are:
# - Godot client test — Connect from the game client to the live fleet, play a match, verify match results post to backend
# - Dockerfile WebSocket port — The plan mentioned adding port 4434/tcp, but this is deferred to M10 (web builds)


# Remaining items for end-to-end testing:
# - hopnbop/server-api-key secret needs to be set as a fleet environment variable if the server posts match results to the backend API
# - Client-side testing - connect a client, trigger matchmaking, verify a game session is created and playable
# - PlayerInputNetworkState class resolution error - non-blocking but should be investigated for the export/pck


# Remaining notes:
# - The server API key needs to be set as a GameLift fleet environment variable (server_api_key) so game servers can read it via G.settings.server_api_key
# - Existing player records won't appear on the leaderboard until they play a match or log in again (they lack rating_partition = "all")
# - The lobby podium object was deferred (needs art assets)


# - Update Google Oauth (and facebook?) to have privacy and TOS links: https://console.cloud.google.com/auth/branding?authuser=2&project=hop-n-bop


# ---


# - Get in water. Die. Respawn with a splash somewhere.


# - Look into the additional $100 from AWS.


# - https://discord.com/channels/1478592423813845106/1478592423813845109

# - Fix Snoring Cat online presence:
#   - Fix and republish Inner-Tube Climber.
#   - Update snoringcat.games.

# ---

# - Review gamelift GDScript, backend, python, audit all AWS activity and used systems, website pages, etc.

# - Add tooltips, with localized text, with translations in all supported languages, to each button in the app.
#   - Update Memory.md or Claude.md to mention including tooltips for all buttons.

# ---


# - Work with Claud on the BIG final plans.
# Milestones:
# - M1: AWS Account & Infrastructure Foundation
# - M2: Complete Auth Flow
# - M3: GameLift Container Fleet Deployment
# - M4: Legal & Compliance
# - M5: Monitoring, Logging & Alerting
# - M6: Matchmaking Enhancements
# - M7: Database & Player Persistence
# - M8: Leaderboards
# - M9: Friends System
# - M10: Web Build & Cross-Play
# - M11: Offline Mode / Local Multiplayer
# - M12: Mobile Builds
# - M13: CI/CD & Deployment Automation
# - M14: Website (hopnbop.net)
# - M15: Client Polish & Remaining Items


# ## Manual Setup Checklist (One-Time)
# ### Platform Accounts
# - [x] AWS account (Snoring Cat LLC billing)
# - [ ] Steam developer account (Steamworks, $100 app fee)
# - [ ] Apple Developer account ($99/year)
# - [ ] Google Play Console ($25 one-time)
# - [ ] Epic Games Store developer account (free)
# - [ ] Google Cloud Console project (for OAuth, free tier)
# - [ ] Discord developer application (free)
# - [ ] Twitch developer application (free)
# - [ ] itch.io project for Hop 'n Bop (already have account)
# ### AWS Infrastructure
# - [x] IAM admin user with MFA
# - [ ] AWS CLI configured locally
# - [ ] SAM CLI installed
# - [ ] Secrets Manager: JWT signing key
# - [ ] Secrets Manager: OAuth client secrets (6 providers)
# - [ ] SNS topic for alarms, email subscription confirmed
# - [ ] S3 bucket for hopnbop.net
# - [ ] CloudFront distribution
# - [ ] Route 53 hosted zone
# - [ ] ACM SSL certificate
# - [ ] ECR repository for server containers
# - [ ] GameLift container fleet
# - [ ] GameLift Anywhere fleet (for local dev)
# - [ ] DynamoDB PITR enabled on all tables
# - [ ] AWS Budgets alerts ($25, $50, $100)
# - [ ] CloudWatch dashboard
# ### Local Development
# - [ ] Docker installed (for container builds)
# - [ ] butler CLI installed (for itch.io uploads)
# - [ ] Xcode installed on Mac (for iOS builds)
# - [ ] Android SDK installed (for Android builds)
# ### Legal
# - [ ] Privacy policy drafted and hosted
# - [ ] Terms of service drafted and hosted
# - [ ] Data deletion policy drafted and hosted
# - [ ] Age gate (13+) implemented in client
# ### CI/CD
# - [ ] GitHub secrets configured (AWS keys, itch.io key, etc.)
# - [ ] `release` branch created with protection rules
# - [ ] All deployment workflows tested with manual dispatch first


# ---


# /Make my image more resemble the reference. I want rectangular blocks that aren't exactly aligned with the tile grid. I want some brown dirt/wood blocks, some yellow sandy blocks, some gray stone blocks, some ice blocks. Grass should be on the tops of all non-stone blocks. There should be some running falling water and a pool. Omit the butterflies and flies.
# /I've made this level using a tileset. I now want to replace it with bespoke art--no repeating tiles. Also, I want to replace most of the interior "stone" art with wood/dirt art. And some sandy art in some of the platforms on the left side of the screen. Also, I want a small trickle flowing into the pool from the middle of the floating platform that's directly above it. Replace the "ice" tiles with a transparent ice-cube aesthetic.
#
# This is a level for a 2D platformer, using a tileset with repeating tiles. I want to replace it with bespoke art across the entire level. I want to carefully preserve the overall geometry of the platforms and walls. I want tall stone columns on the outer sides. I want to still have some stone comprising some bottom parts of some platforms, but more dirt and wooden stump parts as well. Also, I want most of the platforms in the left half to incorporate sandy parts instead of wood/dirt parts. Also, I want a tiny trickle water fall falling into the bottom-left-corner pool from the wide platform that's directly above it. Also, I want to replace the "icy" parts with transparent ice-cube aesthetics.
# Great. Now, I see the water falls in two parts. Have the second part fall from the platform on the left, rather than the one on the right. The water can pool/flow horizontally slightly to reach the preexisting lower waterfall part. Let's replace all the stump parts with dirt parts. Let's lighten up the tone a lot. This should be more of a sunny woodland glade than a gloomy cave. Some of the ice on the right half doesn't exactly match the tiles from the base image--make sure they do. Let there be more transition and merging between dirt/sand and stone, so a given "tile" is more likely to have a bit of both, with stone usually below sand/dirt. Also, allow for a tiny bit of deviation around "tile" edges, so they can stick out a bit more beyond the gridlines.

# Review all tests. Also look for test slop.

# Get CI working again.


# Ask AI where auth fits into the current backend and GameLift logic. This was originally planned.

# Web-client support:
# - Ask if WebSockets or WebRTC make more sense for web.
# - Ask if enabling network support for web clients would make it more worthwhile to have a slower network frame rate than physics frame rate.

# Update the loading-screen text to indicate the current match-connecting status:
# - Finding other players...
# - Connecting to server...
# - Auth?


# ---

# - Make player annotations skinnier.

# - Do research for better AI art tools.
# - Look into whether there are plugins for krita or photoshop.
# - Look into whether anything supports lasso tools for targeted updates.
# - Then, make art for level with this first, and convert to pixel art second.

# - Make a level editor for the game.
# - Support a finite set of tile shapes.
# - Support half tile sizes.
# - Support slopes. 1/1 and 1/2
# - Support two modes: tile set (given a custom template they upload), or a single whole-level image.
# - There'd actually need to be three images. Main layer, background, foreground.
# - Ask AI to help think through content moderation with custom art...

# - Make a bunny level with clouds (in the cloud!)


# ---

# - Implement bespoke art for one level to test the process.
#   - Use PixelLab for generating bespoke backgrounds and foregrounds and occlusion decorations layer for each level, given tilemap layouts to start from.
#   - Also implement occlusion art at this point.
#   - Also implement foreground/background art responsive animations at this point.


# ---


# - Add bespoke art for each level, rather than tile sets. Or, at least, try
#   this for one level.
#   - MAKE SURE THIS PLAN ACCOUNTS FOR THE TILE-ANIMATION PLAN!
# - DEFINITELY add decoration/occlusion art to scatter around in each level
#   (with our without tile set versions of levels)

# Interactive animated tiles behind and in front:
# - MAKE SURE THIS PLAN ACCOUNTS FOR THE BESPOKE-ART-PER-LEVEL PLAN.
# - Research how to implement animated tiles.
# - Have Tile set point to a scene for each animated tile.
# - ALSO, plan a way to sync occlusion and background animated tiles, so
#   rustling one will also trigger the other.
# - Probably implement this by subclassing the TileMap. Then have a property to
#   indicate its partner TileMap, and assert it's set.
# - Then, need to figure out collisions for an offset area for these rustle tiles.
# - Then...


# ---

# - Make bespoke art for the web loading screen.
#   - This should be inspired by the level art.

# ---


# - Review /rollback_netcode/examples/.
# - Look at how some old Scaffolder utilities are used, like ScaffolderTime.
#   Should we simplify and replace them with built-in logic that we _don't_ have
#   the consumer app worry about?


# - Lingering FIXMEs.

# - Ask for targeted reviews of important files/systems:
#   - Player
#   - Critters
#   - Gore manager
#   - UI
#   - GameLift and matchmaking
#   - ...


# - Ask for a security review of EVERYTHING.


#######################################################
# Docs and devlog articles

# Nakama
# Gamelift
# Agones
# Shockbyte
# P2Pdistributedauthorityvsserverauthority(don't want players to have to know about port forwarding!)
# I don'tusetheMonoversionofGodot, and IamprettycomfortablemodifyingtheGodotenginelogic and writingGDExtensionlogic, soIoptedtousetheC + +APIs.
# Estimatedtocostaround$10 / monthwithlowusage.(gofindthecalculatoragain, and sharespecifics, and alink)

# Reply here also: https://www.reddit.com/r/godot/comments/hlx9xl/should_i_use_aws_gamelift_or_some_alternate/

# Before posting anything, collect some actual metrics:
# - My load
# - My tests
# - My costs
# - My hours to implement

# Publish the Gamelift plugin as a GDExtension??

# Talk about how it compares with Unreal (and MHS)
# Talk about how the Godot API setup feels, and how the GameLift deployment feels.
# Talk about how much time I spent researching both parts

# Talk about time spent researching vs implementing

# Post this a bit after the jam--after fully testing the framework, and having a good demo to point to (and with polished debug visualizations!)

# List important aspects of system
# Interactions and last-time records
# Some are rollbackable (like jumps) some are not (like death)
# For two reasons, snappier responses and simpler reconciliation logic, we make some not rollbackable.
# To be specific, it's the _onset_ of an interaction period that's not rollbackable--that is, the first frame that the new interaction appears in (though l, we actually check this by considering the last_ingeraction_frame_index, in case we have multiple instances of the same interaction in sequence). Non-onset frames of a non-rollbackable interaction can be rolled back
# [Diagram]
# Explain rollbacks in general
# Explain fast forwards (only on client)

# _I_ should write the docs, so I can remember better later

# -----

# The technique is most commonly called "dynamic input delay" or "dynamic input latency" in the game networking community. It's sometimes also referred to as "adaptive input delay."

# What it is
# The idea is to intentionally buffer local player input by N frames before injecting it into the simulation (while still transmitting it immediately to peers). This shrinks the prediction window. The number of frames the remote side must predict and potentially roll back is reduced. The tradeoff is local responsiveness vs. remote visual smoothness.

# Key references
# The best writeup is Ryan Juckett's INVERSUS article, where he calls it "Dynamic Input Latency":

# The system measures the worst peer frame lag (averaged over 100 frames) and adjusts the local delay using a state machine
# Fast connections: 0 frames of local lag, allowing a few frames of remote prediction
# Worsening connections: adds local lag to slow down how fast remote prediction grows
# Caps at 4 frames of local lag (anything beyond was too unpleasant)
# This complements INVERSUS's 20-frame rollback window
# SnapNet describes a tiered approach: the first 50ms of latency is absorbed by input delay, prediction handles 50-150ms, and beyond 150ms more input delay is added. They frame it as a balance between prediction and input delay.

# The general principle
# In pure rollback with 0 input delay, the remote side must predict N frames where N = one-way latency in frames. Every misprediction requires rollback + re-simulation. By adding K frames of input delay locally, the remote prediction window shrinks to N-K frames, reducing rollback frequency and visual glitches at the cost of K frames of local input lag.

# Sources:

# Rollback Networking in INVERSUS – Hypersect (http://blog.hypersect.com/rollback-networking-in-inversus/)
# Rollback Networking in INVERSUS – Game Developer (https://www.gamedeveloper.com/design/rollback-networking-in-inversus)
# Netcode Architectures Part 2: Rollback – SnapNet (https://www.snapnet.dev/blog/netcode-architectures-part-2-rollback/)
# GGPO – Wikipedia (https://en.wikipedia.org/wiki/GGPO)

#######################################################


# ---


# Make a list of sound requests for Alden. Will need to decide on theme/vibe first. Different music per level? Different art per level?
# - Fly sfx needs two components:
#   - One is very positional. Oyr represents where it is relatively and how far.
#   - The other is not positional, but it's stronger based on how close and how
#     many. This one needs to have each individual bzzz have a lot of motion
#     with panning.
#   - Need to calculate a strength and relative position score based on the
#     relative positions of ALL flies in the level

# NOW is probably the time to document every aspect of the networking systems, what they do, why, pros and cons, ask AI to help, look at what .md files already exist, all to draft a particular collection of devlog posts, first deciding on main sections and bullets, then I approve, then draft them. GameLift, backend, auth, and other bits of networking not related to gameplay. Then all the gameplay bits
#  (What is lock step again??)

# After publishing devlog post, add links to code to the post, to provide more detailed explanations with visuals.


# ---

# Publish to the AssetLibrary a plugin for client prediction

# Publish to the AssetLibrary a GDExtension for GameLift integration?

# **** Re-enable the `Build GDExtension` GitHub Actions Workflow

# ---


# Add support for a local-only mode.

# Check on how the GitHub Actions current daily actions setup is working.

# Make a new GitHub action for deploying releases.
# - First, I should start using a dev branch for normal work, and merge into main whenever it's release-ready.
# - It should takie master branch and deploy it to itch and aws gamelift
# - It should also deploy to Godot Asset library.
# - It should also create zip files for the build and record them in the repo.
# - AND can it bump my versions for me?? Can it accept a text box for version? Can I tell it all the spots to update the version? Then I could put versions back in the READMEs...


# FIXME: Rollback debug visualization and networking improvements:
#
# Prompt:
# Review my notes and to create a plan for implementing them.
# Please flag any aspects that seem like a mistake or that don't make sense.
#
# ### PART 2: Editor plugin buffer-state debug UI
# - Add two Settings flags:
#   - is_network_pause_debug_shortcut_enabled
#   - is_network_rollback_state_buffer_debug_ui_visible
#     - If true, this will be automatically shown when the network is paused.
# - Create a custom editor plugin for showing a custom tab panel in the bottom
#   dock of the editor.
# - This panel will show all recent network buffer state.
# - When the server is not paused, the panel will just show a pause button.
# - When the server is paused, the panel will show all current buffer state, all
#   in one place.
# - Also, add a hotkey (ESC) to quickly trigger a pause at runtime.
#
# - Buffer UI parts:
#   - It's all one big grid, with uniform cell sizes.
#   - Frame index on horizontal axis.
#   - List of players and their state along the vertical axis.
#   - Each player should be collapsible, and is collapsed by default.
#   - The local player is always the top row (regardless of peer_id) and
#     is expanded by default.
#   - Each cell only renders a _DIFF_ from the previous cell!
#   - Also, each cell only renders a prefix of the state.
#   - However, each cell also includes a tooltip with complete details
#     (property name, unabridged labels, the diff, and the full current value).
#   - Each cell is also color-coded:
#     - Unchanged values show a "-" and are black.
#     - Changed values are blue.
#     - Missing networked state are grey.
#     - Cells representing values that triggered rollback are red.
#   - Also, color-code the frame index header cell for has-network-state (black),
#     no-network-state (grey), and triggered-rollback (red).
#
#   - While paused:
#     - The client then, only updates the debug UI 0.2 seconds after first
#       triggering pause, and whenever any new packed_state is received.
#
# ### PART 3: In-game buffer-state debug UI
# - Also, add a settings-toggleable in-game super-hud debug UI to render the
#   current buffer state when paused.
# - This UI should be interactable with the mouse!
# - This UI should prevent clicks from propagating to the underlying scene.
# - This UI should be semi-transparent, in order to still show the scene behind.
# - This UI should show the same content as the editor plugin version.
#
# ### PART 4: Buffer UI scrubbing
# - Add support for re-rendering the scene with the state from a given buffer
#   frame.
# - Add interaction support for picking and scrubbing through the buffer UI
#   (both the editor-plugin version and the in-game version).
#
# ### PART 5: Visualizing rollback reconciliation diff
# - Add a new settings flag: Settings.is_network_pause_on_rollback_enabled
# - Add a new hotkey (F12) for triggering auto-pause-on-rollback for the next
#   rollback.
#   - Don't auto-pause before the hotkey enables auto-pause, since there are
#     probably a lot of small rollbacks, and it would be too noisy.
# - Add support for automatically triggering a network pause from the client
#   when it triggers a rollback.
# - Whenever ((Settings.is_network_pause_debug_shortcut_enabled and
#   Settings.is_network_rollback_state_buffer_debug_ui_visible) or
#   Settings.is_network_pause_on_rollback_enabled), create a copy of all
#   pre-rollback rollback buffers whenever a rollback is triggered.
#   - This will get re-used for the rollback visual interpolation feature.
# - When pausing, auto scrub to the frame that orginated the rollback.
# - Now, in each tooltip, show info for both the pre- and post-rollback state.
# - Now, when scrubbing, show post-rollback scene state in the normal scene, and
#   render a duplicate version of the entire screen, overtop the first, as
#   semi-transparent, desaturated, and hue-shifted.
#
# ### PART 6: Visualizing server-side rollback
# - Add a new flag: Settings.is_visualizing_server_instead_of_client_rollbacks
# - When this is enabled, do most of the same pause logic, but don't show client
#   buffer state.
# - Instead, add a new RPC from the server that sends _all_ of the server's
#   pre-rollback buffer state, as well as the newly-received input state (this
#   should be sent any time the server is paused).
# - The client then replaces all of its local pre-rollback buffers with the
#   server's versions.
# - Show a label at the top of the panel that indicates whether we're seeing
#   local client state or remote server state.
# - Disable viewing the local client version of the buffer once the server
#   version has been viewed (since we'll have replaced pre-rollback buffers with
#   server state).
#
# ### PART 7: Rollback visual interpolation
# - Add support for visually interpolating from pre-rollback state to
#   post-rollback state.
#   - This should result in less snapping on the client.
# - Make sure each networked entity includes a special
#   RollbackVisualInterpolationOffset node.
#   - This should be assigned in an @export var.
#   - Make sure all visual state for the entity (sprites, animations, etc.) is
#     contained under this node.
#   - But all physics state (colliders, etc.) should be outside this node.
# - Use the duplicate pre-rollback buffer from the rollback-debug-ui feature.
# - Whenever a rollback occurs, we copy all prerollback state from the orginal
#   to the duplicate starting at the rollback origin frame and then for all
#   following frames.
#   - Note, we're now doing this regardless of which debug flags are enabled.
#   - However, for this interpolation, we only need to copy the frames at and
#     following the rollback.
#   - For the previous rollback debug visualization feature, we still need to
#     copy the entire buffer (but only when the appropriate debug flags are
#     enabled).
# - Then, we also record the last-rollback-start-time.
# - Then, in _physics_process, we adjust the RollbackVisualInterpolationOffset
#   position, according to current tween lerp logic from the rollback start time
#   to the current time and the interpolation duration.
#
# ### PART 8: Add hotkeys for toggling each of the various super-hud debug UI
# - F1 should toggle DebugConsole
# - F2 should toggle PlayerStateList
# - F3 should toggle PerfTracker
# - F4 should toggle the rollback buffer
#   - showing local state
#   - this should also toggle server pause
# - F5 should toggle the rollback buffer
#   - showing server state
#   - this should also toggle server pause
#   - we should be able to switch back-and-forth between the client and server
#     versions without unpausing
# - F12 should continue to trigger auto-pause-on-rollback for the next rollback
#   from PART 5.

# FIXME: After polishing networking from above:
# - Add a screen shake for each kill?
# - Use PixelLab for level art ideation?:
#   - https://www.pixellab.ai/
#   - Bunny
#     - Create some mocks for a simple 16x16 bunny.
#     - [Choose one.]
#     - Create a animation spritesheet for this bunny. I need eight frames for a "walk" animation (this is probably more of a hop, since it's a bunny). I need four frames for a jump-rise animation, and four frames for a jump-fall animation. I need eight frames for an idle animation.
#   - Explosion
#     - I need to create animation frames for a gratuitously gorey bunny-explosion splatter effect.
#     - I need to create an alternate bunny-explosion effect for when gore is disabled. This effect should spray flowers and maybe rainbows.
# - Hook-up animations:
#   - Spritesheets are [here].
#   - bunny_animator.tscn and bunny.tscn are [here].
#   - Hook-up the rest, walk, jump-rise, and jump-fall animations.
#   - Hook-up the bunny-explosion gore effect when a bunny is killed.
# - Gore setting:
#   - Add a toggle button on the main menu, pause menu, and game over menu to switch gore on and off.
#   - Record this setting in Settings.
#   - Update the bunny-death animation to check this setting. For non-gore mode, use the flower explosion animation.
#   - Persist a copy of Settings to local user space.
#   - Then, have the gore setting persist to this space when changed; add functions on Settings for triggering save and load, and trigger save from menus when toggling gore.
#   - Have gore default to off.
# - Add support for accumulating gore (or flower) particles from bunny
#   explosions.
#   - Whenever an explosion happens, spawn a handful of custom particles that explode outward.
#   - These should be a custom scene, rather than using Godot's built-in particle logic.
#   - A particle should extend RigidBody2D.
#   - Each particle should use a circle for its collision geometry.
#   - We should have a set of 8 different particle definitions for gore and a set of 8 for flowers.
#   - Each particle definition has a different sprite and a different collision radius.
#   - Each particle is assigned a random definition.
#   - Each particle is assigned a random direction and a random speed (within a min-max range).
#   - Actually, define two separate types of particles: fast and slow:
#    - There should be four definitions for either type (still with a duplicate set for gore vs non-gore mode).
#    - The fast particles should have a lot more speed when initially spawned, and should bounce more.
#   - When the particle comes to rest (displacement for a frame is less than some threshold like 0.05), destroy the node, and record the particle's type and position in separate arrays.
#   - Create a shader that accepts these arrays of particle types and positions, and renders them.
#   - Alternatively, let me know if there is a better way to efficently render tens of thousands of particles like this!
# - In the lobby, when spawning a player, briefly render over their head an indicator for which controls they're using.
#   - A simple drawing of rectangles in the shape of WASD, IJKL, or Arrows, or a controller shape.
# - Sounds (talk to Alden)
#   - Kill
#     - Splatter sound
#     - Confetti party popper sound for non-gore mode
#   - Jump sound
#   - Land sound
#   - Walk sound
#   - Bunny bump sound
#   - Menu click sound
#   - Add countdown tick sounds.
#     - Match-start: Arpeggio: Do mi so do!
#     - Match-end: Write a simple song, beat-aligned to seconds, 10 seconds long.
# - Make sleeping bunny animations for while the countdown is going.
#   - Make sure to override process_mode on PlayerAnimators, so they will move when paused.

# UI fixes:
# - Adjust scene files: lobby_level.tscn, player_list.tscn, player_display.tscn.
# - Lobby scene:
#   - Embed the game title logo within the level.
#   - Also embed some controls instruction.
#   - Also embed instructions to go down hole for starting match.
#   - Call MatchmakingClient.start_matchmaking() when any player jumps down a
#     rabbit hole on the right side of the level.
# - Hook-up / polish pause UI.
#   - Show a small panel in the center of the window with a lightly transparent screen.
# - Revise game-over UI.
#   - Also a panel overlay over the still-visible level area.
#   - Only show this game-over panel while in the lobby.
#   - Have this panel persist, and not take up too much space.
#   - Let players move while the panel is open.
#   - So, completely not a "screen" or part of the transition system at all
#     anymore.

# - Add alternate camera modes.
#   - Support two modes: global camera vs player camera.
#   - This will be configured on the level.
#   - For global camera, dynamically instantiate, configure (according to
#     level bounds), attach, and activate a camera to the level.
#   - For player camera, add support for split screen.
#     - Add a TODO for this for now.

# - [Copilot] Go through each file and fix formatting inconsistencies.
#   - Make sure there are always two empty lines between functions and after the
#     class `extends` line.
#     - But make sure that if a file-level doc comment is present, it is on the
#       next line after the `extends` line
#   - Fix inconsistent line-break. Lines should break at 80 characters.
#   - Use tabs instead of spaces.
#   - Fix anything else that looks off.

# - Add support for web and mobile
#   - Plan through what all needs to change to support websockets
#   - Send client type to the matchmaking backend? Have it prefer the same device type, but be willing to match with others
#   - Mobile controls:
#     - YES
#       - Vertical band for left
#       - Vertical band for right
#       - Possible vertical band for gap, depending on physical screen width
#       - Vertical band for jump
#     - NO
#       - Divide screen into three regions: left, middle, right
#         - Tap middle to jump
#         - Pressed left right I move
#     - Draw a semitransparent bar across the bottom to indicate the regions with an icon
#     - Have a setting to disable the bar
#     - For UI controls:
#       - Have the left/right map to up/down.
#       - Have the jump map to trigger/right (there is no left then; this shouldn't make any difference except for the trinary level-pref buttons).

# - Take another pass at fixing any broken tests.
# - Ask the AI to take another pass at ensuring we have clean decoupling between the frameworks and the game logic.
#   - addons/gamelift/
#   - addons/gamelift_session_manager/ (can depend on rollback_netcode, cannot depend on src/)
#   - addons/rollback_netcode/ (cannot depend on addons/gamelift/, addons/gamelift_session_manager/, src/, or addons/rollback_netcode/examples/)
#   - src/
#   - addons/rollback_netcode/examples/simple_game/ (cannot depend on src/)
# - Test and polish addons/rollback_netcode/examples/simple_game/.
# - Review and edit markdown docs.

# - Disable networked pause.

# - Sudden death?

# - Easter eggs!
#   - Secrets and an art curiosity in every level, and stuff you can actually collect and unlock...
#   - hidden holes in walls.

# ### TODO: After everything else:
# - Survey the codebase for where we use string literals. Should any of these be StringName literals instead?
# - Review tests.
# - Review these notes: https://docs.google.com/document/d/1qJcNUrE1y8UllVVCojp-IN3zCwml8VK7kjYhp1uJhV4
# - Review the example app.
# - Review these notes: https://trello.com/c/i8peodBL
# - Organize Settings.
#   - Analyze all properties in Settings, and how they are used.
#   - Re-group, re-order, re-name, and possibly consolidate properties in whichever way makes the most sense.
# - Use is_instance_valid instead of null comparisons.
# - Survey usage of G.check, G.ensure, G.error, G.fatal, and G.alert.
#   - Check if there are places that I should be more gracefully showing the
#     player a message, and/or redirecting back to the lobby, possibly with
#     reset game state.
# - AI: Scan through all logs, and consider whether we should add any additional
#   categories, and re-group logs int whichever categories make the most sense.
# - AI: I am considering creating a re-usable GDExtension that I can publish on
#   the Godot Asset Library for anyone to use for common featurse when
#   integrating with AWS GameLift.
#   - Does this make sense? Is there any logic within the current C++
#     GDExtension directory that is specific to this local game? Or are there
#     any additional features that it would make sense to add?
# - AI: I want to publish a plugin on the Godot Asset Library that provides
#   support for client prediction and rollback networking. Please create a plan
#   for implementing this plugin based on the current networking architecture in
#   this project. The plugin should be easy to integrate into new Godot
#   projects, and should include documentation and example scenes. In
#   particular, analyze this codebase, and identify which systems need to be
#   decoupled in order to separate-out the game-agnostic networking logic
#   (connection, replication, prediction, rollback, driver, time-tracking,
#   important not-game-specific local-session and match-state logic, etc). In
#   particular, I think some of the current "local-session" vs "match-state" vs
#   other state tracked in networking systems might be best to consolidate in a
#   separate location.
# - Search for and replace/remove anthropic and claude.

# Add alternate modes for all the holidays:
#   - Halloween: candy gore, background change, level change, costume change
#   - Vday: red and pink heart gore, also little baby bunnies run away away when
#     killed, background/level/costume...
#   - Shamrocks
#   - Fireworks
#   - Candy canes
#   - Easter eggs (and finding bonus Easter eggs hidden in each level; need to
#     add occlusion at for this!)
#   - T day...
#   - Chinese New Year's
#   - Other important holidays across the world
# - Alternate adjectives for holidays too


# ### Devlog post:
# - AI helped a lot
# - AI sucked at:
#   - Fixing the GitHub Actions CI workflows.
#     - Probably ~60 iterations.
#
```
