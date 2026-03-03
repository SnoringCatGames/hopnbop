class_name DynamicAdjectiveConfig
extends RefCounted
## Configuration and algorithm for assigning dynamic
## adjectives based on per-player match stats. Each
## stat has optional upper/lower ratio thresholds,
## matching absolute thresholds, and corresponding
## adjective lists.


const NAMES := [
	"Dott",
	"Jiffy",
	"Fizz",
	"Mijji",
	"Bunbun",
	"Biscuit",
	"Thumper",
	"Cinnabun",
	"Marshmallow",
	"Flopsy",
	"Nugget",
	"Clover",
	"Snowball",
	"Peanut",
	"Whiskers",
	"Butterscotch",
	"Mochi",
	"Hopper",
	"Caramel",
	"Pudding",
	"Binky",
	"Cocoa",
	"Sprout",
	"Waffles",
	"Patches",
	"Nibbles",
	"Hazel",
	"Cotton",
	"Pepper",
	"Snickerdoodle",
	"Oreo",
	"Maple",
	"Dusty",
	"Pippin",
	"Twix",
	"Honeybun",
	"Mocha",
	"Jellybean",
	"Scooter",
	"Truffle",
	"Pickles",
	"Bambi",
	"Popcorn",
	"Velvet",
	"Gizmo",
	"Dandelion",
	"Churro",
	"Fuzz",
	"Bubbles",
	"Pretzel",
	"Domino",
	"Sesame",
	"Latte",
	"Bongo",
	"Crumbs",
	"Thistle",
	"Muffin",
	"Pebbles",
	"Éclair",
	"Buttons",
	"Sage",
	"Noodle",
	"Twinkle",
	"Chewie",
	"Blossom",
	"Cashew",
	"Doodle",
	"Taffy",
	"Willow",
	"Squish",
	"Chai",
	"Bonbon",
	"Freckles",
	"Gimli",
	"Tumble",
	"Espresso",
	"Pixie",
	"Bumblebee",
	"Juniper",
	"Cheerio",
	"Snuggles",
	"Puffin",
	"Ginger",
	"Wiggles",
	"Tofu",
	"Mitzi",
	"Pecan",
	"Zigzag",
	"Thistle",
	"Sprinkles",
	"Basil",
	"Cuddles",
	"Pancake",
	"Fluffernutter",
	"Olive",
	"TaterTot",
	"Cheddar",
	"Skippy",
	"Acorn",
	"Wobbles",
	"Rosie",
	"S'mores",
	"Dumpling",
	"Mopsy",
	"Sir Hopsalot",
]

const SOFT_ADJECTIVES := [
	"Bouncy",
	"Chonky",
	"Floppy",
	"Snuggly",
	"Twitchy",
	"Fuzzy",
	"Wiggly",
	"Cuddly",
	"Plump",
	"Velvety",
	"Squishy",
	"Hoppy",
	"Sleepy",
	"Chunky",
	"Adorable",
	"Mischievous",
	"Derpy",
	"Zoomie",
	"Pudgy",
	"Silky",
	"Tubby",
	"Soft",
	"Goofy",
	"Loaf-like",
	"Round",
	"Curious",
	"Floofy",
	"Boopable",
	"Tiny",
	"Dainty",
	"Plush",
	"Cottony",
	"Roly-poly",
	"Wriggly",
	"Sneaky",
	"Poofy",
	"Perky",
	"Grumpy",
	"Spunky",
	"Droopy",
	"Cozy",
	"Sassy",
	"Pampered",
	"Lazy",
	"Nibbling",
	"Munchy",
	"Frisky",
	"Peppy",
	"Smooshy",
	"Binky-prone",
	"Plushy",
	"Wobbling",
	"Teeny",
	"Blobby",
	"Scruffy",
	"Precious",
	"Feisty",
	"Fluffball-ish",
	"Nosy",
	"Pouty",
	"Majestic",
	"Scampering",
	"Thumpy",
	"Marshmallowy",
	"Huggable",
	"Gentle",
	"Ridiculous",
	"Rotund",
	"Dapper",
	"Scraggly",
	"Squashy",
	"Pillowy",
	"Mellow",
	"Docile",
	"Energetic",
	"Tubular",
	"Bashful",
	"Flappy-eared",
	"Potato-shaped",
	"Velour",
	"Itty-bitty",
	"Bumbling",
	"Shy",
	"Giggly",
	"Zoomy",
	"Orb-like",
	"Plucky",
	"Innocent",
	"Dumpy",
	"Pettable",
	"Sniffling",
	"Sprawling",
	"Lounge-y",
	"Twirly",
	"Bonkers",
	"Melty",
	"Boop-nosed",
]

