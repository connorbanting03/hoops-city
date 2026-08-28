class_name CityManager
extends RefCounted
## The city engine (GDD §5). Population = housing capacity x attractiveness, where
## attractiveness is driven by jobs, amenities, civic quality, AND team success — so a
## winning team grows the city. Population then drives market_size, which raises the team's
## effective budget back in EconomyManager. That feedback is the shared hub of the flywheel.
##
## Endless but balanced: upgrade costs scale faster than outputs, and market_size grows with
## log(population) so a metropolis helps a lot but never makes money infinite.

const TIER_OUT_MULT := 1.8       # output per tier
const TIER_COST_MULT := 2.2      # upgrade cost per tier (scales faster than output)
const BUILD_ESCALATION := 1.35   # each added building of a category costs more
const STARTER_POP := 1500.0
const MARKET_REF_POP := 1500.0   # population that maps to the baseline market_size of 0.7
const POP_GROWTH_RATE := 0.34
const AMEN_REF := 120.0
const CIVIC_REF := 150.0
const POP_DIV_REF := 100000.0

const CATALOG := {
	"apartments": {"category": "residential", "cost": 2_000_000, "housing": 1500.0},
	"condo_tower": {"category": "residential", "cost": 9_000_000, "housing": 6000.0},
	"shops": {"category": "commercial", "cost": 1_500_000, "jobs": 900.0, "dividend": 1_400_000.0},
	"office": {"category": "commercial", "cost": 7_000_000, "jobs": 4500.0, "dividend": 6_000_000.0},
	"hotel": {"category": "tourism", "cost": 5_000_000, "dividend": 4_500_000.0},
	"theater": {"category": "entertainment", "cost": 1_400_000, "amenity": 35.0},
	"park": {"category": "civic", "cost": 3_000_000, "civic": 45.0},
	"monument": {"category": "civic", "cost": 25_000_000, "civic": 120.0},
}

const OUTPUT_KEYS := ["housing", "jobs", "dividend", "amenity", "civic"]
const OUTPUT_LABELS := {
	"housing": "housing", "jobs": "jobs", "dividend": "dividend/yr",
	"amenity": "amenity", "civic": "civic",
}

static func category(type: String) -> String:
	return CATALOG[type]["category"]

static func _out(b: BuildingData, key: String) -> float:
	return float(CATALOG[b.type].get(key, 0.0)) * pow(TIER_OUT_MULT, b.tier - 1)

## A building's current (tier-scaled) outputs, only the non-zero ones — for the City screen.
static func building_outputs(b: BuildingData) -> Dictionary:
	var out := {}
	for k in OUTPUT_KEYS:
		var v := _out(b, k)
		if v != 0.0:
			out[k] = v
	return out

## A catalog type's base (tier-1) outputs, for the build menu preview.
static func type_outputs(type: String) -> Dictionary:
	var out := {}
	for k in OUTPUT_KEYS:
		var v := float(CATALOG[type].get(k, 0.0))
		if v != 0.0:
			out[k] = v
	return out

static func count_category(city: CityData, cat: String) -> int:
	var n := 0
	for b in city.buildings:
		if category(b.type) == cat:
			n += 1
	return n

static func build_cost(city: CityData, type: String) -> int:
	var existing := count_category(city, CATALOG[type]["category"])
	return int(round(float(CATALOG[type]["cost"]) * pow(BUILD_ESCALATION, existing)))

static func build(city: CityData, type: String) -> BuildingData:
	var b := BuildingData.new()
	b.type = type
	city.buildings.append(b)
	return b

static func upgrade_cost(b: BuildingData) -> int:
	return int(round(float(CATALOG[b.type]["cost"]) * pow(TIER_COST_MULT, b.tier)))

static func upgrade(b: BuildingData) -> void:
	b.tier += 1

# --- aggregate outputs ---

static func housing_capacity(city: CityData) -> float:
	var h := 0.0
	for b in city.buildings:
		h += _out(b, "housing")
	return h

static func jobs(city: CityData) -> float:
	var j := 0.0
	for b in city.buildings:
		j += _out(b, "jobs")
	return j

static func amenities(city: CityData) -> float:
	var a := 0.0
	for b in city.buildings:
		a += _out(b, "amenity")
	return a

static func civic_points(city: CityData) -> float:
	var c := 0.0
	for b in city.buildings:
		c += _out(b, "civic")
	return c

## Fill rate in [0.05, 1.0]: how full the city's housing gets, driven by jobs/amenities/
## civic quality and — critically — team success (a winning team makes the town desirable).
static func attractiveness(city: CityData, team_success: float) -> float:
	var cap := maxf(housing_capacity(city), 1.0)
	var job_ratio := jobs(city) / cap
	var jobs_term := job_ratio / (job_ratio + 0.8)
	var amen_term := 1.0 - exp(-amenities(city) / AMEN_REF)
	var civic_term := 1.0 - exp(-civic_points(city) / CIVIC_REF)
	return clampf(0.15 + 0.30 * jobs_term + 0.25 * amen_term + 0.10 * civic_term + 0.20 * clampf(team_success, 0.0, 1.0), 0.05, 1.0)

static func target_population(city: CityData, team_success: float) -> float:
	return housing_capacity(city) * attractiveness(city, team_success)

static func advance_population(city: CityData, team_success: float, steps: int = 1) -> void:
	var target := target_population(city, team_success)
	for i in steps:
		city.population += (target - city.population) * POP_GROWTH_RATE

## Passive income from commercial (scales with population) and tourism (scales with
## attractiveness + team success). Feeds EconomyManager as the dividends line.
static func dividends(city: CityData, team_success: float) -> float:
	var pop_scale := city.population / POP_DIV_REF
	var att := attractiveness(city, team_success)
	var total := 0.0
	for b in city.buildings:
		var cat := category(b.type)
		if cat == "commercial":
			total += _out(b, "dividend") * pop_scale
		elif cat == "tourism":
			total += _out(b, "dividend") * (0.5 + att + clampf(team_success, 0.0, 1.0) * 0.5)
	return total

## Population -> market_size, on a log curve so growth is endless but diminishing.
static func market_size(city: CityData) -> float:
	return 0.7 + 0.5 * (log(maxf(city.population, MARKET_REF_POP) / MARKET_REF_POP) / log(10.0))

static func generate_starter_city() -> CityData:
	var c := CityData.new()
	c.name = "Granite City"
	c.population = STARTER_POP
	for i in 4:
		build(c, "apartments")
	for i in 2:
		build(c, "shops")
	build(c, "theater")
	return c
