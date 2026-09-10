extends Control
## World Map (UI-05, RB-031): two world cards with six numbered hole chips
## each, earned stars, and lock explanations. Real Controls only — the layout
## is plain, never a 3D scene per node. Navigation: Home / Collection.

const WORLD_BANNERS := {
	"cloud_cliffs": {"sky": Color("7fc4ee"), "accent": Color("48d860"), "blurb": "Sunny skies over floating grass."},
	"portal_peaks": {"sky": Color("b46ec6"), "accent": Color("ff9a5c"), "blurb": "Portals and sunset plateaus."},
}

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
	box.offset_top = 14
	box.offset_bottom = -14
	box.add_theme_constant_override("separation", 12)
	add_child(box)

	var title := Label.new()
	title.text = tr("WORLD_MAP")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", RoarTheme.WARM_ACCENT)
	box.add_child(title)

	for world: Dictionary in catalog.worlds:
		box.add_child(_make_world_card(catalog, world))

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


## One world = a banner card with a sky strip, progress, and a chip per hole.
func _make_world_card(catalog: LevelCatalog.CatalogData, world: Dictionary) -> PanelContainer:
	var world_id := String(world["id"])
	var level_ids: Array = catalog.world_level_ids(world_id)
	var banner: Dictionary = WORLD_BANNERS.get(world_id, WORLD_BANNERS["cloud_cliffs"])
	var world_unlocked := ProgressStore.is_unlocked(String(level_ids[0]))

	var card := RoarTheme.make_pill_panel(RoarTheme.NAVY_PANEL, RoarTheme.NAVY_BORDER)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 8)
	card.add_child(inner)

	# Sky strip with the world's name — the card's visual identity.
	var strip := PanelContainer.new()
	var strip_style := StyleBoxFlat.new()
	strip_style.bg_color = banner["sky"]
	strip_style.set_corner_radius_all(12)
	strip_style.content_margin_left = 12
	strip_style.content_margin_right = 12
	strip_style.content_margin_top = 6
	strip_style.content_margin_bottom = 6
	strip.add_theme_stylebox_override("panel", strip_style)
	inner.add_child(strip)
	var strip_row := HBoxContainer.new()
	strip.add_child(strip_row)
	var name_label := Label.new()
	name_label.text = String(world["name"])
	name_label.add_theme_font_size_override("font_size", 17)
	name_label.add_theme_color_override("font_color", Color("16324a"))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strip_row.add_child(name_label)
	var stars := 0
	for level_id: String in level_ids:
		stars += int(ProgressStore.best_for(level_id).get("best_stars", 0))
	var stars_label := Label.new()
	stars_label.text = "⭐ %d/18" % stars
	stars_label.add_theme_font_size_override("font_size", 13)
	strip_row.add_child(stars_label)

	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 8)
	chips.alignment = BoxContainer.ALIGNMENT_CENTER
	inner.add_child(chips)
	for level_id: String in level_ids:
		chips.add_child(_make_chip(catalog, level_id, world_unlocked))

	if not world_unlocked:
		var lock_note := Label.new()
		lock_note.text = "🔒 " + tr("WORLD_LOCKED")
		lock_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lock_note.add_theme_color_override("font_color", RoarTheme.TEXT_SECONDARY)
		lock_note.add_theme_font_size_override("font_size", 12)
		inner.add_child(lock_note)
	else:
		var blurb := Label.new()
		blurb.text = String(banner["blurb"])
		blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		blurb.add_theme_color_override("font_color", RoarTheme.TEXT_SECONDARY)
		blurb.add_theme_font_size_override("font_size", 11)
		inner.add_child(blurb)
	return card


## A hole chip: big number, star dots underneath; locked holes dim.
func _make_chip(catalog: LevelCatalog.CatalogData, level_id: String, world_unlocked: bool) -> VBoxContainer:
	var meta := catalog.level_by_id(level_id)
	var unlocked := world_unlocked and ProgressStore.is_unlocked(level_id)
	var playable := catalog.is_playable(level_id)
	var best := ProgressStore.best_for(level_id)
	var stars := int(best.get("best_stars", 0))

	var chip := VBoxContainer.new()
	chip.alignment = BoxContainer.ALIGNMENT_CENTER
	chip.add_theme_constant_override("separation", 2)
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var button := RoarTheme.make_flat_button(str(int(meta["world_index"])), true)
	button.custom_minimum_size = Vector2(44, 44)
	button.add_theme_font_size_override("font_size", 18)
	button.disabled = not (unlocked and playable)
	if unlocked and playable:
		button.pressed.connect(func() -> void: _open_detail(catalog, level_id))
	elif not world_unlocked:
		button.tooltip_text = "Finish the previous world"
	else:
		button.tooltip_text = "Finish the previous hole"
	chip.add_child(button)

	var dots := Label.new()
	dots.text = "★".repeat(stars) if stars > 0 else "·"
	dots.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dots.add_theme_font_size_override("font_size", 10)
	dots.add_theme_color_override("font_color", RoarTheme.WARM_ACCENT if stars > 0 else RoarTheme.TEXT_SECONDARY)
	chip.add_child(dots)
	return chip


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
	_detail_title.add_theme_font_size_override("font_size", 18)
	_detail_title.add_theme_color_override("font_color", RoarTheme.WARM_ACCENT)
	box.add_child(_detail_title)
	_detail_info = Label.new()
	_detail_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_detail_info)
	_detail_play = RoarTheme.make_hero_play_button(tr("PLAY"))
	_detail_play.pressed.connect(func() -> void:
		if not _detail_level_id.is_empty():
			AppRouter.goto_game(_detail_level_id))
	box.add_child(_detail_play)
	var close := RoarTheme.make_flat_button(tr("BACK"), true)
	close.pressed.connect(func() -> void: _detail_panel.visible = false)
	box.add_child(close)
	_detail_panel.visible = false
	add_child(_detail_panel)
