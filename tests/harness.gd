extends "res://tests/TestRunner.gd"
## M0 smoke suite: proves the harness works and the foundation is wired — both
## autoloads load even when running an arbitrary /tests scene, the EventBus exposes
## its signals, and GameState save/load round-trips through versioned JSON.

func run_tests() -> void:
	check(1 + 1 == 2, "arithmetic sanity")

	# Autoloads must be present even though we launched a /tests scene directly —
	# this is the assumption the whole headless-gate strategy rests on.
	check(EventBus != null, "EventBus autoload reachable")
	check(EventBus.has_signal("game_finished"), "EventBus exposes game_finished")
	check(EventBus.has_signal("phase_changed"), "EventBus exposes phase_changed")
	check(GameState != null, "GameState autoload reachable")

	# Save/load round-trip with the version field (§7.5).
	var tmp := "user://_harness_roundtrip.json"
	GameState.reset()
	GameState.current_year = 2099
	GameState.current_phase = "draft"
	check(GameState.save_game(tmp), "save_game wrote file")

	GameState.reset()
	equal(GameState.current_year, GameState.DEFAULT_YEAR, "reset cleared year")

	check(GameState.load_game(tmp), "load_game read file")
	equal(GameState.current_year, 2099, "year survived round-trip")
	equal(GameState.current_phase, "draft", "phase survived round-trip")

	# best-effort cleanup; don't fail the suite on it
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
