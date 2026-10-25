class_name ClothSim
extends Node
## Cloth that moves: capes, skirts, sashes, tails and braids on a modelled
## unit swing, lag and settle with the body, on Godot's SpringBoneSimulator3D
## (native, a few bones per unit, so a full team fight stays cheap). The
## animated pose is what the springs pull toward, so authored motion stays;
## the sim adds inertia on top. Collision capsules on the torso and thighs
## keep cloth out of the body. View only: nothing here touches the sim.

## Chain roots and how they hang: [stiffness, drag, gravity, radius, length
## of the whole chain on the shared rig at hip height 0.96].
## Stiffness is low enough to trail on a sprint, high enough that cloth
## never flaps across the silhouette in a fight.
const CHAINS := {
	"cape": [1.4, 0.22, 1.3, 0.06, 0.62],
	"skirt_f": [2.6, 0.3, 0.8, 0.05, 0.5],
	"skirt_b": [2.2, 0.3, 0.8, 0.05, 0.51],
	"sash": [0.9, 0.4, 0.8, 0.03, 0.45],
	"braid": [1.0, 0.4, 0.9, 0.04, 0.37],
	"tail": [0.8, 0.38, 0.6, 0.04, 0.6],
	"scarf": [0.7, 0.36, 0.6, 0.03, 0.5],
}
## Body capsules: bone, radius as a share of the unit's hip height.
const BODY := {"hips": 0.15, "spine": 0.14, "chest": 0.15, "thigh_l": 0.075, "thigh_r": 0.075}

var _sim: SpringBoneSimulator3D
var _last := Vector3.ZERO
var _primed := false


## Adds cloth to a modelled unit. Minions get their skirts only and no
## collisions, so a wave costs next to nothing.
static func attach(model: Node3D, full := true) -> ClothSim:
	var found := model.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		return null
	var sk := found[0] as Skeleton3D
	var sim := SpringBoneSimulator3D.new()
	sim.name = "Cloth"
	var n := 0
	var roots: Array[int] = []
	for root: String in CHAINS:
		if not full and not root.begins_with("skirt"):
			continue
		var b := sk.find_bone(root)
		if b >= 0:
			roots.append(b)
	var scale := maxf(sk.get_bone_global_rest(maxi(sk.find_bone("hips"), 0)).origin.y, 0.5) / 0.96
	sim.setting_count = roots.size()
	for b in roots:
		var cfg: Array = CHAINS[sk.get_bone_name(b)]
		var end := _chain_end(sk, b)
		sim.set_root_bone(n, b)
		sim.set_end_bone(n, end)
		sim.set_extend_end_bone(n, true)
		sim.set_end_bone_direction(n, SpringBoneSimulator3D.BONE_DIRECTION_PLUS_Y)
		var links := 1
		var k := end
		while k != b:
			k = sk.get_bone_parent(k)
			links += 1
		sim.set_end_bone_length(n, float(cfg[4]) * scale / links)
		sim.set_stiffness(n, cfg[0])
		sim.set_drag(n, cfg[1])
		sim.set_gravity(n, cfg[2])
		sim.set_radius(n, cfg[3])
		n += 1
	if n == 0:
		sim.free()
		return null
	sk.add_child(sim)
	if full:
		var hip := scale * 0.96
		for bone: String in BODY:
			var bi := sk.find_bone(bone)
			if bi < 0:
				continue
			var cap := SpringBoneCollisionCapsule3D.new()
			var len := _bone_len(sk, bi)
			cap.bone = bi
			cap.radius = float(BODY[bone]) * hip
			cap.height = len + cap.radius * 2.0
			cap.position_offset = Vector3(0, len * 0.5, 0)
			sim.add_child(cap)
	var cs := ClothSim.new()
	cs._sim = sim
	sim.add_child(cs)
	return cs


## A chain runs down single children (cape, cape_1, cape_2; tail, tail2).
static func _chain_end(sk: Skeleton3D, b: int) -> int:
	var end := b
	while true:
		var kids := sk.get_bone_children(end)
		if kids.size() != 1:
			break
		end = kids[0]
	return end


static func _bone_len(sk: Skeleton3D, b: int) -> float:
	var kids := sk.get_bone_children(b)
	if not kids.is_empty():
		return sk.get_bone_rest(kids[0]).origin.length()
	return 0.3


## A blink or respawn moves the body metres in a frame; the cloth would
## whip across the map behind it, so the springs start again in place.
func _process(_delta: float) -> void:
	var p := _sim.get_parent() as Node3D
	var at := p.global_position
	if _primed and at.distance_squared_to(_last) > 4.0:
		_sim.reset()
	_last = at
	_primed = true
