class_name WorldSave
extends Resource
## A serializable bundle of the whole game world. Resources nest automatically, so saving
## this writes the league (teams -> players) and city (buildings) in one file (GDD §7.5).

@export var version: int = 1
@export var year: int = 2026
@export var league: LeagueData
@export var city: CityData
