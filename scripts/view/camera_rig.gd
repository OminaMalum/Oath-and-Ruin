class_name CameraRig
extends Node3D
## Over-the-shoulder third-person camera. Mouse turns yaw and pitch; the
## champion faces the camera yaw. It reads unit positions and never changes
## gameplay state. Aim is a ray through the screen-centre reticle.

@export var sensitivity: float = 0.0025
@export var distance: float = 6.5
@export var shoulder_offset: float = 0.9
@export var pivot_height: float = 2.3
@export var min_pitch_deg: float = -50.0
@export var max_pitch_deg: float = 10.0
## Follow smoothing (higher = tighter). Keeps motion calm without lag in aim.
@export var follow_sharpness: float = 18.0

var target: Unit
## Captures and spectating: copy the unit's facing instead of the mouse.
var follow_unit_yaw: bool = false
## Spectator overview (recordings): a high view behind the followed unit
## looking down the lane, so both teams and the wave are in frame.
var overview: bool = false
const FOLLOW_DEADBAND_DEG := 2.0
const FOLLOW_MAX_DEG := 240.0
const OVERVIEW_OFFSET := Vector3(0, 24, 18)
var yaw: float = 0.0
var pitch: float = deg_to_rad(-16.0)

var _arm: SpringArm3D
var camera: Camera3D


func _ready() -> void:
	top_level = true
	# Moved every rendered frame from interpolated positions, so the engine
	# must not interpolate it again.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_arm = SpringArm3D.new()
	_arm.spring_length = distance
	_arm.margin = 0.2
	# Walls and structures push the camera in; other units never do.
	_arm.collision_mask = Unit.LAYER_WORLD | Unit.LAYER_STRUCTURE
	var probe := SphereShape3D.new()
	probe.radius = 0.25
	_arm.shape = probe
	add_child(_arm)
	camera = Camera3D.new()
	camera.fov = 70.0
	camera.near = 0.1
	camera.far = 300.0
	_arm.add_child(camera)
	snap_to_target()


func snap_to_target() -> void:
	if target and is_inside_tree():
		yaw = target.aim_yaw
		global_position = _pivot()


func _pivot() -> Vector3:
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	return target.get_global_transform_interpolated().origin + Vector3(0, pivot_height, 0) + right * shoulder_offset


func mouse_captured() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and mouse_captured():
		var m := event as InputEventMouseMotion
		yaw = wrapf(yaw - m.relative.x * sensitivity, -PI, PI)
		pitch = clampf(pitch - m.relative.y * sensitivity, deg_to_rad(min_pitch_deg), deg_to_rad(max_pitch_deg))
	elif event is InputEventMouseButton and event.pressed and not mouse_captured():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("release_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(delta: float) -> void:
	if target == null:
		return
	if overview:
		_arm.spring_length = 0.0
		yaw = 0.0
		pitch = deg_to_rad(-52.0)
		var goal_o := target.get_global_transform_interpolated().origin + OVERVIEW_OFFSET
		global_position = global_position.lerp(goal_o, 1.0 - exp(-4.0 * delta))
		rotation = Vector3(pitch, yaw, 0.0)
		return
	if follow_unit_yaw:
		# Bot follow policy: ease toward the unit's facing, ignore wobble under
		# FOLLOW_DEADBAND, and never turn faster than FOLLOW_MAX_DEG a second.
		var diff := wrapf(target.aim_yaw - yaw, -PI, PI)
		if absf(diff) > deg_to_rad(FOLLOW_DEADBAND_DEG):
			var want := diff * (1.0 - exp(-6.0 * delta))
			var cap := deg_to_rad(FOLLOW_MAX_DEG) * delta
			yaw = wrapf(yaw + clampf(want, -cap, cap), -PI, PI)
	var goal := _pivot()
	global_position = global_position.lerp(goal, 1.0 - exp(-follow_sharpness * delta))
	rotation = Vector3(pitch, yaw, 0.0)
	_keep_body_visible(delta)


## The spring arm only tests the line to the head. A low wall edge between
## the camera and the champion's hips left the body hidden while the arm
## stayed long, so this also tests a ray to the hips and pulls the arm in
## until that line is clear. It eases back out when the view opens up.
const HIP_HEIGHT := 0.9
const ARM_MIN := 1.6
func _keep_body_visible(delta: float) -> void:
	if not is_inside_tree():
		return
	var space := get_world_3d().direct_space_state
	var hip := target.get_global_transform_interpolated().origin + Vector3(0, HIP_HEIGHT, 0)
	var back := -global_transform.basis.z * -1.0  # arm extends along local +Z (SpringArm3D convention)
	var length := minf(_arm.spring_length + 3.0 * delta, distance)
	while length > ARM_MIN:
		var cam := global_position + back * length
		var q := PhysicsRayQueryParameters3D.create(cam, hip, Unit.LAYER_WORLD | Unit.LAYER_STRUCTURE)
		if space.intersect_ray(q).is_empty():
			break
		length -= 0.3
	_arm.spring_length = maxf(length, ARM_MIN)


## What the reticle is over: first world or unit surface along the camera
## ray. Falls back to a far point along the ray. The caster's own body is
## ignored. Gameplay keeps only the flat direction, so this mostly matters
## for ground-targeted abilities.
func get_aim_point(unit: Unit) -> Vector3:
	if camera == null or not camera.is_inside_tree():
		return unit.global_position + unit.forward() * 10.0
	var vp := get_viewport()
	var centre := vp.get_visible_rect().size * 0.5
	var from := camera.project_ray_origin(centre)
	var dir := camera.project_ray_normal(centre)
	var to := from + dir * 120.0
	var q := PhysicsRayQueryParameters3D.create(from, to, Unit.LAYER_WORLD | Unit.LAYER_UNITS, [unit.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var point: Vector3 = hit.position if not hit.is_empty() else to
	# Points behind or beside the champion (shoulder parallax) fall back to
	# straight ahead along the camera yaw.
	var flat := Vector3(point.x - unit.global_position.x, 0.0, point.z - unit.global_position.z)
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	if flat.length() < 1.0 or flat.normalized().dot(fwd) < 0.5:
		point = unit.global_position + fwd * 8.0
	return point
