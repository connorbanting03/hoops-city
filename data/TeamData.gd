class_name TeamData
extends Resource
## A franchise: identity, roster, market, and accumulated history. Current-season
## record is filled by the SeasonManager (M4); economy/city attach later (M5/M6).

@export var id: int = 0
@export var name: String = ""
@export var abbrev: String = ""
@export var is_player_team: bool = false
@export var market_size: float = 1.0          # starting market tier; city growth feeds this later
@export var cash: int = 0                       # bank for buildings/scouting/arena (separate from the cap)
@export var roster: Array[PlayerData] = []

# Seeded / accumulated history
@export var championships: int = 0
@export var last_title_year: int = 0
@export var all_time_wins: int = 0
@export var all_time_losses: int = 0

# Current-season record (driven by M4)
@export var wins: int = 0
@export var losses: int = 0

func add_player(p: PlayerData) -> void:
	roster.append(p)

## Top-N players by overall — the rotation that actually decides games.
func rotation(n: int = 8) -> Array:
	var sorted_roster := roster.duplicate()
	sorted_roster.sort_custom(func(a, b): return a.overall() > b.overall())
	return sorted_roster.slice(0, mini(n, sorted_roster.size()))

func team_ovr(n: int = 8) -> float:
	var rot := rotation(n)
	if rot.is_empty():
		return 0.0
	var s := 0.0
	for p in rot:
		s += float(p.overall())
	return s / float(rot.size())

func count_position(pos: String) -> int:
	var c := 0
	for p in roster:
		if p.primary_pos == pos:
			c += 1
	return c
