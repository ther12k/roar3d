extends Control
## World Map (UI-05, RB-031): two chapter cards with six numbered nodes each,
## earned stars, and lock explanations. Real Controls only — the layout is
## plain, never a 3D scene per node. Navigation: Home / Collection.

var _detail_panel: PanelContainer
var _detail_title: Label
var _detail_info: Label
var _detail_play: Button
var _detail_level_id := ""


func _ready() -> void:
	theme = RoarTheme.build()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var catalog := LevelCatalog.load_packaged()
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 16
	box.offset_right = -16
	box.offset_top = 16
	box.offset_bottom = -16
	box.add_theme_constant_override("separation", 10)
	add_child(box)

	var title := Label.new()
	title.text = tr("WORLD_MAP")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	for world: Dictionary in catalog.worlds:
		var world_label := Label.new()
		world_label.text = String(world["name"])
		world_label.add_theme_color_override("font_color", RoarTheme.TEXT_SECONDARY)
		box.add_child(world_label)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		box.add_child(row)
		for level_id: String in catalog.world_level_ids(String(world["id"])):
			row.add_child(_make_node(catalog, level_id))

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	box.add_child(buttons)
	var home := RoarTheme.make_flat_button(tr("HOME"))
	home.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	home.pressed.connect(func() -> void: AppRouter.goto_home())
	buttons.add_child(home)
	var balls := RoarTheme.make_flat_button(tr("BALLS"), true)
	balls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	balls.pressed.connect(func() -> void: AppRouter.goto_collection())
	buttons.add_child(balls)

	_build_detail_panel()


func _make_node(catalog: LevelCatalog.CatalogData, level_id: String) -> Button:
	var meta := catalog.level_by_id(level_id)
	var unlocked := ProgressStore.is_unlocked(level_id)
	var playable := catalog.is_playable(level_id)
	var label := "%d" % int(meta["world_index"])
	if unlocked and playable:
		var best := ProgressStore.best_for(level_id)
		var stars := int(best.get("best_stars", 0))
		label += " " + "*".repeat(stars) if stars > 0 else label
	elif unlocked and not playable:
		label += " ·"
	var node := RoarTheme.make_flat_button(label, true)
	node.disabled = not (unlocked and playable)
	node.custom_minimum_size = Vector2(48, 48)
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if unlocked and playable:
		node.pressed.connect(func() -> void: _open_detail(catalog, level_id))
	elif not unlocked:
		node.tooltip_text = "Finish the previous hole"
	return node


func _open_detail(catalog: LevelCatalog.CatalogData, level_id: String) -> void:
	var meta := catalog.level_by_id(level_id)
	_detail_level_id = level_id
	_detail_title.text = "%s · %s" % [level_id, String(meta["title"])]
	var best := ProgressStore.best_for(level_id)
	var best_text := tr("NOT_PLAYED") if best.is_empty() else tr("BEST") % [
		int(best.get("best_strokes", 0)), "*".repeat(int(best.get("best_stars", 0)))
	]
	_detail_info.text = "%s\nPar %d · %s" % [best_text, int(meta["par"]), String(meta["teaching_goal"])]
	_detail_panel.visible = true


func _build_detail_panel() -> void:
	_detail_panel = PanelContainer.new()
	_detail_panel.set_anchors_preset(Control.PRESET_CENTER)
	_detail_panel.anchor_left = 0.1
	_detail_panel.anchor_right = 0.9
	_detail_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_detail_panel.add_child(box)
	_detail_title = Label.new()
	_detail_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_detail_title)
	_detail_info = Label.new()
	_detail_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_detail_info)
	_detail_play = RoarTheme.make_flat_button(tr("PLAY"))
	_detail_play.pressed.connect(func() -> void:
		if not _detail_level_id.is_empty():
			AppRouter.goto_game(_detail_level_id))
	box.add_child(_detail_play)
	var close := RoarTheme.make_flat_button(tr("BACK"), true)
	close.pressed.connect(func() -> void: _detail_panel.visible = false)
	box.add_child(close)
	_detail_panel.visible = false
	add_child(_detail_panel)
