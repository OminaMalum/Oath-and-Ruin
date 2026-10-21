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
	# Walls push the camera in. Towers and cores do not: a tower right
	# behind the champion pulled the camera into its face and hid the
	# champion (2:45 on seed 31). They fade out instead (_fade_structures).
	_arm.collision_mask = Unit.LAYER_WORLD
	var probe := SphereShape3D.new()
	probe.radius = 0.25
	_arm.shape = probe
	add_child(_arm)
	camera = Camera3D.new()
	camera.fov = 70.0
	camera.near = 0.1
	camera.far = 300.0
	# The camera is not the arm's child: the arm snaps to its hit length both
	# ways, which popped the view up to 6.5 m in one frame when a wall edge
	# cleared (camera audit). The camera follows the arm's length, in at
	# once (never through a wall), out at ARM_OUT_SPEED.
	add_child(camera)
	snap_to_target()


func snap_to_target() -> void:
	if target and is_inside_tree():
		yaw = target.aim_yaw
		global_position = _pivot()
		_cam_d = distance  # pulled in next frame if a wall is there


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
		camera.position = Vector3.ZERO
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
	var want_d := _arm.get_hit_length()
	_cam_d = want_d if want_d < _cam_d else minf(_cam_d + ARM_OUT_SPEED * delta, want_d)
	camera.position = Vector3(0, 0, _cam_d)
	_fade_structures()
	if audit:
		_audit_sample()


## The spring arm only tests the line to the head. A low wall edge between
## the camera and the champion's hips left the body hidden while the arm
## stayed long, so this also tests a ray to the hips and pulls the arm in
## until that line is clear. It eases back out when the view opens up.
const HIP_HEIGHT := 0.9
const ARM_OUT_SPEED := 6.0  # metres per second the view eases back out
var _cam_d := 0.0
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
		var q := PhysicsRayQueryParameters3D.create(cam, hip, Unit.LAYER_WORLD)
		if space.intersect_ray(q).is_empty():
			break
		length -= 0.3
	_arm.spring_length = maxf(length, ARM_MIN)


## Fade any tower or core between the camera and the champion, or within
## 4 m of the camera, for this frame. View only.
func _fade_structures() -> void:
	var space := get_world_3d().direct_space_state
	var cam := camera.global_position
	var base := target.get_global_transform_interpolated().origin
	var hits: Array[Unit] = []
	for h: float in [HIP_HEIGHT, target.def.height * 0.9]:
		var exclude: Array[RID] = []
		for i in 3:
			var q := PhysicsRayQueryParameters3D.create(cam, base + Vector3(0, h, 0), Unit.LAYER_STRUCTURE, exclude)
			var r := space.intersect_ray(q)
			if r.is_empty():
				break
			if r.collider is Unit and not hits.has(r.collider):
				hits.append(r.collider)
			exclude.append(r.rid)
	var probe := PhysicsShapeQueryParameters3D.new()
	var ball := SphereShape3D.new()
	ball.radius = 4.0  # a tower this close fills the screen and hides the fight behind it
	probe.shape = ball
	probe.transform = Transform3D(Basis(), cam)
	probe.collision_mask = Unit.LAYER_STRUCTURE
	for r in space.intersect_shape(probe, 4):
		if r.collider is Unit and not hits.has(r.collider):
			hits.append(r.collider)
	for u in hits:
		for c in u.get_children():
			if c is UnitView:
				(c as UnitView).fade_for_camera()


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


## Camera audit (--camaudit): per rendered frame, is the followed champion's
## head and hips in clear view, how long is the arm, how far did the camera
## jump. Printed as one CAMAUDIT line when the run ends.
var audit := false
var audit_stats := {"frames": 0, "head_blocked": 0, "hip_blocked": 0, "both_blocked": 0, "short_arm": 0, "jumps": 0, "max_jump": 0.0, "yaw_steps_over_10": 0, "jumps_arm_in": 0, "jumps_target_fast": 0}
var _audit_last_pos := Vector3.INF
var _audit_last_yaw := 0.0
var _audit_last_d := 0.0
func _audit_sample() -> void:
	if camera == null or not target.alive:
		_audit_last_pos = Vector3.INF
		return
	var space := get_world_3d().direct_space_state
	var cam := camera.global_position
	var base := target.get_global_transform_interpolated().origin
	var mask := Unit.LAYER_WORLD  # towers and cores fade, so only walls hide the champion
	var head := space.intersect_ray(PhysicsRayQueryParameters3D.create(cam, base + Vector3(0, target.def.height * 0.9, 0), mask))
	var hip := space.intersect_ray(PhysicsRayQueryParameters3D.create(cam, base + Vector3(0, HIP_HEIGHT, 0), mask))
	var st := audit_stats
	st.frames += 1
	if not head.is_empty():
		st.head_blocked += 1
	if not hip.is_empty():
		st.hip_blocked += 1
	if not head.is_empty() and not hip.is_empty():
		st.both_blocked += 1
	if _arm.get_hit_length() < 2.5:
		st.short_arm += 1
	if _audit_last_pos != Vector3.INF:
		var j := cam.distance_to(_audit_last_pos)
		st.max_jump = maxf(st.max_jump, j)
		if j > 0.6:  # more than 0.6 m in one 60 Hz frame is a visible pop
			st.jumps += 1
			if _cam_d < _audit_last_d - 0.4:
				st.jumps_arm_in += 1  # pulled in by a wall: by design, never through it
			elif target.velocity.length() > target.def.move_speed * 1.5:
				st.jumps_target_fast += 1  # dash or knockback
		if absf(wrapf(yaw - _audit_last_yaw, -PI, PI)) > deg_to_rad(10.0):
			st.yaw_steps_over_10 += 1
	_audit_last_pos = cam
	_audit_last_yaw = yaw
	_audit_last_d = _cam_d
