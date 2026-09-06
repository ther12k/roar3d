class_name RoarTheme
extends RefCounted
## Shared UI theme from the design tokens (docs/06_UI_UX_SPEC.md §3). Built in
## code so the theme stays reviewable and no font files are bundled (Godot's
## default font is used during development).

const NAVY := Color("132B3A")
const NAVY_PANEL := Color("1D4258")
const TEXT_LIGHT := Color("F5F9FC")
const TEXT_SECONDARY := Color("B9CDDA")
const VOICE_CYAN := Color("2DCEFF")
const PRIMARY_GREEN := Color("63DC65")
const WARM_ACCENT := Color("FFBE42")
const DANGER := Color("EF6A6A")

const PANEL_RADIUS := 20
const BUTTON_RADIUS := 16


static func build() -> Theme:
	var theme := Theme.new()
	theme.set_color("font_color", "Label", TEXT_LIGHT)
	theme.set_color("font_color", "Button", TEXT_LIGHT)
	theme.set_color("font_disabled_color", "Button", TEXT_SECONDARY)
	theme.set_color("font_pressed_color", "Button", TEXT_LIGHT)

	var panel := StyleBoxFlat.new()
	panel.bg_color = NAVY_PANEL
	panel.set_corner_radius_all(PANEL_RADIUS)
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
	button_pressed.bg_color = button.bg_color.darkened(0.15)
	var button_disabled: StyleBoxFlat = button.duplicate()
	button_disabled.bg_color = NAVY_PANEL
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

	var secondary := button.duplicate()
	secondary.bg_color = NAVY_PANEL
	var secondary_pressed: StyleBoxFlat = secondary.duplicate()
	secondary_pressed.bg_color = secondary.bg_color.lightened(0.08)
	theme.set_stylebox("normal", &"SecondaryButton", secondary)
	theme.set_stylebox("hover", &"SecondaryButton", secondary)
	theme.set_stylebox("pressed", &"SecondaryButton", secondary_pressed)
	theme.set_stylebox("disabled", &"SecondaryButton", button_disabled)
	theme.set_color("font_color", &"SecondaryButton", TEXT_LIGHT)

	var grabber := StyleBoxFlat.new()
	grabber.bg_color = VOICE_CYAN
	grabber.set_corner_radius_all(10)
	theme.set_stylebox("grabber_area", "HSlider", grabber)
	var slider_bg := StyleBoxFlat.new()
	slider_bg.bg_color = NAVY_PANEL
	slider_bg.set_corner_radius_all(4)
	slider_bg.content_margin_top = 8
	slider_bg.content_margin_bottom = 8
	theme.set_stylebox("slider", "HSlider", slider_bg)
	return theme


static func make_flat_button(text: String, secondary := false) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 56)
	button.focus_mode = Control.FOCUS_NONE
	if secondary:
		var normal: StyleBoxFlat = _secondary_box()
		var pressed: StyleBoxFlat = _secondary_box()
		pressed.bg_color = pressed.bg_color.lightened(0.08)
		var disabled: StyleBoxFlat = _disabled_box()
		button.add_theme_stylebox_override("normal", normal)
		button.add_theme_stylebox_override("hover", normal)
		button.add_theme_stylebox_override("pressed", pressed)
		button.add_theme_stylebox_override("disabled", disabled)
	return button


static func _secondary_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = NAVY_PANEL
	box.set_corner_radius_all(BUTTON_RADIUS)
	box.content_margin_left = 20
	box.content_margin_right = 20
	box.content_margin_top = 12
	box.content_margin_bottom = 12
	return box


static func _disabled_box() -> StyleBoxFlat:
	var box := _secondary_box()
	box.bg_color = box.bg_color.darkened(0.3)
	return box
