class_name BenchProbe
extends Node
## Repeatable fight benchmark (start with -- --bench, usually with a fixed
## --seed, --spectate --follow=N and --warp=S so the same fight is on screen
## every run). Waits for the warp to end, then records frame time, GPU time,
## draw calls, objects, primitives, lights and live particle emitters for
## BENCH_SECONDS of real time, writes the summary to user://bench.txt, prints
## it and quits. Reads the render state only; changes nothing in the match.

const BENCH_SECONDS := 20.0

var _t := 0.0
var _started := false
var _frames: Array[float] = []
var _gpu: Array[float] = []
var _draws: Array[int] = []
var _prims: Array[int] = []
var _objs: Array[int] = []
var _emitters: Array[int] = []
var _lights: Array[int] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	var main := get_tree().current_scene
	if not _started:
		if main == null or float(main.get("_warp_until")) > 0.0:
			return
		_started = true
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
		return
	_t += delta
	var vp := get_viewport()
	_frames.append(delta * 1000.0)
	_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(vp.get_viewport_rid()))
	_draws.append(vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME))
	_prims.append(vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME))
	_objs.append(vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_OBJECTS_IN_FRAME))
	if _frames.size() % 15 == 0:
		var e := 0
		for p in get_tree().root.find_children("*", "CPUParticles3D", true, false):
			if (p as CPUParticles3D).emitting and (p as CPUParticles3D).is_visible_in_tree():
				e += 1
		_emitters.append(e)
		_lights.append(get_tree().root.find_children("*", "OmniLight3D", true, false).size())
	if _t >= BENCH_SECONDS:
		_finish()


static func _pct(a: Array, p: float) -> float:
	if a.is_empty():
		return 0.0
	var s := a.duplicate()
	s.sort()
	return float(s[clampi(int(round((s.size() - 1) * p)), 0, s.size() - 1)])


func _finish() -> void:
	var ultra := "--ultra" in OS.get_cmdline_user_args()
	var lines := PackedStringArray()
	lines.append("PactFall fight benchmark  %s  %s  %dx%d  %s" % [Time.get_datetime_string_from_system(), "ultra" if ultra else "normal",
			get_viewport().size.x, get_viewport().size.y, RenderingServer.get_video_adapter_name()])
	lines.append("args: %s" % " ".join(OS.get_cmdline_user_args()))
	lines.append("frames %d over %.1f s, average %.1f fps" % [_frames.size(), _t, _frames.size() / maxf(_t, 0.001)])
	lines.append("frame ms   median %.2f  p95 %.2f  p99 %.2f  worst %.2f" % [_pct(_frames, 0.5), _pct(_frames, 0.95), _pct(_frames, 0.99), _pct(_frames, 1.0)])
	lines.append("gpu ms     median %.2f  p95 %.2f  worst %.2f" % [_pct(_gpu, 0.5), _pct(_gpu, 0.95), _pct(_gpu, 1.0)])
	lines.append("draw calls median %d  max %d" % [_pct(_draws, 0.5), _pct(_draws, 1.0)])
	lines.append("objects    median %d  max %d" % [_pct(_objs, 0.5), _pct(_objs, 1.0)])
	lines.append("primitives median %d  max %d" % [_pct(_prims, 0.5), _pct(_prims, 1.0)])
	lines.append("emitters   median %d  max %d   omni lights max %d" % [_pct(_emitters, 0.5), _pct(_emitters, 1.0), _pct(_lights, 1.0)])
	var text := "\n".join(lines)
	print(text)
	var f := FileAccess.open("user://bench.txt", FileAccess.WRITE_READ if FileAccess.file_exists("user://bench.txt") else FileAccess.WRITE)
	if f:
		f.seek_end()
		f.store_string(text + "\n\n")
	get_tree().quit()
