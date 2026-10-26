class_name Ragdoll
extends SkeletonModifier3D
## A death that falls with weight: when a modelled unit dies its skeleton
## goes limp under physics (capsule bodies with cone joints), thrown away
## from the killer, and crumples on the map floor. Built only at the moment
## of death and freed on respawn, so living units cost nothing. View only:
## the bodies sit on no collision layer (nothing in the sim can touch or
## see them) and only collide with the world.
##
## The rig keeps its feet under the root (they are IK targets), so this
## modifier also carries each foot along with its shin while limp.

## bone -> [capsule radius as a share of hip height, mass, cone swing deg, twist deg]
const BODIES := {
	"hips": [0.14, 3.0, 0.0, 0.0],
	"spine": [0.13, 2.5, 25.0, 15.0],
	"chest": [0.15, 3.0, 25.0, 15.0],
	"head": [0.11, 1.2, 40.0, 30.0],
	"upper_arm_l": [0.05, 0.8, 80.0, 30.0],
	"upper_arm_r": [0.05, 0.8, 80.0, 30.0],
	"forearm_l": [0.045, 0.6, 55.0, 10.0],
	"forearm_r": [0.045, 0.6, 55.0, 10.0],
	"thigh_l": [0.075, 1.8, 55.0, 15.0],
	"thigh_r": [0.075, 1.8, 55.0, 15.0],
	"shin_l": [0.06, 1.2, 50.0, 5.0],
	"shin_r": [0.06, 1.2, 50.0, 5.0],
}

var _sim: PhysicalBoneSimulator3D
var _feet: Array = []  # [foot, shin, shin->foot rest]
var _kick := Vector3.ZERO


## Makes the model's skeleton go limp, pushed along `push` (world, m/s).
static func fall(model: Node3D, push: Vector3) -> Ragdoll:
	var found := model.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		return null
	var sk := found[0] as Skeleton3D
	var hip_b := sk.find_bone("hips")
	if hip_b < 0:
		return null
	var scale := maxf(sk.get_bone_global_rest(hip_b).origin.y, 0.4) / 0.96
	var sim := PhysicalBoneSimulator3D.new()
	sim.name = "Ragdoll"
	for bone: String in BODIES:
		var b := sk.find_bone(bone)
		if b < 0:
			continue
		var cfg: Array = BODIES[bone]
		var pb := PhysicalBone3D.new()
		pb.name = "pb_" + bone
		pb.bone_name = bone
		pb.mass = float(cfg[1])
		pb.friction = 0.9
		pb.bounce = 0.0
		pb.linear_damp = 0.4
		pb.angular_damp = 3.0
		pb.collision_layer = 0
		pb.collision_mask = Unit.LAYER_WORLD
		if bone != "hips":
			pb.joint_type = PhysicalBone3D.JOINT_TYPE_CONE
			pb.set("joint_constraints/swing_span", float(cfg[2]))
			pb.set("joint_constraints/twist_span", float(cfg[3]))
			pb.set("joint_constraints/softness", 0.8)
			pb.set("joint_constraints/relaxation", 1.0)
		var len := _length(sk, b, scale)
		var cs := CollisionShape3D.new()
		var r := float(cfg[0]) * scale
		if bone == "head":
			var sp := SphereShape3D.new()
			sp.radius = r
			cs.shape = sp
		else:
			var cap := CapsuleShape3D.new()
			cap.radius = r
			cap.height = maxf(len, r * 2.0 + 0.01)
			cs.shape = cap
		cs.position = Vector3(0, len * 0.5, 0)
		pb.add_child(cs)
		sim.add_child(pb)
	var rd := Ragdoll.new()
	rd.name = "RagdollFeet"
	rd._sim = sim
	rd._kick = push
	for side: String in ["l", "r"]:
		var f := sk.find_bone("foot_" + side)
		var s := sk.find_bone("shin_" + side)
		if f >= 0 and s >= 0:
			rd._feet.append([f, s, sk.get_bone_global_rest(s).affine_inverse() * sk.get_bone_global_rest(f)])
	# Order on the skeleton: clips, BodyReact, the limp bodies, the feet,
	# then the cloth, so capes fall with the body.
	var at := 0
	for i in sk.get_child_count():
		if sk.get_child(i) is BodyReact:
			at = i + 1
	sk.add_child(sim)
	sk.move_child(sim, at)
	sk.add_child(rd)
	sk.move_child(rd, at + 1)
	rd._start.call_deferred()
	return rd


static func _length(sk: Skeleton3D, b: int, scale: float) -> float:
	var kids := sk.get_bone_children(b)
	var best := 0.0
	for k in kids:
		var name := sk.get_bone_name(k)
		if name.begins_with("skirt") or name.begins_with("cape") or name.begins_with("shoulder") or name == "sash" or name == "tail":
			continue
		best = maxf(best, sk.get_bone_rest(k).origin.length())
	if best <= 0.0:
		best = (0.2 if sk.get_bone_name(b) == "head" else 0.25) * scale
	return best


func _start() -> void:
	if not is_instance_valid(_sim):
		return
	_sim.physical_bones_start_simulation()
	for c in _sim.get_children():
		var pb := c as PhysicalBone3D
		if pb == null:
			continue
		# The blow lands on the torso; the limbs follow through the joints.
		var w := 1.6 if pb.bone_name in [&"chest", &"head"] else (1.0 if pb.bone_name == &"spine" else 0.4)
		pb.apply_central_impulse(_kick * pb.mass * w)


## Frees the bodies and lets the clips drive the skeleton again.
func stand() -> void:
	if is_instance_valid(_sim):
		_sim.physical_bones_stop_simulation()
		_sim.queue_free()
	queue_free()


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	for f: Array in _feet:
		sk.set_bone_global_pose(f[0], sk.get_bone_global_pose(f[1]) * (f[2] as Transform3D))
