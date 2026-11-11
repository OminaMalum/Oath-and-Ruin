extends SceneTree
## Bootstrap: writes the starting champion and ability .tres files.
## After this the .tres files are the source of truth (edit them in the
## Godot inspector). Rerunning overwrites them.
## godot --headless --path . -s tools/make_data.gd

func _initialize() -> void:
	var bolt := AbilityDef.new()
	bolt.id = &"arcane_bolt"
	bolt.display_name = "Arcane Bolt"
	bolt.description = "Basic attack. A fast bolt along the aim line. Stops on the first enemy or wall. Dodge it by stepping out of the lane."
	bolt.delivery = AbilityDef.Delivery.PROJECTILE
	bolt.damage = 42.0
	bolt.cast_time = 0.15
	bolt.recovery = 0.25
	bolt.cooldown = 0.85
	bolt.move_mult_while_casting = 0.6
	bolt.range = 18.0
	bolt.projectile_speed = 32.0
	bolt.projectile_radius = 0.3
	_save(bolt, "res://data/abilities/arcane_bolt.tres")

	var glyph := AbilityDef.new()
	glyph.id = &"binding_glyph"
	glyph.display_name = "Binding Glyph"
	glyph.description = "Inscribe a glyph on the ground at the aim point. It shows its full size and fills up, then bursts: damage and a short slow. Counterplay: walk out before it fills."
	glyph.delivery = AbilityDef.Delivery.GROUND_AREA
	glyph.damage = 85.0
	glyph.cast_time = 0.3
	glyph.recovery = 0.2
	glyph.cooldown = 7.0
	glyph.move_mult_while_casting = 0.4
	glyph.range = 14.0
	glyph.area_radius = 2.6
	glyph.area_delay = 0.75
	glyph.slow_amount = 0.35
	glyph.slow_duration = 1.5
	_save(glyph, "res://data/abilities/binding_glyph.tres")

	var sling := AbilityDef.new()
	sling.id = &"dummy_sling"
	sling.display_name = "Sparring Shot"
	sling.description = "Training dummy shot: long windup with a lane on the ground, slow projectile. Teaches dodging."
	sling.delivery = AbilityDef.Delivery.PROJECTILE
	sling.damage = 55.0
	sling.cast_time = 0.7
	sling.recovery = 0.3
	sling.cooldown = 2.2
	sling.move_mult_while_casting = 0.0
	sling.range = 16.0
	sling.projectile_speed = 16.0
	sling.projectile_radius = 0.4
	_save(sling, "res://data/abilities/dummy_sling.tres")

	var scribe := ChampionDef.new()
	scribe.id = &"ruinscribe"
	scribe.display_name = "Ruinscribe"
	scribe.role = "Ranged spellcaster"
	scribe.look = ChampionDef.Look.SPELLCASTER
	scribe.max_health = 560.0
	scribe.move_speed = 6.2
	scribe.respawn_time = 5.0
	scribe.basic_attack = load("res://data/abilities/arcane_bolt.tres")
	scribe.abilities = [load("res://data/abilities/binding_glyph.tres") as AbilityDef]
	scribe.primary_color = Color(0.40, 0.12, 0.11)  # oxblood robe
	scribe.accent_color = Color(0.25, 0.80, 0.78)
	_save(scribe, "res://data/champions/ruinscribe.tres")

	var dummy := ChampionDef.new()
	dummy.id = &"training_dummy"
	dummy.display_name = "Training Dummy"
	dummy.role = "Target"
	dummy.look = ChampionDef.Look.TRAINING_DUMMY
	dummy.max_health = 900.0
	dummy.move_speed = 0.0
	dummy.respawn_time = 4.0
	dummy.basic_attack = load("res://data/abilities/dummy_sling.tres")
	dummy.primary_color = Color(0.74, 0.62, 0.38)
	dummy.accent_color = Color(1.0, 0.62, 0.20)
	_save(dummy, "res://data/champions/training_dummy.tres")
	quit(0)


func _save(r: Resource, path: String) -> void:
	var err := ResourceSaver.save(r, path)
	print("saved %s (%s)" % [path, error_string(err)])
