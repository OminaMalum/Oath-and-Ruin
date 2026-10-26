extends SceneTree
## Finds surfaces that can z-fight (flicker): pairs of mesh faces that face
## the same way, lie within a few millimetres of each other and overlap.
## Only meshes whose transform keeps their box axis aligned are compared,
## which covers the walls, plinths, caps, steps and floor dressing.
## godot --headless --path . -s tools/coplanar_check.gd -- --mode=match --spectate --warp=25

const EPS := 0.003

var _main: Node
var _done := false


func _initialize() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if _done:
		return true
	var warp: float = _main.get("_warp_until")
	if warp > 0.0:
		return false
	_done = true
	_check()
	return true


func _check() -> void:
	var boxes: Array = []
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if not mi.is_visible_in_tree() or mi.mesh == null:
			continue
		var b := mi.global_transform.basis
		if not _axis_aligned(b):
			continue
		var aabb := mi.global_transform * mi.get_aabb()
		var mat := mi.material_override if mi.material_override else mi.mesh.surface_get_material(0)
		boxes.append([aabb, mi, mat, _kind(mi.mesh)])
	print("checking ", boxes.size(), " axis aligned meshes")
	var hits := 0
	for i in boxes.size():
		var a: AABB = boxes[i][0]
		for j in range(i + 1, boxes.size()):
			var c: AABB = boxes[j][0]
			if not a.grow(EPS).intersects(c.grow(EPS)):
				continue
			for axis in 3:
				for sgn in [-1.0, 1.0]:
					var pa: float = a.end[axis] if sgn > 0.0 else a.position[axis]
					var pc: float = c.end[axis] if sgn > 0.0 else c.position[axis]
					if absf(pa - pc) > EPS:
						continue
					# Bottoms resting on the floor face down and are never seen.
					if axis == 1 and sgn < 0.0 and absf(pa) < 0.06:
						continue
					# Same material and world-space texture: identical pixels, no flicker.
					if boxes[i][2] == boxes[j][2] and boxes[i][2] != null:
						continue
					# Only flat faces: a box face or a cylinder cap on Y.
					if not (_flat(boxes[i][3], axis) and _flat(boxes[j][3], axis)):
						continue
					var area := _overlap(a, c, axis)
					if area < 0.0004:
						continue
					hits += 1
					if hits <= 80:
						print("Z-FIGHT %s%s d=%.4f area=%.3f  %s  <->  %s" % ["+-"[0 if sgn > 0.0 else 1], "XYZ"[axis],
							absf(pa - pc), area, _name(boxes[i][1]), _name(boxes[j][1])])
	print("coplanar pairs: ", hits)


func _axis_aligned(b: Basis) -> bool:
	for v in [b.x.normalized(), b.y.normalized(), b.z.normalized()]:
		var m := maxf(absf(v.x), maxf(absf(v.y), absf(v.z)))
		if m < 0.9999:
			return false
	return true


func _kind(m: Mesh) -> String:
	if m is BoxMesh:
		return "box"
	if m is CylinderMesh:
		return "cyl"
	return "other"


func _flat(kind: String, axis: int) -> bool:
	return kind == "box" or (kind == "cyl" and axis == 1)


func _overlap(a: AABB, c: AABB, axis: int) -> float:
	var area := 1.0
	for k in 3:
		if k == axis:
			continue
		var lo := maxf(a.position[k], c.position[k])
		var hi := minf(a.end[k], c.end[k])
		if hi <= lo:
			return 0.0
		area *= hi - lo
	return area


func _name(mi: MeshInstance3D) -> String:
	var p := mi.global_transform.origin
	return "%s(%s) @(%.2f, %.2f, %.2f)" % [mi.get_parent().name + "/" + mi.name, _kind(mi.mesh), p.x, p.y, p.z]
