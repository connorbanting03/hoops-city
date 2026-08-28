class_name BuildingData
extends Resource
## One constructed building in the city. Its category and base outputs live in the
## CityManager catalog; tier multiplies those outputs (and the next upgrade's cost).

@export var type: String = ""
@export var tier: int = 1