const HARD_ADJECTIVES := [
	"Savage",
	"Ruthless",
	"Fierce",
	"Relentless",
	"Unstoppable",
	"Legendary",
	"Brutal",
	"Ferocious",
	"Deadly",
	"Menacing",
	"Vicious",
	"Merciless",
	"Fearless",
	"Dominant",
	"Mighty",
	"Rampaging",
	"Lethal",
	"Thunderous",
	"Formidable",
	"Unbreakable",
	"Invincible",
	"Raging",
	"Sinister",
	"Vengeful",
	"Apocalyptic",
	"Demonic",
	"Infernal",
	"Diabolical",
	"Terrifying",
	"Monstrous",
	"Colossal",
	"Titanic",
	"Supreme",
	"Ultimate",
	"Blazing",
	"Scorching",
	"Nuclear",
	"Explosive",
	"Annihilating",
	"Devastating",
	"Crushing",
	"Obliterating",
	"Wicked",
	"Unholy",
	"Chaotic",
	"Primal",
	"Reckless",
	"Berserker",
	"Warlike",
	"Battle-hardened",
	"Bloodthirsty",
	"Ravenous",
	"Rabid",
	"Feral",
	"Untamed",
	"Wild",
	"Savage",
	"Grim",
	"Dark",
	"Shadowy",
	"Nightmarish",
	"Cursed",
	"Forsaken",
	"Doomed",
	"Hellish",
	"Volcanic",
	"Seismic",
	"Cataclysmic",
	"Catastrophic",
	"Turbulent",
	"Stormy",
	"Tempestuous",
	"Wrathful",
	"Furious",
	"Enraged",
	"Malevolent",
	"Ominous",
	"Dreadful",
	"Ghastly",
	"Macabre",
	"Deranged",
	"Maniacal",
	"Unhinged",
	"Psychotic",
	"Insane",
	"Berserk",
	"Frenzied",
]


## Default ratio thresholds. A value of 1.5 means
## the player's stat must be >= 1.5x the average.
const DEFAULT_UPPER_THRESHOLD := 1.5
const DEFAULT_LOWER_THRESHOLD := 0.5


enum StatName {
	CROWN_TIME,
	REGICIDE_COUNT,
	BUMP_COUNT,
	KILL_COUNT,
	DEATH_COUNT,
	JUMP_COUNT,
	WATER_TIME,
	WATER_JUMP_COUNT,
	ICE_TIME,
	SPRING_LAUNCHES,
	DIRECTION_CHANGES,
	AVERAGE_HEIGHT,
	COMBINED_DISRUPTION,
	FLY_PROXIMITY_TIME,
	POOP_COUNT,
}


# --- Stat threshold configs ---
# Each entry has ratio thresholds (upper/lower) and
# matching absolute thresholds (upper_abs/lower_abs).
# Ratio threshold: player_value / average.
# Absolute threshold: raw value floor (upper) or
#   ceiling (lower) the player must also satisfy.
# null ratio threshold means "not checked"; the
# corresponding _abs key is omitted.

