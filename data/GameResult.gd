class_name GameResult
extends RefCounted
## The outcome of one simulated game: final score, per-player box scores, game MVP, and
## (optionally) an event log for the future play-by-play replay (GDD §4.2). Pure data.

const STAT_KEYS := ["pts", "fgm", "fga", "tpm", "tpa", "ftm", "fta", "oreb", "dreb", "ast", "stl", "blk", "tov", "pf"]

var home_team_id: int = 0
var away_team_id: int = 0
var home_score: int = 0
var away_score: int = 0
var winner_id: int = 0
var loser_id: int = 0
var possessions: int = 0

var box: Dictionary = {}        # pid -> { stat_key: int }
var names: Dictionary = {}      # pid -> String (for readable box scores)
var team_of: Dictionary = {}    # pid -> team_id
var home_pids: Array = []
var away_pids: Array = []

var mvp_id: int = -1
var events: Array = []          # reserved for play-by-play; populated only when logging is on

func winner_score() -> int:
	return maxi(home_score, away_score)

func loser_score() -> int:
	return mini(home_score, away_score)

func line(pid: int) -> Dictionary:
	return box.get(pid, {})
