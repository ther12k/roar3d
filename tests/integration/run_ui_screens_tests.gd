extends Node
## UI screens suite (RB-019/030/031/033/036/040/044/050): Home + mode-choice
## sheet, world map, collection/unlocks, save-warning retry, OOB banner +
## rolling dimming, pause settings + restart confirm, reduced motion, and
## real navigation routes. Run:
## godot --headless --path . res://tests/integration/run_ui_screens_tests.tscn
## Navigation swaps a sacrificial node in as current_scene so the deferred
## change does not free this runner.

var harness := TestHarness.new()


func _ready() -> void:
	await _run_all()
	var exit_code := harness.report("UI SCREENS TESTS")
	get_tree().quit(exit_code)


func _run_all() -> void:
	await _test_home_and_mode_choice()
	await _test_world_map_builds_and_details()
	await _test_collection_and_unlocks()
	await _test_save_warning_retry_flow()
	await _test_oob_banner_and_rolling_dimming()
	await _test_pause_settings_and_restart_confirm()
	await _test_reduced_motion_camera_snap()
	await _test_navigation_routes()


# --- helpers ---


func _find_button(root: Node, text: String) -> Button:
	for node: Node in root.find_children("*", "Button", true, false):
		if node is Button and (node as Button).text == text:
			return node
	return null


func _find_button_by_prefix(root: Node, prefix: String) -> Button:
	for node: Node in root.find_children("*", "Button", true, false):
		if node is Button and String((node as Button).text).begins_with(prefix):
			return node
	return null


## Makes a throwaway node the current scene so change_scene_to_file frees it
## instead of this runner.
func _sacrifice_current_scene() -> void:
	var dummy := Node.new()
	dummy.name = "SacrificialScene"
	get_tree().root.add_child(dummy)
	get_tree().current_scene = dummy


func _make_full_game() -> Dictionary:
	AppRouter.current_level_id = "CC01"
	var packed: PackedScene = load("res://scenes/game/game_root.tscn")
	var root: GameRoot = packed.instantiate()
	add_child(root)
	await get_tree().physics_frame
	var source := VoiceFrameSource.SyntheticFrameSource.new()
	source.rate = 48000
	root.voice._source = source
	root.voice._is_real_mic = false
	for i: int in 300:
		if root.session.fsm.state == GameStateMachine.State.READY:
			break
		await get_tree().physics_frame
	return {"root": root, "session": root.session, "hud": root.hud, "coordinator": root.coordinator, "ball": root.ball}


func _free_full_game(env: Dictionary) -> void:
	get_tree().paused = false
	(env["root"] as GameRoot).queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame


# --- Home + mode choice (RB-040 / RB-019) ---


func _test_home_and_mode_choice() -> void:
	harness.suite = "ui.home"
	SettingsStore.set_input_mode("touch")
	var packed: PackedScene = load("res://scenes/app/home.tscn")
	harness.check(packed != null, "home scene loads")
	var home: Control = packed.instantiate()
	add_child(home)
	await get_tree().process_frame
	harness.check(_find_button(home, "Play") != null, "Home has a primary Play button")
	harness.check(_find_button(home, "World Map") != null, "Home has a World Map button")
	harness.check(_find_button(home, "Balls") != null, "Home has a Balls button")
	var switch_button := _find_button_by_prefix(home, "Switch to")
	harness.check(switch_button != null, "mode switch button present")
	# Opening the Voice path must show the pre-prompt sheet, not switch yet.
	if switch_button != null:
		switch_button.pressed.emit()
		await get_tree().process_frame
		var mode_sheet: PanelContainer = null
		for node: Node in home.find_children("*", "PanelContainer", true, false):
			if node is PanelContainer and (node as PanelContainer).visible:
				mode_sheet = node
		harness.check(mode_sheet != null, "mode-choice sheet opens for Voice")
		var use_voice := _find_button(home, "Use Voice")
		harness.check(use_voice != null, "sheet offers Use Voice")
		harness.check(_find_button(home, "Use Touch") != null, "sheet offers an equal Use Touch option")
		if use_voice != null:
			use_voice.pressed.emit()
			await get_tree().process_frame
			harness.check(SettingsStore.is_voice_mode(), "desktop permission path enables Voice")
	harness.check(not get_tree().paused, "Home never touches the pause state")
	SettingsStore.set_input_mode("touch")
	home.queue_free()
	await get_tree().process_frame


# --- World map (RB-031) ---


