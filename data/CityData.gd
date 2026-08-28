class_name CityData
extends Resource
## The player's city (GDD §5). Population is tracked as a single number — never a node per
## resident — so it scales to millions on any hardware. Buildings give it capacity and pull.

@export var name: String = "Granite City"
@export var population: float = 1500.0
@export var buildings: Array[BuildingData] = []
@export var unlocked_districts: int = 1
