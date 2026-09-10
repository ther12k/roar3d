extends Control
## Collection (UI-11, RB-044): three cosmetic cards with unlock criteria and
## an Equip action. Locked cards inform instead of selling; previewing a
## locked ball never equips it. Equip changes visuals only.

const CARDS := [
	{"id": "lion", "title": "🦁 Lion", "how": "Always yours."},
	{"id": "classic", "title": "⚪ Classic", "how": "Always yours."},
	{"id": "gold", "title": "🟡 Gold", "how": "Finish Cloud Cliffs hole 3."},
	{"id": "tiger", "title": "🐯 Tiger", "how": "Finish Portal Peaks hole 3."},
	{"id": "leaf", "title": "🍃 Leaf", "how": "Finish all 12 holes."},
	{"id": "panda", "title": "🐼 Panda", "how": "Finish Cloud Cliffs (hole 6)."},
	{"id": "robot", "title": "🤖 Robot", "how": "Finish Portal Peaks (hole 6)."},
]

var _equip_buttons: Dictionary = {}
var _status_label: Label


func _ready() -> void:
	theme = RoarTheme.build()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 16
	box.offset_right = -16
	box.offset_top = 16
	box.offset_bottom = -16
	box.add_theme_constant_override("separation", 10)
	add_child(box)

	var title := Label.new()
	title.text = tr("BALLS")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var completed := ProgressStore.completed_set()
	var equipped := ProgressStore.equipped_cosmetic()
	for card: Dictionary in CARDS:
		var unlocked: bool = ProgressionRules.is_cosmetic_unlocked(String(card["id"]), completed)
		var panel := PanelContainer.new()
		box.add_child(panel)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		panel.add_child(row)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var name_label := Label.new()
		name_label.text = String(card["title"])
		info.add_child(name_label)
		var how := Label.new()
		how.text = String(card["how"]) if unlocked else String(card["how"]) + "  (locked)"
		how.add_theme_color_override("font_color", RoarTheme.TEXT_SECONDARY)
		how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(how)
		var equip := RoarTheme.make_flat_button(tr("EQUIP"))
		equip.custom_minimum_size = Vector2(96, 48)
		equip.disabled = not unlocked
		var cosmetic_id := String(card["id"])
		if equipped == cosmetic_id and unlocked:
			equip.text = tr("EQUIPPED")
			equip.disabled = true
		equip.pressed.connect(func() -> void: _on_equip(cosmetic_id))
		row.add_child(equip)
		_equip_buttons[cosmetic_id] = equip

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_color_override("font_color", RoarTheme.TEXT_SECONDARY)
	box.add_child(_status_label)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	var back := RoarTheme.make_flat_button(tr("BACK"))
	back.pressed.connect(func() -> void: AppRouter.goto_map())
	box.add_child(back)


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
