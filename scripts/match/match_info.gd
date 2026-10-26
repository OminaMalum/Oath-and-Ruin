class_name MatchInfo
extends RefCounted
## Static facts about the match map that bots and the HUD may know:
## each team's fountain, lane direction and fallback position.

var fountains: Array[Vector3] = []
var hold_points: Array[Vector3] = []
var lane_dirs: Array[Vector3] = []
var slots := {}  # Unit -> slot index within its team
## Lane centres (world x). One lane: [0]. Three lanes: slot 0 mid, 1 west, 2 east.
var lanes: Array[float] = [0.0]
## Where a team's base opens onto the lanes (z, own side, positive).
var base_z: float = 46.0
## The walk to the neutral camp, per team (four points, the last at the camp).
var routes: Array[PackedVector3Array] = []
## Three lanes: the west lane's walk to the camp, per team.
var routes_west: Array[PackedVector3Array] = []
## For the objective's public state (announced to everyone).
var match_ctl: MatchController


## The neutral objective is open: awake (fight it) or capturable.
func objective_open() -> bool:
	return match_ctl != null and match_ctl.beast_state in [MatchController.Beast.AWAKE, MatchController.Beast.CAPTURE]


## Which slots take the camp: the two nearest it. One lane: slots 1 and 2
## (slot 0 holds the lane). Three lanes: mid and west (the camp is west).
func objective_slot(slot: int) -> bool:
	return slot in ([0, 1] if lanes.size() >= 3 else [1, 2])


func objective_route(team: int, slot := 0) -> PackedVector3Array:
	if slot == 1 and not routes_west.is_empty():
		return routes_west[team]
	if not routes.is_empty():
		return routes[team]
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


## The lane a champion plays (world x of its centre).
func lane_x(u: Unit) -> float:
	if lanes.size() < 3:
		return lanes[0]
	return lanes[[1, 0, 2][slot_of(u) % 3]]
