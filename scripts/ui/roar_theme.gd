class_name RoarTheme
extends RefCounted
## Shared UI theme from the design tokens (docs/06_UI_UX_SPEC.md §3). Built in
## code so the theme stays reviewable and no font files are bundled.
## Replicates the vibrant, rounded, mobile-game style of the reference art:
## rich dark-navy panels, glowing cyan voice accents, lush green action buttons,
## warm gold highlights, and circular mic controls.

const NAVY := Color("0D1D27")
const NAVY_PANEL := Color("132B3A")
const NAVY_CARD := Color("1A384C")
const NAVY_BORDER := Color("244B66")
const TEXT_LIGHT := Color("F5F9FC")
const TEXT_SECONDARY := Color("9BB7C7")
const VOICE_CYAN := Color("2DCEFF")
const VOICE_CYAN_GLOW := Color("168DB5")
const PRIMARY_GREEN := Color("48D860")
const PRIMARY_GREEN_PRESSED := Color("38B24C")
const WARM_ACCENT := Color("FFBE42")
const DANGER := Color("EF6A6A")

# Gradient bar colors (Whisper -> Speak -> Roar)
const METER_WHISPER := Color("48D860")
const METER_SPEAK := Color("FFD036")
const METER_ROAR := Color("FF5A36")

const PANEL_RADIUS := 20
const BUTTON_RADIUS := 16
const PILL_RADIUS := 24


static func build() -> Theme:
	var theme := Theme.new()
	theme.set_color("font_color", "Label", TEXT_LIGHT)
	theme.set_color("font_color", "Button", TEXT_LIGHT)
	theme.set_color("font_disabled_color", "Button", TEXT_SECONDARY)
	theme.set_color("font_pressed_color", "Button", TEXT_LIGHT)

	var panel := StyleBoxFlat.new()
	panel.bg_color = NAVY_PANEL
	panel.set_corner_radius_all(PANEL_RADIUS)
	panel.border_color = NAVY_BORDER
	panel.set_border_width_all(2)
	panel.content_margin_left = 16
	panel.content_margin_right = 16
	panel.content_margin_top = 12
	panel.content_margin_bottom = 12
	theme.set_stylebox("panel", "PanelContainer", panel)
	theme.set_stylebox("panel", "Panel", panel)

	var button := StyleBoxFlat.new()
	button.bg_color = PRIMARY_GREEN
	button.set_corner_radius_all(BUTTON_RADIUS)
	button.content_margin_left = 20
	button.content_margin_right = 20
	button.content_margin_top = 12
	button.content_margin_bottom = 12
	var button_pressed: StyleBoxFlat = button.duplicate()
	button_pressed.bg_color = PRIMARY_GREEN_PRESSED
	var button_disabled: StyleBoxFlat = button.duplicate()
	button_disabled.bg_color = NAVY_CARD
	var button_focus: StyleBoxFlat = button.duplicate()
	button_focus.border_color = VOICE_CYAN
	button_focus.set_border_width_all(2)
	theme.set_stylebox("normal", "Button", button)
	theme.set_stylebox("hover", "Button", button)
	theme.set_stylebox("pressed", "Button", button_pressed)
	theme.set_stylebox("disabled", "Button", button_disabled)
	theme.set_stylebox("focus", "Button", button_focus)
	theme.set_color("font_color", "Button", NAVY)
	theme.set_color("font_pressed_color", "Button", NAVY)
	theme.set_color("font_hover_color", "Button", NAVY)

	var grabber := StyleBoxFlat.new()
	grabber.bg_color = VOICE_CYAN
	grabber.set_corner_radius_all(10)
	theme.set_stylebox("grabber_area", "HSlider", grabber)
	var slider_bg := StyleBoxFlat.new()
	slider_bg.bg_color = NAVY_CARD
	slider_bg.set_corner_radius_all(6)
	slider_bg.content_margin_top = 8
	slider_bg.content_margin_bottom = 8
	theme.set_stylebox("slider", "HSlider", slider_bg)
	return theme


static func make_flat_button(text: String, secondary := false) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 52)
	button.focus_mode = Control.FOCUS_NONE
	if secondary:
		var normal: StyleBoxFlat = _secondary_box()
		var pressed: StyleBoxFlat = _secondary_box()
		pressed.bg_color = NAVY_CARD.lightened(0.08)
		var disabled: StyleBoxFlat = _disabled_box()
		button.add_theme_stylebox_override("normal", normal)
		button.add_theme_stylebox_override("hover", normal)
		button.add_theme_stylebox_override("pressed", pressed)
		button.add_theme_stylebox_override("disabled", disabled)
		button.add_theme_color_override("font_color", TEXT_LIGHT)
	else:
		var normal: StyleBoxFlat = _primary_box()
		var pressed: StyleBoxFlat = normal.duplicate()
		pressed.bg_color = PRIMARY_GREEN_PRESSED
		button.add_theme_stylebox_override("normal", normal)
		button.add_theme_stylebox_override("hover", normal)
		button.add_theme_stylebox_override("pressed", pressed)
		button.add_theme_color_override("font_color", NAVY)
		button.add_theme_color_override("font_pressed_color", NAVY)
	return button


