class_name BodyReact
extends SkeletonModifier3D
## Weight on top of the clips: the torso leans into a sprint and a strafe,
## rocks back when the body stops or turns hard, and flinches away from a
## hit. A damped spring on the spine and chest, after the AnimationTree and
## before the cloth (so capes react to it). View only.

const STIFF := 90.0     # spring rate (1/s^2)
const DAMP := 13.0      # slightly under critical, so a stop rocks once
const LEAN_FWD := 0.14  # rad of forward lean at full run speed
const LEAN_SIDE := 0.10
const LEAN_TURN := 0.06
const HIT := 2.6        # rad/s kicked into the spring by a hit

var _spine := -1
var _chest := -1
var _head := -1
var _off := Vector2.ZERO  # x pitch (+ back), y roll (+ to the right)
var _vel := Vector2.ZERO
var _target := Vector2.ZERO


static func attach(model: Node3D) -> BodyReact:
	var found := model.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		return null
	var sk := found[0] as Skeleton3D
	var r := BodyReact.new()
	r.name = "BodyReact"
	r._spine = sk.find_bone("spine")
	r._chest = sk.find_bone("chest")
	r._head = sk.find_bone("head")
	if r._spine < 0:
		r.free()
		return null
	sk.add_child(r)
	sk.move_child(r, 0)  # before ClothSim's spring bones
	return r


## move: velocity in the model's frame over top speed (x right, y forward);
## turn: yaw rate (rad/s).
func drive(move: Vector2, turn: float) -> void:
	_target = Vector2(-move.y * LEAN_FWD, move.x * LEAN_SIDE - clampf(turn, -6.0, 6.0) * LEAN_TURN * move.length())


## A hit from `from_dir` (the model's frame, x right, y forward, toward the
## attacker): the torso is knocked away from it.
func hit(from_dir: Vector2, strength := 1.0) -> void:
	var d := from_dir.normalized() if from_dir.length() > 0.01 else Vector2(0, 1)
	_vel += Vector2(d.y, -d.x) * HIT * clampf(strength, 0.3, 1.5)


## A cast's windup draws the torso back a little ...
func anticipate() -> void:
	_vel.x += 0.9


## ... and the release throws it into the strike, settling after.
func strike() -> void:
	_vel.x -= 2.2


func _process_modification_with_delta(delta: float) -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	var dt := minf(delta, 0.05)
	var acc := (_target - _off) * STIFF - _vel * DAMP
	_vel += acc * dt
	_off += _vel * dt
	_off = _off.clamp(Vector2(-0.45, -0.4), Vector2(0.45, 0.4))
	_bend(sk, _spine, 0.55)
	_bend(sk, _chest, 0.45)
	if _head >= 0:
		_bend(sk, _head, -0.5)  # the head stays level-ish, eyes on the fight


func _bend(sk: Skeleton3D, b: int, share: float) -> void:
	if b < 0:
		return
	var g := sk.get_bone_global_pose(b)
	var r := Basis(Vector3.RIGHT, _off.x * share) * Basis(Vector3.BACK, -_off.y * share)
	g.basis = r * g.basis
	sk.set_bone_global_pose(b, g)
