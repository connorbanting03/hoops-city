class_name TestRunner
extends Node
## Reusable headless test base for the scaffold -> run -> verify loop.
##
## A test scene's root script `extends TestRunner` and overrides `run_tests()`.
## On ready it runs them, prints a greppable summary, and quits (exit 0 if all
## pass, 1 otherwise). The MCP launches the scene with run_project and reads the
## "RESULT: PASS" / "RESULT: FAIL" sentinel via get_debug_output to gate a milestone.

var _passed: int = 0
var _failed: int = 0
var _suite: String = "suite"

func _ready() -> void:
	_suite = name
	print("\n========== %s ==========" % _suite)
	run_tests()
	_finish()

# Override in subclasses.
func run_tests() -> void:
	pass

# --- assertions ---
func check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("  [PASS] %s" % label)
	else:
		_failed += 1
		print("  [FAIL] %s" % label)

func equal(actual: Variant, expected: Variant, label: String) -> void:
	check(actual == expected, "%s (expected %s, got %s)" % [label, str(expected), str(actual)])

func between(actual: float, lo: float, hi: float, label: String) -> void:
	check(actual >= lo and actual <= hi, "%s (expected [%s, %s], got %s)" % [label, str(lo), str(hi), str(actual)])

func approx(actual: float, expected: float, tol: float, label: String) -> void:
	check(absf(actual - expected) <= tol, "%s (expected %s +/-%s, got %s)" % [label, str(expected), str(tol), str(actual)])

func _finish() -> void:
	var total := _passed + _failed
	print("---------- %s: %d/%d passed ----------" % [_suite, _passed, total])
	if _failed > 0:
		print("RESULT: FAIL (%d/%d failed)" % [_failed, total])
	else:
		print("RESULT: PASS (%d/%d)" % [_passed, total])
	get_tree().quit(1 if _failed > 0 else 0)
