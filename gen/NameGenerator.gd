class_name NameGenerator
extends RefCounted
## Procedural player names. Deterministic when driven by a seeded RNG.

const FIRST := [
	"James", "Marcus", "Andre", "Tyrese", "Darius", "Malik", "Devin", "Jalen",
	"Cole", "Brandon", "Isaiah", "Trey", "Quentin", "Damon", "Elijah", "Xavier",
	"Roman", "Dominic", "Theo", "Kaden", "Silas", "Mateo", "Nikola", "Luka",
	"Bojan", "Dejan", "Omar", "Rashid", "Kofi", "Amare", "Jaylen", "Deron",
	"Cyrus", "Bennett", "Grayson", "Hugo", "Emory", "Zane", "Oscar", "Felix",
	"Reggie", "Vance", "Marquis", "Donovan", "Terrence", "Lamar", "Cedric", "Otis",
	"Nash", "Ezra",
]

const LAST := [
	"Carter", "Brooks", "Hayes", "Bennett", "Coleman", "Ferguson", "Sutton", "Vance",
	"Mercer", "Dalton", "Okafor", "Mensah", "Petrovic", "Volkov", "Nakamura", "Reyes",
	"Castillo", "Okoye", "Adebayo", "Walsh", "Donovan", "Pryor", "Sullivan", "Knox",
	"Ramsey", "Holloway", "Webb", "Pierce", "Quinn", "Marsh", "Beckett", "Cross",
	"Sterling", "Maddox", "Ellison", "Grant", "Boone", "Fontaine", "Larsson", "Voss",
	"Abara", "Calderon", "Diallo", "Eriksen", "Fournier", "Galang", "Haddad", "Ivanov",
	"Jennings", "Kowalski",
]

static func first_name(rng: RandomNumberGenerator) -> String:
	return FIRST[rng.randi() % FIRST.size()]

static func last_name(rng: RandomNumberGenerator) -> String:
	return LAST[rng.randi() % LAST.size()]
