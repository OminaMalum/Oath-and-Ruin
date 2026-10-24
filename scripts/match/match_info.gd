class_name MatchInfo
extends RefCounted
## Static facts about the match map that bots and the HUD may know:
## each team's fountain, lane direction and fallback position.

var fountains: Array[Vector3] = []
var hold_points: Array[Vector3] = []
var lane_dirs: Array[Vector3] = []
var slots := {}  # Unit -> slot index within its team
## For the objective's public state (announced to everyone).
var match_ctl: MatchController


## The neutral objective is open: awake (fight it) or capturable.
func objective_open() -> bool:
	return match_ctl != null and match_ctl.beast_state in [MatchController.Beast.AWAKE, MatchController.Beast.CAPTURE]


func objective_route(team: int) -> PackedVector3Array:
	var s := 1.0 if team == 0 else -1.0
	return PackedVector3Array([Vector3(-4, 0, s * 9.0), Vector3(-15, 0, s * 9.0), Vector3(-15, 0, 0), Vector3(-24, 0, 0)])


func fountain(team: int) -> Vector3:
	return fountains[team]


func hold_point(team: int) -> Vector3:
	return hold_points[team]


func lane_dir(team: int) -> Vector3:
	return lane_dirs[team]


func slot_of(u: Unit) -> int:
	return slots.get(u, 0)
