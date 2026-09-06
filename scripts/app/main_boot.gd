extends Node
## Boot scene: validate catalog/stores, then route. Shows a recoverable error
## with Retry/Home on failure — never a fake course or silently unlocked
## content (docs/03 §8). No microphone activity ever happens here (UI-01).


func _ready() -> void:
	# Autoload stores loaded first (script order); check their state.
	var catalog := LevelCatalog.load_packaged()
	if not catalog.valid:
		_show_fatal("ERR_CATALOG_INVALID: " + ", ".join(catalog.errors.slice(0, 3)))
		return
	if not ProgressStore.ordered_ids().is_empty() and ProgressStore.data.is_empty():
		_show_fatal("ERR_PROGRESS_UNREADABLE")
		return
	var next := ProgressStore.next_playable_level()
	if next.is_empty():
		next = ProgressStore.ordered_ids()[0]
	AppRouter.goto_game(next)


func _show_fatal(code: String) -> void:
	var label := Label.new()
	label.text = "Roarball could not start.\n" + code
	add_child(label)
	var retry := RoarTheme.make_flat_button("Retry")
	retry.pressed.connect(func() -> void: get_tree().reload_current_scene())
	add_child(retry)
	var home := RoarTheme.make_flat_button("Home", true)
	home.pressed.connect(func() -> void: AppRouter.goto_home())
	add_child(home)