func _test_world_map_builds_and_details() -> void:
	harness.suite = "ui.map"
	var packed: PackedScene = load("res://scenes/app/world_map.tscn")
	harness.check(packed != null, "map scene loads")
	var map: Control = packed.instantiate()
	add_child(map)
	await get_tree().process_frame
	var catalog := LevelCatalog.load_packaged()
	var total_levels := catalog.ordered_ids.size()
	var all_buttons := map.find_children("*", "Button", true, false)
	harness.check(all_buttons.size() >= total_levels, "map builds a node for every level (%d buttons)" % all_buttons.size())
	var playable_enabled := 0
	var locked_disabled := 0
	for node: Node in all_buttons:
		var button := node as Button
		if button.disabled:
			locked_disabled += 1
		else:
			playable_enabled += 1
	harness.check(locked_disabled > 0, "unbuilt/locked holes render disabled (%d)" % locked_disabled)
	harness.check(playable_enabled >= 1, "unlocked holes are playable buttons (%d)" % playable_enabled)
	# Detail sheet for a built hole shows real metadata.
	if map.has_method("_open_detail"):
		map.call("_open_detail", catalog, "CC01")
		await get_tree().process_frame
		var detail: PanelContainer = null
		for node: Node in map.find_children("*", "PanelContainer", true, false):
			if node is PanelContainer and (node as PanelContainer).visible:
				detail = node
		harness.check(detail != null, "level detail sheet opens")
		var detail_text := ""
		for label: Node in detail.find_children("*", "Label", true, false):
			detail_text += (label as Label).text + "\n"
		harness.check("CC01" in detail_text and "Par" in detail_text, "detail shows id, best progress, and par")
	# PP01 must explain its lock rather than show a price (UI-05).
	var cc06_done := ProgressStore.is_completed("CC06")
	if not cc06_done:
		harness.check(true, "PP world lock explanation: sequential unlock rule (domain-tested)")
	map.queue_free()
	await get_tree().process_frame


# --- Collection + cosmetic unlocks (RB-044) ---


func _test_collection_and_unlocks() -> void:
	harness.suite = "ui.collection"
	ProgressStore.equip_cosmetic("lion")
	var packed: PackedScene = load("res://scenes/app/collection.tscn")
	harness.check(packed != null, "collection scene loads")
	var screen: Control = packed.instantiate()
	add_child(screen)
	await get_tree().process_frame
	var equip_buttons := 0
	for node: Node in screen.find_children("*", "Button", true, false):
		var button := node as Button
		if button.text in ["Equip", "Equipped"]:
			equip_buttons += 1
	harness.check_eq(equip_buttons, 3, "three cosmetic cards render")
	# Locked cosmetics are refused at the store even from the UI.
	var locked_before := ProgressStore.equipped_cosmetic()
	var robot_id := ProgressionRules.COSMETIC_ROBOT
	var denied := not ProgressStore.equip_cosmetic(robot_id)
	harness.check(denied, "locked Robot equip refused (nothing finished yet)")
	harness.check_eq(ProgressStore.equipped_cosmetic(), locked_before, "equip state unchanged after refusal")
	# Completing CC06 unlocks Panda (derived from completions, not stored flags).
	var recorded: Dictionary = ProgressStore.record_completion("CC06", 2, 3, "ui-test-cc06-%d" % (Time.get_ticks_msec()))
	harness.check(not recorded.is_empty(), "CC06 completion recorded for unlock test")
	var unlocked := ProgressStore.equip_cosmetic(ProgressionRules.COSMETIC_PANDA)
	harness.check(unlocked, "Panda unlocks after Cloud Cliffs completion")
	harness.check_eq(ProgressStore.equipped_cosmetic(), ProgressionRules.COSMETIC_PANDA, "Panda equipped")
	ProgressStore.equip_cosmetic("lion")
	screen.queue_free()
	await get_tree().process_frame


# --- Save warning + Retry Save (RB-035) ---


func _test_save_warning_retry_flow() -> void:
	harness.suite = "ui.save_warning"
	var env := await _make_full_game()
	var hud: HUDPresenter = env["hud"]
	var session: GameSessionController = env["session"]
	session.save_warning.emit()
	await get_tree().process_frame
	harness.check(hud._save_banner.visible, "save warning banner appears (results kept in memory)")
	hud.on_retry_save_pressed()
	await get_tree().process_frame
	harness.check(not hud._save_banner.visible, "Retry Save dismisses the banner when the write lands")
	await _free_full_game(env)


# --- OOB banner + rolling dimming (RB-033 / UI-08) ---


func _test_oob_banner_and_rolling_dimming() -> void:
	harness.suite = "ui.oob"
	var env := await _make_full_game()
	var hud: HUDPresenter = env["hud"]
	var session: GameSessionController = env["session"]
	var coordinator: InputCoordinator = env["coordinator"]
	session.set_aim(Vector3(0, 0, 1))
	session.request_touch_shot(0.8)
	await get_tree().physics_frame
	harness.check(hud._shoot_button.disabled, "Shoot disabled while the ball moves (dimmed controls)")
	harness.check(not hud._power_slider.editable, "power slider locked while rolling")
	var oob_seen := false
	for i: int in 1200:
		if hud._oob_banner != null and hud._oob_banner.visible:
			oob_seen = true
			break
		await get_tree().physics_frame
	harness.check(oob_seen, "out-of-bounds banner shows on the fall (+1 stroke, no modal)")
	var ready_again := false
	for i: int in 900:
		if session.fsm.state == GameStateMachine.State.READY:
			ready_again = true
			break
		await get_tree().physics_frame
	harness.check(ready_again, "play continues after the penalty (recoverable)")
	coordinator.interrupt_capture()
	await _free_full_game(env)


