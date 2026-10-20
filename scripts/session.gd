class_name Session
## Choices that survive a scene reload (restart keeps the chosen mode).

static var mode: String = ""
## Champion the player picked on the menu (a ChampionDef id).
static var champion: StringName = &"ruinscribe"


## The pick as a ChampionDef, from data/champions/.
static func champion_def() -> ChampionDef:
	var path := "res://data/champions/%s.tres" % champion
	return load(path) if ResourceLoader.exists(path) else load("res://data/champions/ruinscribe.tres")
