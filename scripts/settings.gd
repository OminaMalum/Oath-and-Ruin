class_name Settings
## Player settings and the match record, saved in user://settings.cfg so they
## survive a restart of the game. Read once, applied at startup.

const PATH := "user://settings.cfg"
const DIFFICULTY_NAMES: Array[String] = ["Easy", "Normal", "Hard"]

## 0 to 1, the master bus.
static var volume: float = 0.8
## Multiplier on the camera's mouse sensitivity (0.4 to 2.5).
static var mouse_sensitivity: float = 1.0
static var fullscreen: bool = false
## Enemy bots: 0 Easy, 1 Normal, 2 Hard.
static var difficulty: int = 1
## Shop catalog: true the adventurer items (recipes, boots, selling), false
## the four classic items.
static var adventurer_items: bool = true
## Matches finished from the menu, per difficulty.
static var wins: Array[int] = [0, 0, 0]
static var losses: Array[int] = [0, 0, 0]
static var _loaded := false


static func load_once() -> void:
	if _loaded:
		return
	_loaded = true
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	volume = clampf(float(cf.get_value("audio", "volume", volume)), 0.0, 1.0)
	mouse_sensitivity = clampf(float(cf.get_value("controls", "mouse_sensitivity", mouse_sensitivity)), 0.4, 2.5)
	fullscreen = bool(cf.get_value("display", "fullscreen", fullscreen))
	difficulty = clampi(int(cf.get_value("match", "difficulty", difficulty)), 0, 2)
	adventurer_items = bool(cf.get_value("match", "adventurer_items", adventurer_items))
	for i in 3:
		wins[i] = maxi(0, int(cf.get_value("record", "wins_%d" % i, 0)))
		losses[i] = maxi(0, int(cf.get_value("record", "losses_%d" % i, 0)))


static func save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("audio", "volume", volume)
	cf.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	cf.set_value("display", "fullscreen", fullscreen)
	cf.set_value("match", "difficulty", difficulty)
	cf.set_value("match", "adventurer_items", adventurer_items)
	for i in 3:
		cf.set_value("record", "wins_%d" % i, wins[i])
		cf.set_value("record", "losses_%d" % i, losses[i])
	cf.save(PATH)


## Volume and window mode. Headless runs (tests, soaks) are left alone.
static func apply() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.0001)))
	AudioServer.set_bus_mute(0, volume <= 0.001)
	if DisplayServer.get_name() == "headless":
		return
	var want := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != want:
		DisplayServer.window_set_mode(want)


static func record(won: bool) -> void:
	if won:
		wins[difficulty] += 1
	else:
		losses[difficulty] += 1
	save()


static func record_text() -> String:
	var w := wins[difficulty]
	var l := losses[difficulty]
	if w + l == 0:
		return "No %s matches played yet" % DIFFICULTY_NAMES[difficulty]
	return "Your record on %s: %d %s, %d %s" % [DIFFICULTY_NAMES[difficulty], w, "win" if w == 1 else "wins", l, "loss" if l == 1 else "losses"]
