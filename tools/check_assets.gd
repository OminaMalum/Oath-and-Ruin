extends SceneTree
## Asset contract check for champion models (see docs/ASSET_CONTRACT.md).
##
##   godot --headless --path . -s tools/check_assets.gd -- [FILES...] [--spec=DIR]
##
## FILES are .glb or .gltf paths (default: every file in assets/champions/ and
## assets/units/; minion models live in assets/units/ and check against data/units/).
## The champion is taken from the file name (ruinscribe.glb, or
## ruinscribe_v2.glb: the part before the first "_v"), the windup release
## times from FILE.timing.json next to it (tools/blender/export_champion.py
## writes it from pose markers). --spec=DIR writes one JSON spec per champion
## for artists and the Blender template script, then exits.
## Exit code = number of files with errors.

const CHAMPIONS := "res://data/champions/"
const UNITS := "res://data/units/"
const MINIONS: Array[StringName] = [&"minion_melee", &"minion_caster", &"minion_breaker"]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var files: PackedStringArray = []
	var spec_dir := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--spec="):
			spec_dir = a.trim_prefix("--spec=")
		elif not a.begins_with("--"):
			files.append(a)
	if not spec_dir.is_empty():
		quit(_write_specs(spec_dir))
		return
	if files.is_empty():
		for sub in ["res://assets/champions", "res://assets/units"]:
			var dir := ProjectSettings.globalize_path(sub)
			for f in DirAccess.get_files_at(dir):
				if f.get_extension() in ["glb", "gltf"]:
					files.append(dir.path_join(f))
	if files.is_empty():
		print("No models to check (put .glb files in assets/champions/).")
		quit(0)
		return
	var bad := 0
	for f in files:
		bad += 1 if not await _check_file(f) else 0
	print("%d of %d models pass the contract" % [files.size() - bad, files.size()])
	quit(bad)


func _check_file(path: String) -> bool:
	var id := path.get_file().get_basename().get_slice("_v", 0).to_lower()
	var def_path := CHAMPIONS + id + ".tres"
	if not ResourceLoader.exists(def_path):
		def_path = UNITS + id + ".tres"
	print("\n== %s (champion %s)" % [path, id])
	if not ResourceLoader.exists(def_path):
		print("ERROR no champion called '%s' in %s (name the file after the champion id)" % [id, CHAMPIONS])
		return false
	var def := load(def_path) as ChampionDef
	var scene := AssetContract.load_gltf(path)
	if scene == null:
		print("ERROR could not read the file as glTF 2.0")
		return false
	root.add_child(scene)  # the AnimationPlayer needs the tree to pose bones
	await process_frame
	var timing := {}
	var tpath := path.get_basename() + ".timing.json"
	if FileAccess.file_exists(tpath):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(tpath))
		if parsed is Dictionary:
			timing = (parsed as Dictionary).get("release", {})
	var r := AssetContract.check(scene, def, timing)
	scene.queue_free()
	for e: String in r.errors:
		print("ERROR " + e)
	for w: String in r.warnings:
		print("WARN  " + w)
	print("measured " + JSON.stringify(r.measured))
	print("PASS" if r.errors.is_empty() else "FAIL (%d errors)" % r.errors.size())
	return r.errors.is_empty()


func _write_specs(dir: String) -> int:
	DirAccess.make_dir_recursive_absolute(dir)
	for f in DirAccess.get_files_at(CHAMPIONS):
		if f.get_extension() != "tres":
			continue
		var def := load(CHAMPIONS + f) as ChampionDef
		if def == null or def.kind != ChampionDef.Kind.CHAMPION:
			continue
		var out := dir.path_join(String(def.id) + ".json")
		var fa := FileAccess.open(out, FileAccess.WRITE)
		fa.store_string(JSON.stringify(AssetContract.spec(def), "  ", false) + "\n")
		print("wrote " + out)
	for id in MINIONS:
		var def := load(UNITS + String(id) + ".tres") as ChampionDef
		var out := dir.path_join(String(id) + ".json")
		var fa := FileAccess.open(out, FileAccess.WRITE)
		fa.store_string(JSON.stringify(AssetContract.spec(def), "  ", false) + "\n")
		print("wrote " + out)
	return 0
