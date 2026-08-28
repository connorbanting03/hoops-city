class_name PlayerData
extends Resource
## A player = a readable rating bundle + identity + contract (GDD §4.1, §7.3).
## OVR is ALWAYS computed per position, never stored as truth — the same player
## can grade out "better" at the position that fits his tools.

# The 10 surface-level skills shown to the player. Each rated 1-99.
const ATTRS: Array[String] = [
	"inside",       # finishing at the rim: layups, dunks, post scoring
	"shooting",     # jump shot: mid-range + three (spacing)
	"playmaking",   # passing + ball-handling: creating and running offense
	"perimeter_d",  # on-ball defense vs guards/wings + steals
	"interior_d",   # rim protection, post defense, blocks
	"rebounding",   # offensive + defensive boards
	"athleticism",  # speed, agility, vertical
	"strength",     # physicality, finishing through contact
	"stamina",      # conditioning / minutes capacity
	"iq",           # decision-making, positioning, consistency
]

const ATTR_NAMES := {
	"inside": "Inside Scoring", "shooting": "Outside Shooting", "playmaking": "Playmaking",
	"perimeter_d": "Perimeter D", "interior_d": "Interior D", "rebounding": "Rebounding",
	"athleticism": "Athleticism", "strength": "Strength", "stamina": "Stamina", "iq": "Basketball IQ",
}

const POSITIONS: Array[String] = ["PG", "SG", "SF", "PF", "C"]

# Relative per-position weights for the OVR roll-up (normalized at compute time).
const POSITION_WEIGHTS := {
	"PG": {"playmaking": 9, "iq": 7, "shooting": 7, "perimeter_d": 6, "athleticism": 6, "inside": 4, "stamina": 4, "rebounding": 2, "interior_d": 2, "strength": 2},
	"SG": {"shooting": 9, "athleticism": 7, "perimeter_d": 7, "inside": 6, "playmaking": 6, "iq": 5, "stamina": 4, "rebounding": 3, "interior_d": 2, "strength": 2},
	"SF": {"shooting": 7, "perimeter_d": 7, "athleticism": 7, "inside": 7, "playmaking": 5, "rebounding": 5, "iq": 5, "strength": 4, "interior_d": 4, "stamina": 4},
	"PF": {"inside": 8, "rebounding": 8, "interior_d": 7, "strength": 7, "athleticism": 5, "shooting": 5, "iq": 4, "perimeter_d": 4, "stamina": 4, "playmaking": 3},
	"C": {"interior_d": 9, "rebounding": 9, "inside": 8, "strength": 8, "athleticism": 4, "iq": 4, "stamina": 4, "shooting": 3, "perimeter_d": 3, "playmaking": 2},
}

# --- Identity ---
@export var id: int = 0
@export var first_name: String = ""
@export var last_name: String = ""
@export var age: int = 20
@export var height_cm: int = 198
@export var primary_pos: String = "SF"
@export var archetype: String = ""

# --- Ratings (keyed by ATTRS) ---
@export var attributes: Dictionary = {}

# --- Hidden / dynamic ---
@export var potential: int = 0      # hidden growth ceiling, in OVR units
@export var durability: int = 60    # hidden injury resistance
@export var morale: int = 70        # dynamic

# --- Contract / history (filled by later milestones) ---
@export var salary: int = 0
@export var years_left: int = 0
@export var stats_history: Array = []
@export var accolades: Array = []

func full_name() -> String:
	return "%s %s" % [first_name, last_name]

func get_attr(key: String) -> int:
	return int(attributes.get(key, 0))

func overall() -> int:
	return overall_for(primary_pos)

func overall_for(pos: String) -> int:
	var weights: Dictionary = POSITION_WEIGHTS.get(pos, {})
	if weights.is_empty():
		return 0
	var total := 0.0
	var wsum := 0.0
	for key in weights:
		total += float(get_attr(key)) * float(weights[key])
		wsum += float(weights[key])
	return int(round(total / wsum)) if wsum > 0.0 else 0

func summary_line() -> String:
	return "%-18s %2d %-2s %3dcm %-13s OVR %2d [IN%2d SH%2d PM%2d PD%2d ID%2d RB%2d AT%2d ST%2d SM%2d IQ%2d] pot%2d" % [
		full_name(), age, primary_pos, height_cm, archetype, overall(),
		get_attr("inside"), get_attr("shooting"), get_attr("playmaking"),
		get_attr("perimeter_d"), get_attr("interior_d"), get_attr("rebounding"),
		get_attr("athleticism"), get_attr("strength"), get_attr("stamina"), get_attr("iq"),
		potential,
	]
