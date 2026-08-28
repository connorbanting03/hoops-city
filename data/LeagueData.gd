class_name LeagueData
extends Resource
## The whole league: teams, who you are, who the dynasty is, the seeded past, and the
## league-wide salary cap (managed by M5). Lives inside GameState once a game starts.

@export var season_year: int = 2026
@export var teams: Array[TeamData] = []
@export var player_team_id: int = -1
@export var dynasty_team_id: int = -1
@export var league_cap: int = 0
@export var history: Array = []   # [{year:int, champion_id:int, champion_name:String}]

func get_team(team_id: int) -> TeamData:
	for t in teams:
		if t.id == team_id:
			return t
	return null

func player_team() -> TeamData:
	return get_team(player_team_id)

func dynasty_team() -> TeamData:
	return get_team(dynasty_team_id)

func most_titles_team() -> TeamData:
	var best: TeamData = null
	for t in teams:
		if best == null or t.championships > best.championships:
			best = t
	return best
