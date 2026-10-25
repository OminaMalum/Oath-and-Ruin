class_name ModelAnimator
extends RefCounted
## Plays an imported model's clips through an AnimationTree so they layer:
## a basic attack or ability thrown while moving plays on the upper body and
## the legs keep running (no sliding in a standing pose). Standing still, the
## cast clip drives the whole body as authored. Idle and run cross-blend by
## speed, and death takes over everything. View only: every timing comes
## from the sim, this only chooses what to draw.

## Bones the legs own: from the run while moving, from the cast while still.
const LOWER := ["root", "hips", "thigh_l", "shin_l", "foot_l", "thigh_r", "shin_r", "foot_r",
	"skirt_f", "skirt_f_1", "skirt_b", "skirt_b_1", "tail", "tail2"]

var tree: AnimationTree
var _player: AnimationPlayer
var _move := 0.0        # 0 idle .. 1 run, smoothed
var _cast_w := 0.0
var _cast_clip := ""
var _cast_t := 0.0      # clip time played so far
var _cast_speed := 1.0
var _cast_len := 0.0
var _dead := false
var run_phase := 0.0    # 0..1 through the run cycle, for footsteps
var _run_len := 0.6


func _init(player: AnimationPlayer) -> void:
	_player = player
	var bt := AnimationNodeBlendTree.new()
	var idle := AnimationNodeAnimation.new()
	idle.animation = &"idle"
	var run := AnimationNodeAnimation.new()
	run.animation = &"run"
	bt.add_node("idle", idle)
	bt.add_node("run", run)
	bt.add_node("run_ts", AnimationNodeTimeScale.new())
	bt.connect_node("run_ts", 0, "run")
	bt.add_node("loco", AnimationNodeBlend2.new())
	bt.connect_node("loco", 0, "idle")
	bt.connect_node("loco", 1, "run_ts")
	# Two copies of the cast clip, one per layer, so each advances once.
	var lower_paths: Array[NodePath] = []
	var upper_paths: Array[NodePath] = []
	var skel_path := ""
	for clip: StringName in player.get_animation_list():
		var a := player.get_animation(clip)
		for i in a.get_track_count():
			var p := a.track_get_path(i)
			var bone := p.get_concatenated_subnames()
			if skel_path.is_empty() and not bone.is_empty():
				skel_path = String(p.get_concatenated_names())
	var sk := player.get_parent().find_children("*", "Skeleton3D", true, false)
	if not sk.is_empty():
		var s := sk[0] as Skeleton3D
		for b in s.get_bone_count():
			var np := NodePath("%s:%s" % [skel_path, s.get_bone_name(b)])
			if s.get_bone_name(b) in LOWER:
				lower_paths.append(np)
			else:
				upper_paths.append(np)
	for layer: String in ["cu", "cl"]:
		var c := AnimationNodeAnimation.new()
		c.animation = &"idle"
		bt.add_node(layer, c)
		bt.add_node(layer + "_seek", AnimationNodeTimeSeek.new())
		bt.connect_node(layer + "_seek", 0, layer)
		bt.add_node(layer + "_ts", AnimationNodeTimeScale.new())
		bt.connect_node(layer + "_ts", 0, layer + "_seek")
	var up := AnimationNodeBlend2.new()
	up.filter_enabled = true
	for p in upper_paths:
		up.set_filter_path(p, true)
	bt.add_node("up", up)
	bt.connect_node("up", 0, "loco")
	bt.connect_node("up", 1, "cu_ts")
	var low := AnimationNodeBlend2.new()
	low.filter_enabled = true
	for p in lower_paths:
		low.set_filter_path(p, true)
	bt.add_node("low", low)
	bt.connect_node("low", 0, "up")
	bt.connect_node("low", 1, "cl_ts")
	var death := AnimationNodeAnimation.new()
	death.animation = &"death"
	bt.add_node("death", death)
	bt.add_node("death_seek", AnimationNodeTimeSeek.new())
	bt.connect_node("death_seek", 0, "death")
	bt.add_node("dead", AnimationNodeBlend2.new())
	bt.connect_node("dead", 0, "low")
	bt.connect_node("dead", 1, "death_seek")
	bt.connect_node("output", 0, "dead")
	tree = AnimationTree.new()
	tree.name = "Layers"
	tree.tree_root = bt
	player.get_parent().add_child(tree)
	tree.root_node = tree.get_path_to(player.get_node(player.root_node))
	tree.anim_player = tree.get_path_to(player)
	player.active = false
	tree.active = true
	if player.has_animation(&"run"):
		_run_len = maxf(player.get_animation(&"run").length, 0.1)
	for k: String in ["run_ts", "cu_ts", "cl_ts"]:
		tree.set("parameters/%s/scale" % k, 1.0)


## A cast clip from its start; `speed` stretches the windup onto the sim's.
func cast(clip: String, speed: float) -> void:
	if not _player.has_animation(clip):
		return
	_cast_clip = clip
	_cast_t = 0.0
	_cast_speed = speed
	_cast_len = _player.get_animation(clip).length
	var bt := tree.tree_root as AnimationNodeBlendTree
	for layer: String in ["cu", "cl"]:
		(bt.get_node(layer) as AnimationNodeAnimation).animation = StringName(clip)
		tree.set("parameters/%s_seek/seek_request" % layer, 0.0)
		tree.set("parameters/%s_ts/scale" % layer, speed)
	_cast_w = maxf(_cast_w, 0.6)


## True while the cast clip still has frames to show.
func casting() -> bool:
	return not _cast_clip.is_empty() and _cast_t < _cast_len


func end_cast() -> void:
	_cast_clip = ""


func die() -> void:
	if _dead:
		return
	_dead = true
	tree.set("parameters/death_seek/seek_request", 0.0)


func revive() -> void:
	_dead = false
	_cast_clip = ""
	_cast_w = 0.0


## moving: 0..1 how much the legs run; rate: run playback rate (negative
## plays the cycle backwards for a backpedal); hold: keep the cast layer up
## (the sim is still in a cast phase).
func update(delta: float, moving: float, rate: float, hold: bool) -> void:
	var k := 1.0 - exp(-12.0 * delta)
	_move = lerpf(_move, moving, k)
	if not _cast_clip.is_empty():
		_cast_t += delta * _cast_speed
	var want := 1.0 if (casting() or (hold and not _cast_clip.is_empty())) else 0.0
	if want == 0.0 and _cast_w < 0.02:
		_cast_clip = ""
	_cast_w = lerpf(_cast_w, want, 1.0 - exp(-(30.0 if want > _cast_w else 9.0) * delta))
	tree.set("parameters/loco/blend_amount", _move)
	tree.set("parameters/run_ts/scale", rate)
	tree.set("parameters/up/blend_amount", _cast_w)
	tree.set("parameters/low/blend_amount", _cast_w * (1.0 - _move))
	tree.set("parameters/dead/blend_amount", 1.0 if _dead else 0.0)
	if _move > 0.05:
		run_phase = fposmod(run_phase + delta * rate / _run_len, 1.0)
