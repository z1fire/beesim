extends Node
## Global game state (autoload "Game"): resources, upgrades, settings and saving.

signal changed
signal settings_changed
signal message(text: String)

const SAVE_PATH := "user://save.cfg"
const HONEY_PER_NECTAR := 0.5
const RIPEN_RATE := 1.5 # nectar per second the hive turns into honey
const SAVED_KEYS := [
	"nectar", "pollen", "hive_nectar", "hive_pollen", "honey", "total_honey", "pollinated",
	"third_person", "high_quality", "look_sensitivity", "invert_y", "seen_intro",
]

const UPGRADES := {
	"pouch": {"name": "Bigger Pouch", "desc": "Carry +10 nectar and +5 pollen", "honey": 8.0, "pollen": 0.0, "max": 10},
	"wings": {"name": "Swift Wings", "desc": "Fly 12% faster", "honey": 12.0, "pollen": 2.0, "max": 8},
	"stamina": {"name": "Royal Jelly", "desc": "+40 maximum energy", "honey": 10.0, "pollen": 4.0, "max": 8},
	"workers": {"name": "Raise a Worker", "desc": "A helper bee that gathers nectar", "honey": 20.0, "pollen": 10.0, "max": 12},
}

# carried by the bee
var nectar := 0.0
var pollen := 0.0
var energy := 100.0
# stored in the hive
var hive_nectar := 0.0
var hive_pollen := 0.0
var honey := 0.0
var total_honey := 0.0
var pollinated := 0
var levels := {"pouch": 0, "wings": 0, "stamina": 0, "workers": 0}

# settings
var third_person := true
var high_quality := true
var look_sensitivity := 1.0
var invert_y := false
var seen_intro := false

var _save_timer := 0.0


func _ready() -> void:
	_setup_input()
	load_game()
	energy = max_energy()


func _process(delta: float) -> void:
	if hive_nectar > 0.0:
		var amount := minf(hive_nectar, RIPEN_RATE * (1.0 + levels["workers"] * 0.1) * delta)
		hive_nectar -= amount
		honey += amount * HONEY_PER_NECTAR
		total_honey += amount * HONEY_PER_NECTAR
		changed.emit()
	_save_timer += delta
	if _save_timer > 20.0:
		save_game()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST \
			or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		save_game()


func nectar_capacity() -> float:
	return 20.0 + levels["pouch"] * 10.0


func pollen_capacity() -> float:
	return 10.0 + levels["pouch"] * 5.0


func max_energy() -> float:
	return 100.0 + levels["stamina"] * 40.0


func speed_multiplier() -> float:
	return 1.0 + levels["wings"] * 0.12


func upgrade_cost(id: String) -> Vector2:
	var info: Dictionary = UPGRADES[id]
	var mult := pow(1.6, levels[id])
	return Vector2(ceilf(info["honey"] * mult), ceilf(info["pollen"] * mult))


func can_upgrade(id: String) -> bool:
	if levels[id] >= UPGRADES[id]["max"]:
		return false
	var cost := upgrade_cost(id)
	return honey >= cost.x and hive_pollen >= cost.y


func buy_upgrade(id: String) -> bool:
	if not can_upgrade(id):
		return false
	var cost := upgrade_cost(id)
	honey -= cost.x
	hive_pollen -= cost.y
	levels[id] += 1
	if id == "stamina":
		energy = max_energy()
	changed.emit()
	save_game()
	return true


## Moves everything the bee carries into the hive. Returns (nectar, pollen) delivered.
func deposit() -> Vector2:
	var delivered := Vector2(nectar, pollen)
	hive_nectar += nectar
	hive_pollen += pollen
	nectar = 0.0
	pollen = 0.0
	changed.emit()
	return delivered


func save_game() -> void:
	_save_timer = 0.0
	var cfg := ConfigFile.new()
	for key in SAVED_KEYS:
		cfg.set_value("game", key, get(key))
	cfg.set_value("game", "levels", levels)
	cfg.save(SAVE_PATH)


func load_game() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	for key in SAVED_KEYS:
		if cfg.has_section_key("game", key):
			set(key, cfg.get_value("game", key))
	var saved: Dictionary = cfg.get_value("game", "levels", {})
	for key in saved:
		if levels.has(key):
			levels[key] = int(saved[key])


func _setup_input() -> void:
	_bind("move_forward", [KEY_W, KEY_UP])
	_bind("move_back", [KEY_S, KEY_DOWN])
	_bind("move_left", [KEY_A, KEY_LEFT])
	_bind("move_right", [KEY_D, KEY_RIGHT])
	_bind("ascend", [KEY_SPACE, KEY_E])
	_bind("descend", [KEY_Q, KEY_CTRL])
	_bind("boost", [KEY_SHIFT])
	_bind("toggle_camera", [KEY_V, KEY_C])
	_bind("hive_menu", [KEY_H, KEY_TAB])
	_bind("pause", [KEY_ESCAPE, KEY_P])


func _bind(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for key in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		InputMap.action_add_event(action, ev)
