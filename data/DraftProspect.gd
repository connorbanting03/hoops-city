class_name DraftProspect
extends Resource
## A draft prospect: the TRUE young player (hidden) plus the public scouting picture. The UI
## shows estimates and ranges that tighten toward the truth as you spend scouting budget —
## so a smart scout finds the steal nobody else saw (GDD §4.5).

@export var player: PlayerData            # the true ratings, hidden until scouted/drafted
@export var uncertainty: float = 1.0      # 1 = totally unknown, 0 = fully scouted
@export var stock: int = 0                # public consensus draft stock (blends current + upside)
@export var projected_range: String = ""
@export var errors: Dictionary = {}        # attr -> fixed N(0,1) scouting error sample

const NOISE_SCALE := 14.0
const BAND_SCALE := 12.0

## Best current read of an attribute: drifts from a noisy guess toward the truth as
## uncertainty falls to 0.
func estimate(attr: String) -> int:
	var tru := player.get_attr(attr)
	return clampi(int(round(float(tru) + float(errors.get(attr, 0.0)) * uncertainty * NOISE_SCALE)), 1, 99)

func attr_range(attr: String) -> Array:
	var est := estimate(attr)
	var band := int(round(uncertainty * BAND_SCALE))
	return [maxi(1, est - band), mini(99, est + band)]

func scouted_ovr() -> int:
	var weights: Dictionary = PlayerData.POSITION_WEIGHTS.get(player.primary_pos, {})
	if weights.is_empty():
		return 0
	var tot := 0.0
	var wsum := 0.0
	for k in weights:
		tot += float(estimate(k)) * float(weights[k])
		wsum += float(weights[k])
	return int(round(tot / wsum)) if wsum > 0.0 else 0

func true_ovr() -> int:
	return player.overall()