static var STAT_CONFIGS := {
	StatName.CROWN_TIME: {
		"upper": 1.5,
		"upper_abs": 3.0,
		"lower": null,
		"upper_adjectives": CROWN_UPPER,
		"lower_adjectives": [],
	},
	StatName.REGICIDE_COUNT: {
		"upper": 1.5,
		"upper_abs": 1.0,
		"lower": null,
		"upper_adjectives": REGICIDE_UPPER,
		"lower_adjectives": [],
	},
	StatName.BUMP_COUNT: {
		"upper": 1.5,
		"upper_abs": 3.0,
		"lower": null,
		"upper_adjectives": BUMPS_UPPER,
		"lower_adjectives": [],
	},
	StatName.KILL_COUNT: {
		"upper": 1.5,
		"upper_abs": 3.0,
		"lower": 0.5,
		"lower_abs": 1.0,
		"upper_adjectives": KILLS_UPPER,
		"lower_adjectives": KILLS_LOWER,
	},
	StatName.DEATH_COUNT: {
		"upper": 1.5,
		"upper_abs": 3.0,
		"lower": 0.5,
		"lower_abs": 1.0,
		"upper_adjectives": DEATHS_UPPER,
		"lower_adjectives": DEATHS_LOWER,
	},
	StatName.JUMP_COUNT: {
		"upper": 1.5,
		"upper_abs": 30.0,
		"lower": 0.5,
		"lower_abs": 10.0,
		"upper_adjectives": JUMPS_UPPER,
		"lower_adjectives": JUMPS_LOWER,
	},
	StatName.WATER_TIME: {
		"upper": 1.5,
		"upper_abs": 3.0,
		"lower": null,
		"upper_adjectives": WATER_TIME_UPPER,
		"lower_adjectives": [],
	},
	StatName.WATER_JUMP_COUNT: {
		"upper": 1.5,
		"upper_abs": 2.0,
		"lower": null,
		"upper_adjectives": WATER_JUMP_UPPER,
		"lower_adjectives": [],
	},
	StatName.ICE_TIME: {
		"upper": 1.5,
		"upper_abs": 3.0,
		"lower": null,
		"upper_adjectives": ICE_TIME_UPPER,
		"lower_adjectives": [],
	},
	StatName.SPRING_LAUNCHES: {
		"upper": 1.5,
		"upper_abs": 3.0,
		"lower": null,
		"upper_adjectives": SPRINGS_UPPER,
		"lower_adjectives": [],
	},
	StatName.DIRECTION_CHANGES: {
		"upper": 1.5,
		"upper_abs": 20.0,
		"lower": 0.5,
		"lower_abs": 5.0,
		"upper_adjectives": DIRECTION_CHANGES_UPPER,
		"lower_adjectives": DIRECTION_CHANGES_LOWER,
	},
	StatName.AVERAGE_HEIGHT: {
		"upper": 1.3,
		"upper_abs": 0.0,
		"lower": null,
		"upper_adjectives": HEIGHT_UPPER,
		"lower_adjectives": [],
	},
	StatName.COMBINED_DISRUPTION: {
		"upper": 1.5,
		"upper_abs": 5.0,
		"lower": null,
		"upper_adjectives":
			CRITTER_DISRUPTOR_UPPER,
		"lower_adjectives": [],
	},
	StatName.FLY_PROXIMITY_TIME: {
		"upper": 1.5,
		"upper_abs": 10.0,
		"lower": null,
		"upper_adjectives":
			FLY_PROXIMITY_UPPER,
		"lower_adjectives": [],
	},
	StatName.POOP_COUNT: {
		"upper": 1.5,
		"upper_abs": 3.0,
		"lower": null,
		"upper_adjectives": POOP_UPPER,
		"lower_adjectives": [],
	},
}


# --- Adjective Lists ---


# Crown time upper: regal, royal themes.
const CROWN_UPPER := [
	"Regal",
	"Kingly",
	"Majestic",
	"Noble",
	"Sovereign",
	"Imperial",
	"Crowned",
	"Enthroned",
	"Reigning",
	"Anointed",
	"Royal",
	"Exalted",
	"Triumphant",
	"Glorious",
]

# Regicide upper: king-slayer themes.
const REGICIDE_UPPER := [
	"King-slaying",
	"Regicidal",
	"Throne-toppling",
	"Crown-snatching",
	"Usurping",
	"Dethroning",
	"Insurgent",
	"Coup-staging",
	"Dynasty-ending",
	"Monarch-hunting",
	"Uprising-leading",
	"Overthrow-happy",
	"Scepter-breaking",
]

