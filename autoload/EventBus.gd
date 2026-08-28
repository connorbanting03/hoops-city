extends Node
## EventBus — global signal hub (§7.2). Simulation systems EMIT here; UI and other
## systems LISTEN. Nothing calls across systems directly, so the sim stays headless
## and the presentation layer can be swapped or unit-tested independently.
##
## Add new signals per milestone as the systems that fire them come online.

# --- Match / season flow ---
# Signals are emitted from other systems (EventBus.<signal>.emit(...)), so GDScript's
# unused_signal check is a false positive here — silence it on this hub.
@warning_ignore("unused_signal")
signal game_finished(result)             # GameResult — after a game is simulated (M3)
@warning_ignore("unused_signal")
signal phase_changed(new_phase: String)  # off-season phase machine (M4/M9)
@warning_ignore("unused_signal")
signal day_advanced(day: int)            # cozy, player-paced time progression (M5/M6)

# --- Economy / city (wired in M5 / M6) ---
@warning_ignore("unused_signal")
signal economy_updated
@warning_ignore("unused_signal")
signal city_updated

# --- Presentation / shell (M10) ---
# A screen asks the shell to navigate; any screen can fire it without knowing the others.
@warning_ignore("unused_signal")
signal screen_requested(screen: String, context: Dictionary)
# The world changed (advanced a year / new game / built something) — chrome resyncs.
@warning_ignore("unused_signal")
signal world_changed
