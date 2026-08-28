class_name PlayByPlay
extends RefCounted
## Turns a GameResult's event log into a readable play-by-play feed (GDD §4.2 tier 2). Pure: every
## scoring event carries its points, so accumulating them reproduces the final score exactly — the
## gate checks that the feed reconciles. The Game Day screen streams these lines one at a time.

## Returns an ordered list of { text, home, away, home_play, scored } — home/away are the RUNNING
## score after this play. Requires the GameResult to have been simulated with {"log_events": true}.
static func feed(r: GameResult) -> Array:
	var home := 0
	var away := 0
	var out := []
	for e in r.events:
		var pid: int = e["pid"]
		var is_home: bool = int(r.team_of.get(pid, 0)) == r.home_team_id
		var name: String = r.names.get(pid, "?")
		var pts := 0
		var text := ""
		match e["type"]:
			"fg3":
				pts = 3
				text = "%s buries a three" % name
				if int(e.get("assist_pid", -1)) >= 0:
					text += " (assist: %s)" % r.names.get(e["assist_pid"], "?")
			"fg2":
				pts = 2
				text = "%s scores" % name
				if int(e.get("assist_pid", -1)) >= 0:
					text += " off the feed from %s" % r.names.get(e["assist_pid"], "?")
			"and1":
				if bool(e.get("made", false)):
					pts = 1
					text = "%s finishes the and-one!" % name
				else:
					text = "%s misses the and-one freebie" % name
			"ft":
				pts = int(e.get("made", 0))
				text = "%s hits %d of %d at the line" % [name, int(e.get("made", 0)), int(e.get("att", 0))]
			"oreb":
				if bool(e.get("putback", false)):
					pts = 2
					text = "%s cleans the glass and puts it back!" % name
				else:
					text = "%s grabs the offensive board" % name
			"blk":
				text = "%s swats %s's shot" % [name, r.names.get(e.get("on_pid", -1), "the attempt")]
			"tov":
				if int(e.get("steal_pid", -1)) >= 0:
					text = "%s picks %s's pocket" % [r.names.get(e["steal_pid"], "?"), name]
				else:
					text = "%s coughs it up" % name
			_:
				text = "..."
		if is_home:
			home += pts
		else:
			away += pts
		out.append({"text": text, "home": home, "away": away, "home_play": is_home, "scored": pts > 0})
	return out