# Bumps upper: aggressive, confrontational.
const BUMPS_UPPER := [
	"Rowdy",
	"Brawling",
	"Scrappy",
	"Rambunctious",
	"Pushy",
	"Bulldozing",
	"Combative",
	"Rough-and-tumble",
	"Shoulder-checking",
	"Bruising",
	"Stampeding",
	"Barging",
	"Truculent",
	"Bullish",
	"Wrestling",
]

# Kills upper: deadly, lethal themes.
const KILLS_UPPER := [
	"Devastating",
	"Lethal",
	"Ruthless",
	"Merciless",
	"Unstoppable",
	"Dominant",
	"Vicious",
	"Fearsome",
	"Relentless",
	"Crushing",
	"Annihilating",
	"All-destroying",
	"Supreme",
	"Skull-crushing",
	"Conquering",
]

# Kills lower: peaceful, pacifist themes.
const KILLS_LOWER := [
	"Peaceful",
	"Pacifist",
	"Gentle",
	"Harmless",
	"Merciful",
	"Kind-hearted",
	"Benevolent",
	"Tender",
	"Tranquil",
	"Serene",
	"Zen",
	"Passive",
	"Nonviolent",
	"Meek",
	"Mild-mannered",
]

# Deaths upper: accident-prone, unlucky.
const DEATHS_UPPER := [
	"Accident-prone",
	"Hapless",
	"Unlucky",
	"Cursed",
	"Doomed",
	"Ill-fated",
	"Star-crossed",
	"Jinxed",
	"Tragic",
	"Luckless",
	"Blundering",
	"Clumsy",
	"Disaster-prone",
	"Squishy",
	"Fragile",
]

# Deaths lower: survivalist, resilient.
const DEATHS_LOWER := [
	"Invincible",
	"Immortal",
	"Unkillable",
	"Resilient",
	"Indestructible",
	"Enduring",
	"Undying",
	"Unbreakable",
	"Everlasting",
	"Defiant",
	"Unscathed",
	"Tough-as-nails",
	"Diamond-skinned",
]

# Jumps upper: hyperactive, springy.
const JUMPS_UPPER := [
	"Hyperactive",
	"Springy",
	"Manic",
	"Caffeinated",
	"Boing-boing",
	"Pogo-legged",
	"Restless",
	"Bouncing",
	"Leaping",
	"Exuberant",
	"Sky-bound",
	"Airborne",
	"Kangaroo-like",
	"Spastic",
	"Twitchy",
]

# Jumps lower: grounded, planted.
const JUMPS_LOWER := [
	"Grounded",
	"Planted",
	"Earthbound",
	"Rooted",
	"Anchored",
	"Flat-footed",
	"Steady",
	"Unshakeable",
	"Immovable",
	"Stubborn",
	"Heavy-footed",
	"Leaden",
	"Stoic",
	"Unmoved",
	"Statuesque",
]

# Water time upper: aquatic themes.
const WATER_TIME_UPPER := [
	"Aquatic",
	"Amphibious",
	"Waterlogged",
	"Deep-diving",
	"Soggy",
	"Saturated",
	"Submerged",
	"Swimming",
	"Dripping",
	"Drenched",
	"Tidal",
	"Nautical",
	"Oceanic",
	"Briny",
	"Fish-like",
]

# Water jump upper: acrobatic water themes.
const WATER_JUMP_UPPER := [
	"Dolphin-like",
	"Breaching",
	"Splashing",
	"Porpoising",
	"Surf-riding",
	"Wave-hopping",
	"Leaping-salmon",
	"Geyser-powered",
	"Sea-sprung",
	"Torrent-born",
]

# Ice time upper: cold/frozen themes.
const ICE_TIME_UPPER := [
	"Frostbitten",
	"Glacial",
	"Ice-skating",
	"Frozen",
	"Arctic",
	"Chilly",
	"Frost-kissed",
	"Ice-crusted",
	"Permafrost",
	"Blizzard-born",
	"Snow-dusted",
	"Sub-zero",
	"Frigid",
	"Winterized",
	"Slippery",
]

