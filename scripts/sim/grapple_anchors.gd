class_name GrappleAnchors
extends RefCounted
## Which walls a grapple chain may hook onto. The rule lives here, in one
## place, instead of in each map builder: a static box at least MIN_HEIGHT
## tall that stands on the floor (not the floor itself), inside the playable
## stretch of the map. Base plazas (the spawn and fountain) are left out, and
## so is anything without collision (trees, banners, rubble are decoration).
## Approved bodies get Unit.LAYER_ANCHOR beside Unit.LAYER_WORLD.

const MIN_HEIGHT := 2.0


## Marks every approved wall under `root`. `keep_out_z`: walls whose centre
## lies further than this from z = 0 (the base plazas) are not anchors.
static func mark(root: Node, keep_out_z: float = INF) -> int:
	var n := 0
	for body: StaticBody3D in root.find_children("*", "StaticBody3D", true, false):
		if body.collision_layer & Unit.LAYER_WORLD == 0 or absf(body.global_position.z) > keep_out_z:
			continue
		for shape: CollisionShape3D in body.find_children("*", "CollisionShape3D", false, false):
			var box := shape.shape as BoxShape3D
			if box and box.size.y >= MIN_HEIGHT and body.global_position.y > 0.0:
				body.collision_layer |= Unit.LAYER_ANCHOR
				n += 1
				break
	return n
