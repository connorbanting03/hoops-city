extends "res://tests/TestRunner.gd"
## M1 gate: the player generator yields readable, archetype-shaped, height-aware
## players with sane bounds, a hidden potential ceiling, and reproducible output.

func _mean(players: Array, key: String) -> float:
	var s := 0.0
	for p in players:
		s += float(p.get_attr(key))
	return s / float(players.size())

func _mean_pot(players: Array) -> float:
	var s := 0.0
	for p in players:
		s += float(p.potential)
	return s / float(players.size())

func _mean_ovr(players: Array) -> float:
	var s := 0.0
	for p in players:
		s += float(p.overall())
	return s / float(players.size())

func _make(n: int, opts: Dictionary, seed_val: int) -> Array[PlayerData]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var out: Array[PlayerData] = []
	for i in n:
		out.append(PlayerGenerator.generate_player(rng, opts))
	return out

func run_tests() -> void:
	# 1. Archetypes produce recognizable shapes.
	var sharp := _make(300, {"archetype": "Sharpshooter"}, 101)
	check(_mean(sharp, "shooting") > 62.0, "Sharpshooter shooting high (%.1f)" % _mean(sharp, "shooting"))
	check(_mean(sharp, "shooting") > _mean(sharp, "interior_d") + 15.0, "Sharpshooter shoots >> defends inside")

	var rim := _make(300, {"archetype": "Rim Protector"}, 102)
	check(_mean(rim, "interior_d") > 62.0, "Rim Protector interior_d high (%.1f)" % _mean(rim, "interior_d"))
	check(_mean(rim, "rebounding") > 58.0, "Rim Protector rebounding high (%.1f)" % _mean(rim, "rebounding"))
	check(_mean(rim, "interior_d") > _mean(rim, "shooting") + 20.0, "Rim Protector defends >> shoots")

	var fg := _make(300, {"archetype": "Floor General"}, 103)
	check(_mean(fg, "playmaking") > 62.0, "Floor General playmaking high (%.1f)" % _mean(fg, "playmaking"))
	check(_mean(fg, "playmaking") > _mean(fg, "rebounding") + 20.0, "Floor General creates >> rebounds")

	# 2. Height trade-offs hold across a broad mixed population.
	var pop := _make(1500, {}, 200)
	var tall := []
	var short := []
	for p in pop:
		if p.height_cm >= 210:
			tall.append(p)
		elif p.height_cm <= 188:
			short.append(p)
	check(tall.size() > 30 and short.size() > 30, "enough tall (%d) and short (%d) samples" % [tall.size(), short.size()])
	check(_mean(short, "playmaking") > _mean(tall, "playmaking"), "short out-handle tall (%.1f vs %.1f)" % [_mean(short, "playmaking"), _mean(tall, "playmaking")])
	check(_mean(short, "athleticism") > _mean(tall, "athleticism"), "short more agile (%.1f vs %.1f)" % [_mean(short, "athleticism"), _mean(tall, "athleticism")])
	check(_mean(tall, "rebounding") > _mean(short, "rebounding"), "tall rebound more (%.1f vs %.1f)" % [_mean(tall, "rebounding"), _mean(short, "rebounding")])
	check(_mean(tall, "interior_d") > _mean(short, "interior_d"), "tall protect rim more (%.1f vs %.1f)" % [_mean(tall, "interior_d"), _mean(short, "interior_d")])

	# 3. Bounds + integrity on the big sample.
	var bounds_ok := true
	var ids := {}
	var uniq := true
	for p in pop:
		for key in PlayerData.ATTRS:
			var a := p.get_attr(key)
			if a < 1 or a > 99:
				bounds_ok = false
		if p.full_name().strip_edges() == "":
			bounds_ok = false
		if ids.has(p.id):
			uniq = false
		ids[p.id] = true
	check(bounds_ok, "all attributes in [1,99] and names non-empty")
	check(uniq, "generated ids unique across the batch")

	# 4. Potential is a ceiling, never below current OVR; Projects carry real upside.
	var pot_ok := true
	for p in pop:
		if p.potential < p.overall():
			pot_ok = false
	check(pot_ok, "potential >= current OVR for every player")
	var proj := _make(300, {"archetype": "Project"}, 104)
	check(_mean_pot(proj) > _mean_ovr(proj) + 12.0, "Projects carry big hidden upside (pot %.1f vs ovr %.1f)" % [_mean_pot(proj), _mean_ovr(proj)])

	# 5. OVR is position-sensitive (right tool at the right position).
	var rng := RandomNumberGenerator.new()
	rng.seed = 300
	var center := PlayerGenerator.generate_player(rng, {"archetype": "Rim Protector"})
	check(center.overall_for("C") > center.overall_for("PG"), "Rim Protector grades better at C than PG (%d vs %d)" % [center.overall_for("C"), center.overall_for("PG")])

	# 6. Determinism: same seed + opts -> identical player.
	var a1 := _make(1, {"archetype": "Slasher"}, 777)[0]
	var b1 := _make(1, {"archetype": "Slasher"}, 777)[0]
	check(a1.full_name() == b1.full_name() and a1.attributes == b1.attributes and a1.height_cm == b1.height_cm, "same seed reproduces an identical player")

	# 7. Ages within expected bounds.
	var age_ok := true
	for p in pop:
		if p.age < 19 or p.age > 36:
			age_ok = false
	check(age_ok, "ages within [19,36]")

	# Eyeball a few cards.
	print("\n--- sample players ---")
	for p in _make(6, {}, 4242):
		print("  " + p.summary_line())