# Spring launches upper: bouncy, elastic themes.
const SPRINGS_UPPER := [
	"Spring-loaded",
	"Catapulted",
	"Launched",
	"Propelled",
	"Rocket-powered",
	"Trampoline-loving",
	"Turbo-boosted",
	"Slingshot",
	"Elastic",
	"Rebounding",
	"Ejected",
	"Ballistic",
	"Jet-propelled",
	"Booster-fueled",
	"Supersonic",
]

# Direction changes upper: flighty, nervous.
const DIRECTION_CHANGES_UPPER := [
	"Flighty",
	"Scared",
	"Nervous",
	"Jittery",
	"Indecisive",
	"Twitchy",
	"Frantic",
	"Panicky",
	"Scatterbrained",
	"Zigzagging",
	"Erratic",
	"Fidgety",
	"Skittish",
	"Waffling",
	"Flustered",
]

# Direction changes lower: bold, determined.
const DIRECTION_CHANGES_LOWER := [
	"Bold",
	"Surefooted",
	"Confident",
	"Determined",
	"Resolute",
	"Unwavering",
	"Single-minded",
	"Purposeful",
	"Focused",
	"Steadfast",
	"Unflinching",
	"Unyielding",
	"Decisive",
	"Iron-willed",
	"Unshakeable",
]

# Average height upper: sky/altitude themes.
# Uses negated Y so higher altitude = higher value.
const HEIGHT_UPPER := [
	"Sky-dwelling",
	"Cloud-hopping",
	"Soaring",
	"High-flying",
	"Lofty",
	"Elevated",
	"Skyward",
	"Summit-seeking",
	"Peak-climbing",
	"Mountaintop",
	"Stratospheric",
	"Towering",
	"Zenith-bound",
]

# Combined critter disruption upper: nature-
# disrupting, chaotic themes.
const CRITTER_DISRUPTOR_UPPER := [
	"Disruptive",
	"Terrorizing",
	"Harassing",
	"Exterminating",
	"Frightening",
	"Beast-bothering",
	"Havoc-wreaking",
]

# Fly proximity time upper: fly-associated,
# gross/funny themes.
const FLY_PROXIMITY_UPPER := [
	"Buzzing",
	"Swarm-kissed",
	"Fly-whispering",
	"Buzz-bathed",
	"Gnat-clouded",
	"Bug-wreathed",
	"Midge-mantled",
]

# Poop count upper: scatological, gross/funny
# themes.
const POOP_UPPER := [
	"Prolific-pooper",
	"Fertilizing",
	"Trail-leaving",
	"Pellet-dropping",
	"Dung-dealing",
	"Plop-prone",
	"Bowel-blessed",
	"Turd-turfing",
	"Fecalferious",
	"Scat-tastic",
]


# --- All dynamic adjective lists (for validation) ---

static var _ALL_DYNAMIC_LISTS: Array[Array] = [
	CROWN_UPPER,
	REGICIDE_UPPER,
	BUMPS_UPPER,
	KILLS_UPPER,
	KILLS_LOWER,
	DEATHS_UPPER,
	DEATHS_LOWER,
	JUMPS_UPPER,
	JUMPS_LOWER,
	WATER_TIME_UPPER,
	WATER_JUMP_UPPER,
	ICE_TIME_UPPER,
	SPRINGS_UPPER,
	DIRECTION_CHANGES_UPPER,
	DIRECTION_CHANGES_LOWER,
	HEIGHT_UPPER,
	CRITTER_DISRUPTOR_UPPER,
	FLY_PROXIMITY_UPPER,
	POOP_UPPER,
]


## Checks if an adjective belongs to any dynamic
## adjective list.
static func is_valid_dynamic_adjective(
	adjective: String,
) -> bool:
	for list in _ALL_DYNAMIC_LISTS:
		if list.has(adjective):
			return true
	return false


