extends Node
## AppRouter autoload: top-level screen transitions with exactly one active
## gameplay session (docs/03 §3). Never loads arbitrary scene paths — the
## home/game scenes are packaged, and level ids resolve through the
## validated catalog only.

const MAIN_SCENE := "res://scenes/app/main.tscn"
const HOME_SCENE := "res://scenes/app/home.tscn"
const GAME_SCENE := "res://scenes/game/game_root.tscn"

var current_level_id := ""


func goto_home() -> void:
	current_level_id = ""
	_deferred_change(HOME_SCENE)


func goto_game(level_id: String) -> void:
	var catalog := LevelCatalog.load_packaged()
	if not catalog.valid or not catalog.ordered_ids.has(level_id):
		push_error("Refusing to load unknown level id: " + level_id)
		goto_home()
		return
	if not catalog.is_playable(level_id):
		# A save may point past the last built scene (e.g. test/dev progress):
		# recover to the next playable hole, never a fake course.
		var fallback := ProgressStore.next_playable_level()
		if fallback.is_empty():
			push_error("No playable level scenes exist.")
			goto_home()
			return
		level_id = fallback
	current_level_id = level_id
	ProgressStore.set_last_played(level_id)
	_deferred_change(GAME_SCENE)


## Scene changes from _ready (boot) are rejected by the tree; always defer.
func _deferred_change(path: String) -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file.call_deferred(path)


func is_in_level() -> bool:
	return not current_level_id.is_empty()


## Android Back: dismiss top sheet first, pause gameplay second. The gameplay
## HUD installs itself as the sheet owner while active (docs/06 §6).
var _back_handler: Callable = Callable()

func set_back_handler(handler: Callable) -> void:
	_back_handler = handler


func clear_back_handler(handler: Callable) -> void:
	if _back_handler == handler:
		_back_handler = Callable()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		var handled := false
		if _back_handler.is_valid():
			var result: Variant = _back_handler.call()
			handled = bool(result)
		if not handled and is_in_level() and not get_tree().paused:
			goto_home()
		get_viewport().set_input_as_handled()
