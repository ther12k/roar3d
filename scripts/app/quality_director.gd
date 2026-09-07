extends Node
## QualityDirector autoload (RB-029): applies the saved quality tier to
## renderer state at boot and whenever settings change. The low tier trims
## resolution scale, MSAA, and shadow resolution/filtering; gameplay-critical
## readability (cup, rails, ball) never depends on the tier. Uses the 4.7.2
## RenderingServer surface (soft-shadow filter quality + shadow atlas sizes —
## there is no shadow_quality_set in this engine version). Device performance
## measurement itself is tracked separately (RB-052 / RB-003).

const TIERS := ["low", "medium", "high"]


func _ready() -> void:
	apply(SettingsStore.quality())
	SettingsStore.settings_changed.connect(func(_s: Dictionary) -> void: apply(SettingsStore.quality()))


func apply(quality: String) -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	match quality:
		"low":
			RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_HARD)
			RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_HARD)
			RenderingServer.directional_shadow_atlas_set_size(2048, true)
			RenderingServer.viewport_set_positional_shadow_atlas_size(viewport.get_viewport_rid(), 2048)
			viewport.scaling_3d_scale = 0.7
			viewport.msaa_3d = Viewport.MSAA_DISABLED
			viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		"high":
			RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH)
			RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH)
			RenderingServer.directional_shadow_atlas_set_size(8192, true)
			RenderingServer.viewport_set_positional_shadow_atlas_size(viewport.get_viewport_rid(), 4096)
			viewport.scaling_3d_scale = 1.0
			viewport.msaa_3d = Viewport.MSAA_2X
			viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		_:
			# medium (default): full resolution, no MSAA, soft shadows.
			RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH)
			RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH)
			RenderingServer.directional_shadow_atlas_set_size(4096, true)
			RenderingServer.viewport_set_positional_shadow_atlas_size(viewport.get_viewport_rid(), 4096)
			viewport.scaling_3d_scale = 1.0
			viewport.msaa_3d = Viewport.MSAA_DISABLED
			viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