## Assigns dynamic adjectives to all players based
## on their match stats. Returns a Dictionary mapping
## player_id -> new adjective string.
static func assign_adjectives(
	stats_by_player_id: Dictionary,
) -> Dictionary:
	var player_ids: Array = (
		stats_by_player_id.keys())
	var player_count := player_ids.size()

	if player_count == 0:
		return {}

	# Step 1: Calculate averages for each stat.
	var averages := _calculate_averages(
		stats_by_player_id)

	# Step 2: For each player, collect qualifying
	# adjective lists.
	var result := {}
	for player_id in player_ids:
		var stats: PlayerMatchStats = (
			stats_by_player_id[player_id]
		)
		var qualifying_lists: Array[Array] = []

		for stat_name in STAT_CONFIGS:
			var config: Dictionary = (
				STAT_CONFIGS[stat_name]
			)
			var player_value := _get_stat_value(
				stats, stat_name)
			var avg_value: float = (
				averages[stat_name]
			)

			# Skip if average is zero (no meaningful
			# comparison).
			if avg_value == 0.0:
				continue

			var ratio := player_value / avg_value

			# Check upper threshold.
			if (
				config["upper"] != null
				and ratio >= config["upper"]
				and player_value
					>= config["upper_abs"]
				and not config[
					"upper_adjectives"].is_empty()
			):
				qualifying_lists.append(
					config["upper_adjectives"])

			# Check lower threshold.
			if (
				config["lower"] != null
				and ratio <= config["lower"]
				and player_value
					<= config["lower_abs"]
				and not config[
					"lower_adjectives"].is_empty()
			):
				qualifying_lists.append(
					config["lower_adjectives"])

		# Always include baseline soft adjectives.
		qualifying_lists.append(
			SOFT_ADJECTIVES)
		if G.settings.are_hard_adjectives_enabled:
			qualifying_lists.append(
				HARD_ADJECTIVES)

		# Step 3: Pick a random qualifying list,
		# then a random adjective from it.
		var chosen_list: Array = (
			qualifying_lists.pick_random()
		)
		result[player_id] = (
			chosen_list.pick_random())

	return result


static func _calculate_averages(
	stats_by_player_id: Dictionary,
) -> Dictionary:
	var player_count := (
		stats_by_player_id.size()
	)
	var totals := {}
	for stat_name in StatName.values():
		totals[stat_name] = 0.0

	for player_id in stats_by_player_id:
		var stats: PlayerMatchStats = (
			stats_by_player_id[player_id]
		)
		for stat_name in StatName.values():
			totals[stat_name] += _get_stat_value(
				stats, stat_name)

	var averages := {}
	for stat_name in StatName.values():
		averages[stat_name] = (
			totals[stat_name] / player_count
		)
	return averages


static func _get_stat_value(
	stats: PlayerMatchStats,
	stat_name: int,
) -> float:
	match stat_name:
		StatName.CROWN_TIME:
			return stats.crown_time_sec
		StatName.REGICIDE_COUNT:
			return float(stats.regicide_count)
		StatName.BUMP_COUNT:
			return float(stats.bump_count)
		StatName.KILL_COUNT:
			return float(stats.kill_count)
		StatName.DEATH_COUNT:
			return float(stats.death_count)
		StatName.JUMP_COUNT:
			return float(stats.jump_count)
		StatName.WATER_TIME:
			return stats.water_time_sec
		StatName.WATER_JUMP_COUNT:
			return float(stats.water_jump_count)
		StatName.ICE_TIME:
			return stats.ice_time_sec
		StatName.SPRING_LAUNCHES:
			return float(
				stats.spring_launch_count)
		StatName.DIRECTION_CHANGES:
			return float(
				stats.direction_change_count)
		StatName.AVERAGE_HEIGHT:
			return stats.average_height
		StatName.COMBINED_DISRUPTION:
			return float(
				stats.cricket_disturb_count
				+ stats.fish_disturb_count
				+ stats.butterfly_disturb_count
				+ stats.snail_crush_count)
		StatName.FLY_PROXIMITY_TIME:
			return stats.fly_proximity_time_sec
		StatName.POOP_COUNT:
			return float(stats.poop_count)
		_:
			return 0.0
