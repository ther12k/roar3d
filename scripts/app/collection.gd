extends Control
## Collection (UI-11, RB-044): cosmetic cards with a colored ball preview,
## unlock criteria, and an Equip action. Locked cards inform instead of
## selling; previewing a locked ball never equips it. Equip changes visuals
## only. Grid layout fits 390x844 without horizontal overflow.

const CARDS := [
	{"id": "lion", "title": "Lion", "color": Color("f2b547"), "how": "Always yours."},
	{"id": "classic", "title": "Classic", "color": Color("f5f5f0"), "how": "Always yours."},
	{"id": "gold", "title": "Gold", "color": Color("f2c250"), "how": "Clear Cloud Cliffs hole 3."},
	{"id": "tiger", "title": "Tiger", "color": Color("e8823d"), "how": "Clear Portal Peaks hole 3."},
	{"id": "leaf", "title": "Leaf", "color": Color("59b34a"), "how": "Clear all 12 holes."},
	{"id": "panda", "title": "Panda", "color": Color("ebeff5"), "how": "Clear Cloud Cliffs hole 6."},
	{"id": "robot", "title": "Robot", "color": Color("9eacb9"), "how": "Clear Portal Peaks hole 6."},
]

var _equip_buttons: Dictionary = {}
var _status_label: Label


func _ready() -> void:
	theme = RoarTheme.build()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 14
	box.offset_right = -14
	box.offset_top = 14
	box.offset_bottom = -14
	box.add_theme_constant_override("separation", 10)
	add_child(box)

	var title := Label.new()
	title.text = tr("BALLS")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", RoarTheme.WARM_ACCENT)
	box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = tr("BALLS_SUB")
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", RoarTheme.TEXT_SECONDARY)
	subtitle.add_theme_font_size_override("font_size", 12)
	box.add_child(subtitle)

	# 3 columns x 3 rows: every card keeps a fixed width budget inside 362 px.
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(grid)

	var completed := ProgressStore.completed_set()
	var equipped := ProgressStore.equipped_cosmetic()
	for card: Dictionary in CARDS:
		grid.add_child(_make_card(card, completed, equipped))

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_color_override("font_color", RoarTheme.WARM_ACCENT)
	_status_label.add_theme_font_size_override("font_size", 12)
	box.add_child(_status_label)

	var back := RoarTheme.make_flat_button(tr("BACK"))
	back.pressed.connect(func() -> void: AppRouter.goto_home())
	box.add_child(back)


## One card: round ball preview swatch, name, unlock hint, equip button.
func _make_card(card: Dictionary, completed: Dictionary, equipped: String) -> PanelContainer:
	var cosmetic_id := String(card["id"])
	var unlocked: bool = ProgressionRules.is_cosmetic_unlocked(cosmetic_id, completed)

	var panel := RoarTheme.make_pill_panel(RoarTheme.NAVY_PANEL, RoarTheme.NAVY_BORDER)
	var inner := VBoxContainer.new()
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	inner.add_theme_constant_override("separation", 4)
	panel.add_child(inner)

	var swatch_color: Color = card["color"]
	if not unlocked:
		swatch_color = swatch_color.darkened(0.55)
	var swatch := PanelContainer.new()
	swatch.custom_minimum_size = Vector2(46, 46)
	swatch.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var swatch_style := StyleBoxFlat.new()
	swatch_style.bg_color = swatch_color
	swatch_style.set_corner_radius_all(23)
	swatch_style.border_color = Color("ffffff").darkened(0.0 if unlocked else 0.6)
	swatch_style.set_border_width_all(2)
	swatch.add_theme_stylebox_override("panel", swatch_style)
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(swatch)

	var name_label := Label.new()
	name_label.text = ("🔒 " if not unlocked else "") + String(card["title"])
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 13)
	inner.add_child(name_label)

	var how := Label.new()
	how.text = String(card["how"])
	how.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	how.add_theme_color_override("font_color", RoarTheme.TEXT_SECONDARY)
	how.add_theme_font_size_override("font_size", 10)
	how.custom_minimum_size = Vector2(104, 0)
	inner.add_child(how)

	var equip := RoarTheme.make_flat_button(tr("EQUIP"), unlocked)
	equip.add_theme_font_size_override("font_size", 12)
	equip.disabled = not unlocked
	if equipped == cosmetic_id and unlocked:
		equip.text = tr("EQUIPPED")
		equip.disabled = true
	equip.pressed.connect(func() -> void: _on_equip(cosmetic_id))
	inner.add_child(equip)
	_equip_buttons[cosmetic_id] = equip
	return panel


func _on_equip(cosmetic_id: String) -> void:
	# The store enforces the unlock rule; a locked equip is refused outright.
	if not ProgressStore.equip_cosmetic(cosmetic_id):
		_status_label.text = "That ball is still locked."
		return
	_status_label.text = "Equipped."
	for id: String in _equip_buttons:
		var button: Button = _equip_buttons[id]
		button.text = tr("EQUIPPED") if id == cosmetic_id else tr("EQUIP")
		button.disabled = id == cosmetic_id
