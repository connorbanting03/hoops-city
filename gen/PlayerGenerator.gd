class_name PlayerGenerator
extends RefCounted
## Procedural player generation (GDD §4.1): pick archetype -> seed ratings from its
## template -> modulate by height -> assign age + hidden potential -> add variance.
## All randomness flows through a passed RNG so generation is reproducible.

const BASE := 48        # neutral attribute baseline before bias/height/talent/noise
const REF_HEIGHT := 198 # ~6'6", the neutral height for modulation

# Per-attribute height slope (points per cm relative to REF_HEIGHT). Taller biases
# toward the paint and away from handling/quickness/shooting — height has consequences.
const HEIGHT_SLOPE := {
	"inside": 0.16, "interior_d": 0.22, "rebounding": 0.24, "strength": 0.18,
	"athleticism": -0.22, "playmaking": -0.26, "perimeter_d": -0.16,
	"shooting": -0.10, "stamina": -0.06, "iq": 0.0,
}

# Each archetype is a generation template: eligible positions, a height band, a flat
# talent shift (stars vs role players), a hidden-potential bonus, and per-attribute bias.
const ARCHETYPES := {
	"Sharpshooter": {"pos": ["SG", "SF"], "height": [190, 201], "talent": 0, "pot_bonus": 0,
		"bias": {"shooting": 24, "iq": 6, "playmaking": 4, "inside": -4, "interior_d": -10, "rebounding": -10, "strength": -8, "athleticism": -2}},
	"Slasher": {"pos": ["SG", "SF"], "height": [193, 203], "talent": 0, "pot_bonus": 2,
		"bias": {"inside": 18, "athleticism": 16, "perimeter_d": 4, "strength": 4, "shooting": -6, "interior_d": -4}},
	"Floor General": {"pos": ["PG"], "height": [183, 193], "talent": 0, "pot_bonus": 0,
		"bias": {"playmaking": 24, "iq": 14, "shooting": 6, "perimeter_d": 4, "athleticism": 8, "inside": -2, "interior_d": -12, "rebounding": -12, "strength": -8}},
	"3-and-D Wing": {"pos": ["SG", "SF"], "height": [196, 206], "talent": 0, "pot_bonus": 0,
		"bias": {"perimeter_d": 18, "shooting": 14, "athleticism": 6, "playmaking": -4, "inside": -2}},
	"Two-Way Star": {"pos": ["SG", "SF", "PF"], "height": [198, 208], "talent": 12, "pot_bonus": 6,
		"bias": {"perimeter_d": 10, "athleticism": 10, "inside": 10, "shooting": 8, "iq": 8, "playmaking": 6, "rebounding": 4}},
	"Rim Protector": {"pos": ["C"], "height": [208, 221], "talent": 0, "pot_bonus": 2,
		"bias": {"interior_d": 24, "rebounding": 18, "strength": 14, "inside": 8, "shooting": -18, "playmaking": -16, "perimeter_d": -8, "athleticism": -2}},
	"Stretch Big": {"pos": ["PF", "C"], "height": [206, 216], "talent": 2, "pot_bonus": 2,
		"bias": {"shooting": 20, "rebounding": 8, "inside": 6, "interior_d": 6, "strength": 6, "playmaking": -6, "perimeter_d": -4, "athleticism": -4}},
	"Bruiser": {"pos": ["PF", "C"], "height": [203, 213], "talent": 0, "pot_bonus": 0,
		"bias": {"strength": 20, "inside": 16, "rebounding": 16, "interior_d": 12, "shooting": -16, "playmaking": -10, "athleticism": -6}},
	"Glue Guy": {"pos": ["SF", "PF"], "height": [196, 206], "talent": -8, "pot_bonus": 0,
		"bias": {"iq": 14, "perimeter_d": 10, "rebounding": 8, "athleticism": 4, "stamina": 6}},
	"Project": {"pos": ["SF", "PF", "C"], "height": [198, 213], "talent": -12, "pot_bonus": 22,
		"bias": {"athleticism": 6, "strength": 6, "shooting": -6, "playmaking": -4, "iq": -8}},
}

static func archetype_names() -> Array:
	return ARCHETYPES.keys()

## Generate one player. `opts` may pin: archetype, pos, age, id.
static func generate_player(rng: RandomNumberGenerator, opts: Dictionary = {}) -> PlayerData:
	var arch_name: String = opts.get("archetype", "")
	if arch_name == "":
		arch_name = _pick(ARCHETYPES.keys(), rng)
	var arch: Dictionary = ARCHETYPES[arch_name]

	var p := PlayerData.new()
	p.archetype = arch_name
	p.id = int(opts.get("id", rng.randi() & 0x7fffffff))
	p.first_name = NameGenerator.first_name(rng)
	p.last_name = NameGenerator.last_name(rng)

	var pos: String = opts.get("pos", "")
	if pos == "":
		pos = _pick(arch["pos"], rng)
	p.primary_pos = pos

	p.height_cm = _rand_band(rng, int(arch["height"][0]), int(arch["height"][1]))
	p.age = int(opts.get("age", clampi(int(round(rng.randfn(26.0, 3.8))), 19, 36)))

	# One talent roll shifts every rating together -> a spread of stars and scrubs.
	# opts.talent_bonus lets the league/draft/FA layers tilt a whole roster up or down.
	var talent := rng.randfn(float(arch.get("talent", 0)) + float(opts.get("talent_bonus", 0.0)), 7.0)
	var bias: Dictionary = arch["bias"]
	var dict := {}
	for key in PlayerData.ATTRS:
		var v := float(BASE)
		v += float(bias.get(key, 0))
		v += float(HEIGHT_SLOPE.get(key, 0.0)) * float(p.height_cm - REF_HEIGHT)
		v += talent
		v += rng.randfn(0.0, 4.5)
		dict[key] = clampi(int(round(v)), 1, 99)
	p.attributes = dict

	# Hidden potential: a ceiling at or above current OVR, bigger for youth + raw archetypes.
	var cur := p.overall()
	var youth_upside := maxf(0.0, float(24 - p.age)) * 1.4
	var upside := youth_upside + float(arch.get("pot_bonus", 0)) + rng.randf_range(0.0, 6.0)
	p.potential = clampi(cur + int(round(upside)), cur, 99)

	p.durability = clampi(int(round(rng.randfn(62.0, 14.0))), 20, 99)
	p.morale = clampi(int(round(rng.randfn(70.0, 8.0))), 30, 99)
	return p

static func _pick(arr: Array, rng: RandomNumberGenerator) -> Variant:
	return arr[rng.randi() % arr.size()]

static func _rand_band(rng: RandomNumberGenerator, lo: int, hi: int) -> int:
	# Average of two uniforms -> mild central tendency within the band.
	return int(round((rng.randf_range(float(lo), float(hi)) + rng.randf_range(float(lo), float(hi))) * 0.5))