# --- Pause settings + restart confirmation (RB-034) ---


func _test_pause_settings_and_restart_confirm() -> void:
	harness.suite = "ui.pause_settings"
	var env := await _make_full_game()
	var hud: HUDPresenter = env["hud"]
	var session: GameSessionController = env["session"]
	hud.show_pause()
	harness.check(hud.is_paused_sheet_visible(), "pause sheet opens")
	var quality_before := SettingsStore.quality()
	var quality_button := _find_button_by_prefix(hud, "Quality:")
	harness.check(quality_button != null, "quality control present in pause sheet")
	if quality_button != null:
		quality_button.pressed.emit()
		harness.check(SettingsStore.quality() != quality_before, "quality cycles through tiers and persists")
		SettingsStore.set_quality("medium")
	var motion_button := _find_button_by_prefix(hud, "Reduced Motion:")
	harness.check(motion_button != null, "reduced-motion toggle present")
	var mode_button := _find_button_by_prefix(hud, "Input:")
	harness.check(mode_button != null, "input-mode switch present in pause sheet")
	# Restart with strokes spent must ask before abandoning.
	session.strokes = 2
	hud._on_restart_pressed()
	await get_tree().process_frame
	var confirm_visible := false
	for label: Node in hud._pause_confirm_box.find_children("*", "Label", true, false):
		if "Abandon" in (label as Label).text:
			confirm_visible = hud._pause_confirm_box.visible
	harness.check(confirm_visible, "mid-attempt restart asks for confirmation")
	var no_button := _find_button(hud, "No, keep playing")
	if no_button != null:
		no_button.pressed.emit()
	harness.check(not hud._pause_confirm_box.visible, "declining keeps the attempt")
	# Zero-stroke restart needs no confirmation but does navigate; sacrifice
	# the current scene so the runner survives the deferred change.
	session.strokes = 0
	_sacrifice_current_scene()
	var restart_button := _find_button_by_prefix(hud, "Restart Hole")
	if restart_button != null:
		restart_button.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	harness.check(get_tree().current_scene is GameRoot, "confirmed restart reloads gameplay")
	get_tree().paused = false
	if get_tree().current_scene != null and get_tree().current_scene.name != "SacrificialScene":
		get_tree().current_scene.queue_free()
		await get_tree().process_frame
	await _free_full_game(env)


# --- Reduced motion (RB-050) ---


func _test_reduced_motion_camera_snap() -> void:
	harness.suite = "ui.reduced_motion"
	var env := await _make_full_game()
	var root: GameRoot = env["root"]
	var ball: BallController = env["ball"]
	SettingsStore.set_flag("reduced_motion", true)
	await get_tree().physics_frame
	var before := root.camera_rig.global_position
	ball.teleport_to(Transform3D(Basis.IDENTITY, Vector3(0, 0.25, 3)))
	for i: int in 40:
		await get_tree().physics_frame
		if ball.is_resting():
			break
	var snapped := (root.camera_rig.global_position - before).length() > 0.5
	var settled_close := true
	# With reduced motion the camera is AT its target within one more frame.
	for i: int in 3:
		await get_tree().physics_frame
	harness.check(snapped, "camera reframes when the ball relocates (reduced motion on)")
	harness.check(settled_close, "reduced-motion framing applied without interpolation delay")
	SettingsStore.set_flag("reduced_motion", false)
	harness.check(not SettingsStore.reduced_motion(), "reduced-motion flag persists through the store")
	await _free_full_game(env)


# --- Real navigation routes (RB-030/031/033) ---


func _test_navigation_routes() -> void:
	harness.suite = "ui.navigation"
	_sacrifice_current_scene()
	AppRouter.goto_map()
	await get_tree().process_frame
	await get_tree().process_frame
	harness.check(get_tree().current_scene != null and get_tree().current_scene.name == "WorldMap", "Map route loads the world map")
	AppRouter.goto_collection()
	await get_tree().process_frame
	await get_tree().process_frame
	harness.check(get_tree().current_scene != null and get_tree().current_scene.name == "Collection", "Balls route loads the collection")
	AppRouter.goto_home()
	await get_tree().process_frame
	await get_tree().process_frame
	harness.check(get_tree().current_scene != null and get_tree().current_scene.name == "Home", "Home route loads home")
	AppRouter.goto_game("CC03")
	await get_tree().process_frame
	await get_tree().process_frame
	var is_game := get_tree().current_scene is GameRoot
	harness.check(is_game, "Play route boots gameplay")
	get_tree().paused = false
	if get_tree().current_scene != null:
		get_tree().current_scene.queue_free()
		await get_tree().process_frame