## Large glossy hero PLAY button (matching 02_home.png)
static func make_hero_play_button(text := "▶  PLAY") -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 68)
	button.focus_mode = Control.FOCUS_NONE
	var normal := StyleBoxFlat.new()
	normal.bg_color = PRIMARY_GREEN
	normal.set_corner_radius_all(34)
	normal.border_color = Color("8EF8A0")
	normal.set_border_width_all(3)
	normal.content_margin_top = 16
	normal.content_margin_bottom = 16
	var pressed: StyleBoxFlat = normal.duplicate()
	pressed.bg_color = PRIMARY_GREEN_PRESSED
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", normal)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_color_override("font_color", NAVY)
	button.add_theme_color_override("font_pressed_color", NAVY)
	button.add_theme_font_size_override("font_size", 22)
	return button


## Gold "ROAR!" mic pill button matching the asset-pack UI panel
static func make_circular_mic_button(diameter := 84) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(diameter + 40, diameter - 20)
	button.focus_mode = Control.FOCUS_NONE
	button.text = "🎙 ROAR!"
	var normal := StyleBoxFlat.new()
	normal.bg_color = WARM_ACCENT
	normal.set_corner_radius_all((diameter - 20) / 2)
	normal.border_color = Color("FFE090")
	normal.set_border_width_all(3)
	normal.shadow_color = Color(WARM_ACCENT.r, WARM_ACCENT.g, WARM_ACCENT.b, 0.4)
	normal.shadow_size = 8
	var pressed: StyleBoxFlat = normal.duplicate()
	pressed.bg_color = Color("FFD036")
	pressed.border_color = Color.WHITE
	pressed.shadow_size = 14
	var disabled: StyleBoxFlat = normal.duplicate()
	disabled.bg_color = NAVY_CARD
	disabled.border_color = NAVY_BORDER
	disabled.shadow_size = 0
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", normal)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_color", NAVY)
	button.add_theme_color_override("font_pressed_color", NAVY)
	button.add_theme_font_size_override("font_size", 16)
	return button


## Legacy circular style kept for reference
static func make_circular_mic_button_cyan(diameter := 84) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(diameter, diameter)
	button.focus_mode = Control.FOCUS_NONE
	button.text = "🎙\nHOLD"
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("1A4D6B")
	normal.set_corner_radius_all(diameter / 2)
	normal.border_color = VOICE_CYAN
	normal.set_border_width_all(4)
	normal.shadow_color = Color(VOICE_CYAN.r, VOICE_CYAN.g, VOICE_CYAN.b, 0.45)
	normal.shadow_size = 8
	var pressed: StyleBoxFlat = normal.duplicate()
	pressed.bg_color = VOICE_CYAN
	pressed.border_color = Color.WHITE
	pressed.shadow_color = Color(VOICE_CYAN.r, VOICE_CYAN.g, VOICE_CYAN.b, 0.8)
	pressed.shadow_size = 14
	var disabled: StyleBoxFlat = normal.duplicate()
	disabled.bg_color = NAVY_CARD
	disabled.border_color = NAVY_BORDER
	disabled.shadow_size = 0
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", normal)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_color", TEXT_LIGHT)
	button.add_theme_color_override("font_pressed_color", NAVY)
	button.add_theme_font_size_override("font_size", 14)
	return button


## Pill box container (for Strokes counter, status chips, badges)
static func make_pill_panel(bg_color := NAVY_CARD, border_color := NAVY_BORDER) -> PanelContainer:
	var panel := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = bg_color
	box.set_corner_radius_all(18)
	box.border_color = border_color
	box.set_border_width_all(2)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", box)
	return panel


static func _primary_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = PRIMARY_GREEN
	box.set_corner_radius_all(BUTTON_RADIUS)
	box.border_color = Color("8EF8A0")
	box.set_border_width_all(2)
	box.content_margin_left = 20
	box.content_margin_right = 20
	box.content_margin_top = 12
	box.content_margin_bottom = 12
	return box


static func _secondary_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = NAVY_CARD
	box.set_corner_radius_all(BUTTON_RADIUS)
	box.border_color = NAVY_BORDER
	box.set_border_width_all(2)
	box.content_margin_left = 16
	box.content_margin_right = 16
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	return box


static func _disabled_box() -> StyleBoxFlat:
	var box := _secondary_box()
	box.bg_color = box.bg_color.darkened(0.3)
	box.border_color = NAVY
	return box
