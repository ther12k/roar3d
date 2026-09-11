class_name GameRoot
extends Node
## Gameplay composition root and the SINGLE pause/overview authority
## (review round 1: pause/overview previously split across HUD, CameraRig and
## the session, which could leave the player stuck or the session paused
## while the world ran). All pause-flavored state changes funnel through
## set_gameplay_paused()/toggle_overview(): cancel capture → update session
## state machine → pause the tree → show/hide overlay, in that order.

const AIM_GUIDE_LENGTH := 2.4
const CAL_STAGE_SECONDS := 1.5
const MASCOT_ASSET := "res://assets/models/lion_ball.glb"  # RB-027 production asset
# Squash & stretch spring (D-021): positive = squashed wide, negative =
# stretched tall. Under-damped on purpose so the ball visibly springs back.
const SQUASH_SPRING_K := 180.0
const SQUASH_SPRING_D := 16.0
const SQUASH_CLAMP := 0.35

@onready var session: GameSessionController = $GameSessionController
@onready var coordinator: InputCoordinator = $InputCoordinator
@onready var level: LevelController = $WorldRoot/LevelController
@onready var ball: BallController = $WorldRoot/Ball
@onready var camera_rig: CameraRig = $WorldRoot/CameraRig
@onready var voice: VoiceInputService = $VoiceInputService
@onready var hud: HUDPresenter = $GameUI/SafeAreaRoot

var _aim_guide: Node3D = null
var _aim_segments: Array[MeshInstance3D] = []
var _aim_arrow: MeshInstance3D = null
var _aim_pulse_time := 0.0
var _roll_particle_timer := 0.0
var _last_sling_band := -1
var _visual_root: Node3D = null
var _face_rig: Node3D = null
var _mouth_smile: MeshInstance3D = null
var _mouth_o: MeshInstance3D = null
var _mouth_smile_base := Vector3.ONE
var _expression_timer: SceneTreeTimer = null
var _sad_active := false
var _mane: Node3D = null
var _mane_base := Vector3.ONE
var _mane_puff := 0.0
var _using_mascot_asset := false  # true when the RB-027 GLB drives the look
var _brows: Array[MeshInstance3D] = []
var _brow_base_pos: Array[Vector3] = []
var _brow_base_rot: Array[Vector3] = []
var _ears: Array[MeshInstance3D] = []
var _mouth_tongue: MeshInstance3D = null
var _blink_meshes: Array[MeshInstance3D] = []
var _blink_base: Array[float] = []
var _blink_timer := 2.0
var _blink_phase := -1.0
var _squash := 0.0
var _squash_vel := 0.0
var _sinking := false
var _hop_tween: Tween = null  # READY-state decorative hop (visual node only)
var _flag_mesh: MeshInstance3D = null
var _cup_twin_material: Material = null  # turf material reused for carved pieces
var _flag_time := 0.0
var _last_bounce_ms := 0
var _perf_label: Label = null
var _perf_accum := 0.0
var _perf_frames := 0
var _cal_stage: String = ""
var _cal_room: Dictionary = {}
var _cal_soft: Dictionary = {}
var _cal_strong: Dictionary = {}


func _ready() -> void:
	var level_id := AppRouter.current_level_id
	if level_id.is_empty():
		AppRouter.goto_home()
		return
	var catalog := LevelCatalog.load_packaged()
	if not catalog.valid or not catalog.ordered_ids.has(level_id):
		push_error("Cannot start unknown level " + level_id)
		AppRouter.goto_home()
		return
	var meta: Dictionary = catalog.level_by_id(level_id)
	if not catalog.is_playable(level_id):
		push_error("Level " + level_id + " is not playable (status/scene).")
		AppRouter.goto_home()
		return

	var errors := level.load_level(meta)
	if not errors.is_empty():
		push_error("Level marker contract failed for " + level_id + ": " + ", ".join(errors))
		AppRouter.goto_home()
		return

	_apply_world_sky(level_id)
	# Portal Peaks gets the sunset track; Cloud Cliffs keeps the sunny loop
	# (same-track requests are no-ops, so menu → CC never restarts the music).
	AudioDirector.play_music("sunset" if level_id.begins_with("PP") else "sunny")
	_maybe_build_perf_overlay()
	_spawn_scenery(level_id)
	_spawn_hole_sign(level_id, int(meta["par"]))
	session.setup(ball, level, level_id, int(meta["par"]), int(meta["max_strokes"]))
	coordinator.session = session
	coordinator.voice = voice
	coordinator.camera_rig = camera_rig
	camera_rig.session = session
	camera_rig.level = level
	# A saved calibration profile is the only way Voice power mapping works;
	# load it before any hold can start (review finding: empty profile).
	if SettingsStore.has_valid_calibration():
		voice.calibration = SettingsStore.calibration()
	hud.gameplay = self
	hud.bind(session, coordinator, voice, camera_rig)
	hud.set_hole_info("%s · %s" % [level_id, String(meta["title"])], int(meta["par"]))
	hud.pause_requested.connect(func() -> void: set_gameplay_paused(true))
	hud.resume_requested.connect(func() -> void: set_gameplay_paused(false))
	hud.overview_toggled.connect(func() -> void: toggle_overview())
	hud.restart_requested.connect(_restart_level)
	hud.map_requested.connect(_to_map)
	hud.next_hole_requested.connect(_next_hole)
	# Nonverbal feedback cues (RB-025): effects bus only, never the mic path.
	session.shot_committed.connect(func(_shot: ShotCommand) -> void:
		AudioDirector.play_effect("putt")
		_spawn_burst(ball.global_position, Color("6fce4e"), 10, 2.0)
		_kick_squash(-5.0)
		_set_expression("surprised")
	)
	session.hole_completed.connect(func(_result: Dictionary) -> void:
		AudioDirector.play_effect("cup")
		# Celebration sting rides just after the drop rattle finishes.
		get_tree().create_timer(0.45).timeout.connect(func() -> void:
			AudioDirector.play_effect("cheer", 0.8))
		_spawn_burst(level.cup_position() + Vector3(0, 0.4, 0), RoarTheme.WARM_ACCENT, 26, 5.0)
		_spawn_burst(level.cup_position() + Vector3(0, 0.5, 0), RoarTheme.VOICE_CYAN, 18, 4.5)
		_spawn_burst(level.cup_position() + Vector3(0, 0.6, 0), RoarTheme.PRIMARY_GREEN, 18, 4.5)
		_kick_squash(4.0)
		_set_expression("happy")
		_play_cup_sink()
	)
	ball.fall_detected.connect(func(_reason: String) -> void: _on_any_fall())
	level.kill_zone_entered.connect(func() -> void: _on_any_fall())
	ball.settled.connect(func(_t: Transform3D, _ok: bool) -> void:
		_spawn_burst(ball.global_position, Color(0.75, 0.72, 0.66), 8, 1.2)  # landing dust
		_kick_squash(3.5))
	ball.bounced.connect(_on_ball_bounced)
	ball.jumped.connect(_on_ball_jumped)
	# READY-state hop is presentation-only: the mascot bounces on its visual
	# node, the RigidBody never moves (D-026 — no ball movement without stroke).
	session.decorative_hop_requested.connect(_play_decorative_hop)

	_apply_equipped_cosmetic()
	_build_visual_root()
	_build_face_rig()
	# Re-apply after the mascot asset loads: the equipped tint must land on
	# the GLB body (BallBody) when it is the visible mesh.
	_apply_equipped_cosmetic()
	_build_real_cup()
	# The authored cup flag exists in every level scene; only its flutter is
	# driven here (presentation-only, no collider involved).
	_flag_mesh = level.find_child("FlagMesh", true, false) as MeshInstance3D
	_build_aim_guide()
	ball.freeze = true
	session.start_level()
	ball.freeze = false
	_maybe_capture_evidence_screenshot()


## Cosmetics are visual-only (docs/07 §5): collider, mass, and physics stay
## identical; the equipped ball just re-tints the body mesh.
func _apply_equipped_cosmetic() -> void:
	var equipped := ProgressStore.equipped_cosmetic()
	# Prefer the RB-027 asset body; fall back to the legacy scene primitive.
	var mesh := ball.find_child("BallBody", true, false) as MeshInstance3D
	if mesh == null:
		mesh = ball.find_child("BallMesh", true, false) as MeshInstance3D
	var mane := ball.find_child("Mane", true, false) as MeshInstance3D
	if mane == null:
		mane = ball.find_child("ManeMesh", true, false) as MeshInstance3D
	var is_mascot := equipped in [
		ProgressionRules.COSMETIC_LION, ProgressionRules.COSMETIC_PANDA, ProgressionRules.COSMETIC_ROBOT,
	]
	# Faceless golf-ball skins hide the mane and the billboard face rig.
	if mane != null:
		mane.visible = is_mascot
	if _face_rig != null:
		_face_rig.visible = is_mascot
	if mesh == null:
		return
	var material := StandardMaterial3D.new()
	match equipped:
		ProgressionRules.COSMETIC_LION:
			return  # authored lion materials stay
		ProgressionRules.COSMETIC_PANDA:
			material.albedo_color = Color(0.92, 0.93, 0.95)
		ProgressionRules.COSMETIC_ROBOT:
			material.albedo_color = Color(0.62, 0.68, 0.75)
		ProgressionRules.SKIN_CLASSIC:
			material.albedo_color = Color(0.96, 0.96, 0.94)
			material.roughness = 0.35
		ProgressionRules.SKIN_GOLD:
			material.albedo_color = Color(0.95, 0.76, 0.31)
			material.metallic = 0.6
			material.roughness = 0.25
		ProgressionRules.SKIN_TIGER:
			material.albedo_color = Color(0.91, 0.51, 0.24)
			material.roughness = 0.45
		ProgressionRules.SKIN_LEAF:
			material.albedo_color = Color(0.35, 0.70, 0.29)
			material.roughness = 0.4
		_:
			return
	mesh.material_override = material
	# Tiger stripes: two dark rings hugging the sphere.
	if equipped == ProgressionRules.SKIN_TIGER:
		for offset in [0.09, -0.09]:
			var stripe := MeshInstance3D.new()
			stripe.name = "TigerStripe"
			var ring := TorusMesh.new()
			ring.inner_radius = 0.225
			ring.outer_radius = 0.255
			stripe.mesh = ring
			var dark := StandardMaterial3D.new()
			dark.albedo_color = Color(0.16, 0.12, 0.1)
			stripe.material_override = dark
			stripe.position = Vector3(0, offset, 0)
			ball.add_child(stripe)


## Fall coalescing for presentation only: either the kill plane or the kill
## volume may fire; penalties remain the session's once-only decision.
func _on_any_fall() -> void:
	AudioDirector.play_effect("fall")
	_set_expression("sad")
	hud.show_out_of_bounds()


## Impact-strength bounce cue with a 140 ms throttle (rail rattles fire one
## contact event per frame otherwise) and a small squash nudge on hard hits.
func _on_ball_bounced(strength: float) -> void:
	if strength < 1.2:
		return
	var now := Time.get_ticks_msec()
	if now - _last_bounce_ms < 140:
		return
	_last_bounce_ms = now
	AudioDirector.play_effect("bounce", clampf(strength / 10.0, 0.3, 1.0))
	_kick_squash(clampf(strength * 0.06, 0.0, 0.6))
	camera_rig.add_trauma(clampf(strength * 0.025, 0.05, 0.3))


## Jump anticipation (M5 feel pass): a beat of stretch + dust at takeoff, and
## the follow-through lands via the existing settle dust.
func _on_ball_jumped(strength: float) -> void:
	_kick_squash(-clampf(strength * 1.2, 3.0, 6.0))
	camera_rig.add_trauma(0.12)
	AudioDirector.play_effect("launch", 0.7)
	if not SettingsStore.reduced_motion():
		_spawn_burst(ball.global_position + Vector3(0, -0.18, 0), Color(0.75, 0.72, 0.62), 8, 1.6)


## Presentation-only juice (D-021): the spring animates a child VisualRoot,
## never the RigidBody3D transform, so physics and scoring stay untouched.
func _kick_squash(velocity: float) -> void:
	if SettingsStore.reduced_motion() or _sinking:
		return
	_squash_vel += velocity


## READY-state hop (D-026): bounces the mascot's visual node up and back; the
## RigidBody never moves. Kill any running hop so rapid taps never stack.
func _play_decorative_hop() -> void:
	if _visual_root == null or _sinking:
		return
	_set_expression("happy")
	_kick_squash(-3.0)
	if SettingsStore.reduced_motion():
		return
	if _hop_tween != null and _hop_tween.is_valid():
		_hop_tween.kill()
	_visual_root.position.y = 0.0
	_hop_tween = create_tween()
	_hop_tween.tween_property(_visual_root, "position:y", 0.35, 0.22
		).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_hop_tween.tween_property(_visual_root, "position:y", 0.0, 0.22
		).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)


## Finish moment: the frozen ball funnels into the cup while shrinking.
func _play_cup_sink() -> void:
	if SettingsStore.reduced_motion() or _visual_root == null:
		return
	_sinking = true
	_visual_root.scale = Vector3.ONE
	camera_rig.add_trauma(0.4)
	var sink := create_tween()
	# Two-beat cup drop (M5 feel pass): a short rim hesitation, then the
	# rattle down to the cavity floor — reads as weight, not a teleport.
	sink.tween_interval(0.12)
	sink.tween_property(ball, "global_position",
		Vector3(level.cup_position().x, level.cup_plane_y() - 0.08, level.cup_position().z), 0.10
		).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	# Target sits on the physical cavity floor (ball center = plane - depth + radius);
	# note cup_position().y is the marker anchor, the plane is cup_plane_y().
	var rest_y := level.cup_plane_y() - GameSessionController.CUP_CAVITY_DEPTH + 0.25
	sink.parallel().tween_property(_visual_root, "scale", Vector3(0.62, 0.62, 0.62), 0.16
		).set_delay(0.12)
	sink.tween_property(ball, "global_position",
		Vector3(level.cup_position().x, rest_y, level.cup_position().z), 0.26
		).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)


## Upgrades the authored flat cup sticker into a real recessed hole: the turf
## COLLIDER is carved open (see _carve_cup_cavity) and the visuals match —
## beveled white lip, dark cavity walls you can see into, metallic floor liner.
## Dimensions mirror GameSessionController.CUP_HOLE_RADIUS / CUP_CAVITY_DEPTH.
func _build_real_cup() -> void:
	if level == null:
		return
	var cup_pos := level.cup_position()
	var cup_y := level.cup_plane_y()
	var old_ring := level.find_child("Ring", true, false) as MeshInstance3D
	if old_ring != null:
		old_ring.visible = false
	var hole_r: float = GameSessionController.CUP_HOLE_RADIUS
	var depth: float = GameSessionController.CUP_CAVITY_DEPTH
	var cup_root := Node3D.new()
	cup_root.name = "RealCupVisual"
	add_child(cup_root)
	cup_root.global_position = Vector3(cup_pos.x, cup_y, cup_pos.z)

	var shadow := MeshInstance3D.new()
	var shadow_mesh := CylinderMesh.new()
	shadow_mesh.top_radius = hole_r + 0.12
	shadow_mesh.bottom_radius = hole_r + 0.12
	shadow_mesh.height = 0.003
	shadow.mesh = shadow_mesh
	var shadow_mat := StandardMaterial3D.new()
	shadow_mat.albedo_color = Color(0.04, 0.10, 0.05, 0.55)
	shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow.material_override = shadow_mat
	shadow.position = Vector3(0.0, 0.002, 0.0)
	cup_root.add_child(shadow)

	var rim := MeshInstance3D.new()
	var rim_mesh := TorusMesh.new()
	rim_mesh.inner_radius = hole_r
	rim_mesh.outer_radius = hole_r + 0.08
	rim.mesh = rim_mesh
	var rim_mat := StandardMaterial3D.new()
	rim_mat.albedo_color = Color(0.97, 0.97, 0.98)
	rim_mat.roughness = 0.2
	rim.material_override = rim_mat
	rim.scale = Vector3(1.0, 0.18, 1.0)
	rim.position = Vector3(0.0, 0.005, 0.0)
	cup_root.add_child(rim)

	# Cavity walls: open-topped tube with double-sided shading so looking in
	# shows the dark inside of the liner instead of a flat black cap.
	var walls := MeshInstance3D.new()
	var walls_mesh := CylinderMesh.new()
	walls_mesh.top_radius = hole_r
	walls_mesh.bottom_radius = hole_r - 0.01
	walls_mesh.height = depth
	walls_mesh.cap_top = false
	walls_mesh.cap_bottom = false
	walls_mesh.radial_segments = 24
	walls.mesh = walls_mesh
	var walls_mat := StandardMaterial3D.new()
	walls_mat.albedo_color = Color(0.02, 0.03, 0.03)
	walls_mat.roughness = 0.95
	walls_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	walls.material_override = walls_mat
	walls.position = Vector3(0.0, -depth * 0.5, 0.0)
	cup_root.add_child(walls)

	var liner := MeshInstance3D.new()
	var liner_mesh := CylinderMesh.new()
	liner_mesh.top_radius = hole_r - 0.01
	liner_mesh.bottom_radius = hole_r - 0.01
	liner_mesh.height = 0.02
	liner.mesh = liner_mesh
	var liner_mat := StandardMaterial3D.new()
	liner_mat.albedo_color = Color(0.45, 0.48, 0.52)
	liner_mat.metallic = 0.7
	liner_mat.roughness = 0.35
	liner.material_override = liner_mat
	liner.position = Vector3(0.0, -depth + 0.01, 0.0)
	cup_root.add_child(liner)

	# Deferred: space-state queries only see bodies after a physics step has
	# flushed the just-entered tree, and capture works on flat turf meanwhile.
	_carve_cup_deferred(cup_pos, cup_y, hole_r, depth)


func _carve_cup_deferred(cup_pos: Vector3, cup_y: float, hole_r: float, depth: float) -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not is_inside_tree():
		return
	_carve_cup_cavity(cup_pos, cup_y, hole_r, depth)


## Physics + visual half of the real cup: replaces the single turf BoxShape3D
## under the cup with slabs around a square cut whose corners are filled back
## to make the opening circular, mirrors those pieces as visible turf meshes
## (hiding the now-hole-less original), then adds a cavity wall + floor on the
## Course layer. The ball now genuinely drops in; capture recognizes it below
## the rim (QA-024 keeps flyovers out: that branch only fires below the plane).
func _carve_cup_cavity(cup_pos: Vector3, cup_y: float, hole_r: float, depth: float) -> void:
	var space := level.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		Vector3(cup_pos.x, cup_y + 0.5, cup_pos.z),
		Vector3(cup_pos.x, cup_y - 1.0, cup_pos.z)
	)
	query.collision_mask = 0b0000_0000_0010  # Course only
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return
	var body := hit.get("collider") as StaticBody3D
	if body == null:
		return
	# Find the box shape whose footprint covers the cup (kit turf is boxes).
	for child in body.get_children():
		var shape_node := child as CollisionShape3D
		if shape_node == null or not (shape_node.shape is BoxShape3D):
			continue
		var box := shape_node.shape as BoxShape3D
		var to_box: Transform3D = (body.global_transform * shape_node.transform).affine_inverse()
		var cup_local := to_box * Vector3(cup_pos.x, cup_y, cup_pos.z)
		var half := box.size * 0.5
		if absf(cup_local.x) > half.x or absf(cup_local.z) > half.z:
			continue
		if cup_local.y < -half.y - 0.5 or cup_local.y > half.y + 0.5:
			continue
		# Cut rect clamped to the box (cup may sit near an edge).
		var cut_min_x := maxf(cup_local.x - hole_r, -half.x)
		var cut_max_x := minf(cup_local.x + hole_r, half.x)
		var cut_min_z := maxf(cup_local.z - hole_r, -half.z)
		var cut_max_z := minf(cup_local.z + hole_r, half.z)
		var pieces: Array = []
		# Four slabs preserve the full rectangular turf footprint while leaving a
		# square opening around the cup.
		if cut_max_x < half.x:
			pieces.append({
				"center": Vector3((cut_max_x + half.x) * 0.5, 0.0, 0.0),
				"size": Vector3(half.x - cut_max_x, box.size.y, box.size.z),
			})
		if cut_min_x > -half.x:
			pieces.append({
				"center": Vector3((cut_min_x - half.x) * 0.5, 0.0, 0.0),
				"size": Vector3(cut_min_x + half.x, box.size.y, box.size.z),
			})
		if cut_max_z < half.z:
			pieces.append({
				"center": Vector3((cut_min_x + cut_max_x) * 0.5, 0.0, (cut_max_z + half.z) * 0.5),
				"size": Vector3(cut_max_x - cut_min_x, box.size.y, half.z - cut_max_z),
			})
		if cut_min_z > -half.z:
			pieces.append({
				"center": Vector3((cut_min_x + cut_max_x) * 0.5, 0.0, (cut_min_z - half.z) * 0.5),
				"size": Vector3(cut_max_x - cut_min_x, box.size.y, cut_min_z + half.z),
			})
		# Fill the four square corners outside the circular radius. The inner
		# corner of each block sits on r/sqrt(2), so the opening reads circular.
		var reaches_full_x := [
			cut_max_x >= cup_local.x + hole_r - 0.001,
			cut_min_x <= cup_local.x - hole_r + 0.001,
		]
		var reaches_full_z := [
			cut_max_z >= cup_local.z + hole_r - 0.001,
			cut_min_z <= cup_local.z - hole_r + 0.001,
		]
		var fill := hole_r * (1.0 - 0.70710678)
		var fill_center := hole_r - fill * 0.5
		for quad: Array in [
			[reaches_full_x[1], reaches_full_z[1], -1.0, -1.0],
			[reaches_full_x[1], reaches_full_z[0], -1.0, 1.0],
			[reaches_full_x[0], reaches_full_z[1], 1.0, -1.0],
			[reaches_full_x[0], reaches_full_z[0], 1.0, 1.0],
		]:
			if bool(quad[0]) and bool(quad[1]):
				pieces.append({
					"center": Vector3(cup_local.x + quad[2] * fill_center, 0.0, cup_local.z + quad[3] * fill_center),
					"size": Vector3(fill, box.size.y, fill),
				})
		if pieces.is_empty():
			continue
		var shape_world: Transform3D = body.global_transform * shape_node.transform
		_hide_turf_visual_twin(shape_world, box.size)
		for piece: Dictionary in pieces:
			var new_shape := CollisionShape3D.new()
			var new_box := BoxShape3D.new()
			new_box.size = piece["size"]
			new_shape.shape = new_box
			new_shape.transform = shape_node.transform * Transform3D(Basis.IDENTITY, piece["center"])
			body.add_child(new_shape)
			var turf := MeshInstance3D.new()
			var turf_mesh := BoxMesh.new()
			turf_mesh.size = piece["size"]
			turf.mesh = turf_mesh
			if _cup_twin_material != null:
				turf.material_override = _cup_twin_material
			add_child(turf)
			turf.global_transform = shape_world * Transform3D(Basis.IDENTITY, piece["center"])
		body.remove_child(shape_node)
		shape_node.queue_free()
		break
	# Cavity walls (double-sided concave ring) + floor on the Course layer.
	var cup_body := StaticBody3D.new()
	cup_body.name = "RealCupPhysics"
	cup_body.collision_layer = 0b0000_0000_0010
	cup_body.collision_mask = 0
	add_child(cup_body)
	cup_body.global_position = Vector3(cup_pos.x, cup_y, cup_pos.z)
	var seg := 24
	var verts := PackedVector3Array()
	for i: int in seg:
		var a0 := TAU * float(i) / float(seg)
		var a1 := TAU * float(i + 1) / float(seg)
		var p0 := Vector3(cos(a0) * hole_r, 0.0, sin(a0) * hole_r)
		var p1 := Vector3(cos(a1) * hole_r, 0.0, sin(a1) * hole_r)
		var b0 := p0 + Vector3(0.0, -depth, 0.0)
		var b1 := p1 + Vector3(0.0, -depth, 0.0)
		verts.append_array([p0, p1, b1, p0, b1, b0])
	var walls_shape := ConcavePolygonShape3D.new()
	walls_shape.backface_collision = true
	walls_shape.set_faces(verts)
	var walls_node := CollisionShape3D.new()
	walls_node.shape = walls_shape
	cup_body.add_child(walls_node)
	var floor_shape := CylinderShape3D.new()
	floor_shape.radius = hole_r
	floor_shape.height = 0.04
	var floor_node := CollisionShape3D.new()
	floor_node.shape = floor_shape
	floor_node.position = Vector3(0.0, -depth - 0.02, 0.0)
	cup_body.add_child(floor_node)


## The kit renders turf as a BoxMesh whose transform and size match the
## collider box; find that visual twin by world position + size and hide it,
## or the turf texture would still paint across the carved opening.
func _hide_turf_visual_twin(shape_world: Transform3D, size: Vector3) -> void:
	var stack: Array[Node] = [level]
	_cup_twin_material = null
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		var mesh_node := node as MeshInstance3D
		if mesh_node == null or not (mesh_node.mesh is BoxMesh):
			continue
		var box_mesh := mesh_node.mesh as BoxMesh
		if (box_mesh.size - size).length() > 0.01:
			continue
		if mesh_node.global_transform.origin.distance_to(shape_world.origin) > 0.05:
			continue
		_cup_twin_material = mesh_node.material_override
		mesh_node.visible = false
		return


## Asset-pack dressing: a few scenery islands OUTSIDE course bounds and a
## wooden "HOLE N · Par X" sign at the tee. Deterministic per level id.
## Dev-only on-device perf overlay (RB-052 preparation): ROAR3D_PERF=1
## shows fps + frame-time ms so a phone soak session can be filmed and read.
func _maybe_build_perf_overlay() -> void:
	if OS.get_environment("ROAR3D_PERF").is_empty():
		return
	_perf_label = Label.new()
	_perf_label.name = "PerfOverlay"
	_perf_label.position = Vector2(8, 64)
	_perf_label.add_theme_font_size_override("font_size", 14)
	_perf_label.add_theme_color_override("font_color", RoarTheme.PRIMARY_GREEN)
	_perf_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	($GameUI/SafeAreaRoot as Control).add_child(_perf_label)


func _spawn_scenery(level_id: String) -> void:
	var bounds := level.course_bounds()
	var seed_value := hash(level_id)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var half_w := bounds.size.x * 0.5  # real half-width: on wide courses a 3 m
	# cap would drop islands INTO the course's screen band, crowding the rails.
	# Floating islands flanking BOTH sides of the course, close enough to the
	# rails and high enough to read in the narrow portrait frustum (the 19°
	# half-FOV only spans ~±3.5 m at 10 m out, so islands hug the course).
	for i: int in 10:
		var variant := rng.randi_range(0, 3)
		var piece := Scenery.build(variant, rng.randf_range(1.0, 1.8))
		add_child(piece)
		_disable_cast_shadow(piece)
		var side := -1.0 if i % 2 == 0 else 1.0
		var out := rng.randf_range(half_w + 1.0, half_w + 2.4)
		piece.position = Vector3(
			side * out,
			rng.randf_range(1.2, 4.0),
			bounds.position.z + bounds.size.z * (0.25 + 0.7 * rng.randf())
		)
		piece.rotation_degrees = Vector3(0.0, rng.randf_range(0.0, 360.0), 0.0)
	_spawn_clouds(bounds, level_id)
	_spawn_gap_dressing(level_id, bounds)


## Hole-specific flourish (M5 art pass): CC04's leap gets drifting rock shards
## below the gap so the signature jump reads as a chasm crossing. Deterministic
## per level id; decorative only (no collision, never above kill plane logic).
func _spawn_gap_dressing(level_id: String, bounds: AABB) -> void:
	if not level_id.begins_with("CC04"):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(level_id + ":gap")
	var shard_material := StandardMaterial3D.new()
	shard_material.albedo_color = Color("6b6157")
	shard_material.roughness = 1.0
	for i: int in 7:
		var shard := MeshInstance3D.new()
		var rock := SphereMesh.new()
		var r := rng.randf_range(0.25, 0.7)
		rock.radius = r
		rock.height = r * rng.randf_range(1.2, 1.9)
		rock.radial_segments = 6
		rock.rings = 4
		shard.mesh = rock
		shard.material_override = shard_material
		add_child(shard)
		_disable_cast_shadow(shard)
		shard.position = Vector3(
			rng.randf_range(-2.2, 2.2),
			rng.randf_range(-4.5, -1.5),
			bounds.position.z + bounds.size.z * rng.randf_range(0.35, 0.55)
		)
		shard.rotation_degrees = Vector3(rng.randf_range(0, 40), rng.randf_range(0, 360), rng.randf_range(0, 40))


## Dressing must never shadow the playfield: the sun sits at ~40°, so island
## and cloud shadows would sweep across the course and darken every hole.
func _disable_cast_shadow(node: Node) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_disable_cast_shadow(child)


## Clouds in the band the portrait camera actually shows: near the vanishing
## point ahead and high over the course (unshaded white puffs, read against
## the bright sky). A couple trail behind for the overview camera.
func _spawn_clouds(bounds: AABB, level_id: String) -> void:
	var cloud_material := StandardMaterial3D.new()
	cloud_material.albedo_color = Color(1.0, 1.0, 1.0)
	cloud_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(level_id)
	for c: int in 7:
		var cloud := Node3D.new()
		add_child(cloud)
		_disable_cast_shadow(cloud)
		var puff_count := rng.randi_range(2, 3)
		for p: int in puff_count:
			var puff := MeshInstance3D.new()
			var sphere := SphereMesh.new()
			sphere.radius = rng.randf_range(2.2, 4.2)
			sphere.height = sphere.radius * 2.0
			puff.mesh = sphere
			puff.material_override = cloud_material
			puff.scale = Vector3(1.4, 0.5, 1.0)
			puff.position = Vector3(p * sphere.radius * 1.1 - sphere.radius * 0.5, rng.randf_range(-0.3, 0.3), 0.0)
			cloud.add_child(puff)
		var ahead := bounds.position.z - rng.randf_range(12.0, 30.0)
		var behind := bounds.end.z + rng.randf_range(16.0, 40.0)
		cloud.position = Vector3(
			# Keep puffs OFF the course column (|x| > 3): a white puff crossing
			# the vanishing point reads as a gray band across the far holes.
			(3.0 + rng.randf_range(0.0, 8.0)) * (1.0 if c % 2 == 0 else -1.0),
			# High enough to sit above the play camera's horizon line — clouds
			# belong to the sky band of the frame, never over the course.
			rng.randf_range(6.0, 10.0),
			ahead if c % 3 != 2 else behind
		)


func _spawn_hole_sign(level_id: String, par: int) -> void:
	var sign_root := Node3D.new()
	sign_root.name = "HoleSign"
	add_child(sign_root)
	var spawn_pos := level.spawn_transform().origin
	var to_cup := ShotMath.horizontal_direction(level.cup_position() - spawn_pos)
	if to_cup == Vector3.ZERO:
		to_cup = Vector3(0, 0, -1)
	var side := to_cup.cross(Vector3.UP).normalized()
	sign_root.global_position = spawn_pos + side * 1.9 + Vector3(0, 0, 0)
	sign_root.look_at(sign_root.global_position + side, Vector3.UP)
	var post := MeshInstance3D.new()
	var post_box := BoxMesh.new()
	post_box.size = Vector3(0.1, 0.9, 0.1)
	post.mesh = post_box
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("7a5230")
	post.material_override = wood
	post.position = Vector3(0, 0.45, 0)
	sign_root.add_child(post)
	var board := MeshInstance3D.new()
	var board_box := BoxMesh.new()
	board_box.size = Vector3(0.95, 0.5, 0.06)
	board.mesh = board_box
	var board_mat := StandardMaterial3D.new()
	board_mat.albedo_color = Color("c9a36a")
	board.material_override = board_mat
	board.position = Vector3(0, 1.0, 0)
	sign_root.add_child(board)
	var label := Label3D.new()
	label.text = "%s\nPar %d" % [level_id, par]
	label.font_size = 40
	label.modulate = Color("3a2a18")
	label.outline_size = 8
	label.outline_modulate = Color("f5e9c8")
	label.pixel_size = 0.004
	label.position = Vector3(0, 1.0, 0.04)
	sign_root.add_child(label)


## Camera-facing face rig (docs/07 §5): the lion face billboards toward the
## camera independently of the rolling sphere so the mascot stays readable.
## Body, mane, and face all live under a scaled VisualRoot so squash &
## stretch (D-021) deforms the character while the RigidBody transform and
## its CollisionShape3D stay untouched.
func _build_visual_root() -> void:
	_visual_root = Node3D.new()
	_visual_root.name = "VisualRoot"
	ball.add_child(_visual_root)
	for body_part in ["BallMesh", "ManeMesh"]:
		var mesh := ball.get_node_or_null(NodePath(body_part))
		if mesh is Node3D:
			(mesh as Node3D).reparent(_visual_root)
	_mane = _visual_root.get_node_or_null(NodePath("ManeMesh")) as Node3D
	if _mane != null:
		_mane_base = _mane.scale
	_load_mascot_asset()


## RB-027: the production lion GLB replaces the primitive body/mane/ears/face.
## Loaded under VisualRoot; _wire_mascot_face() moves its expression subtrees
## onto the face rig. Legacy primitives stay as a fallback when the asset is
## missing. The collider, mass, and shot tuning are untouched by construction.
func _load_mascot_asset() -> void:
	if not ResourceLoader.exists(MASCOT_ASSET):
		return
	var packed := load(MASCOT_ASSET) as PackedScene
	if packed == null:
		return
	var mascot := packed.instantiate()
	mascot.name = "MascotAsset"
	_visual_root.add_child(mascot)
	_using_mascot_asset = true
	for legacy in ["BallMesh", "ManeMesh"]:
		var node := _visual_root.get_node_or_null(NodePath(legacy)) as Node3D
		if node != null:
			node.visible = false


func _build_face_rig() -> void:
	_face_rig = Node3D.new()
	_face_rig.name = "FaceRig"
	_visual_root.add_child(_face_rig)
	if _using_mascot_asset:
		_wire_mascot_face()
	else:
		_wire_legacy_face()
	_build_expression_layer()


## Asset path (RB-027): expression subtrees (mane, ears, face) move onto the
## face rig so they billboard; the body stays under VisualRoot. Legacy face
## primitives still parented to the ball are hidden, not freed.
func _wire_mascot_face() -> void:
	var mascot := _visual_root.get_node_or_null(NodePath("MascotAsset")) as Node3D
	if mascot == null:
		_wire_legacy_face()
		return
	for legacy in ["EyeWhiteLeft", "EyeWhiteRight", "EyeLeft", "EyeRight", "Muzzle", "Nose"]:
		var node := ball.get_node_or_null(NodePath(legacy)) as Node3D
		if node != null:
			node.visible = false
	# Recursive lookups: the importer wraps authored nodes an extra level
	# (MascotAsset/LionBall/...), so direct child paths do not resolve.
	for part in ["Mane", "EarOuterL", "EarOuterR", "EarInnerL", "EarInnerR", "FaceRoot"]:
		var subtree := mascot.find_child(part, true, false) as Node3D
		if subtree != null:
			subtree.reparent(_face_rig)
	_mane = _face_rig.get_node_or_null(NodePath("Mane")) as Node3D
	if _mane != null:
		_mane_base = _mane.scale
	for ear_name in ["EarOuterL", "EarOuterR", "EarInnerL", "EarInnerR"]:
		var ear := _face_rig.find_child(ear_name, true, false) as MeshInstance3D
		if ear != null:
			_ears.append(ear)
	# Imported glTF scenes may re-parent authored grandchildren, so pupils are
	# resolved by name search, not by authored path.
	for pupil_name in ["PupilL", "PupilR"]:
		var pupil := _face_rig.find_child(pupil_name, true, false) as MeshInstance3D
		if pupil != null:
			_blink_meshes.append(pupil)
			_blink_base.append(pupil.scale.y)
			_add_catchlight(pupil)


## Fallback path: the pre-asset primitives from the ball scene, re-rigged.
func _wire_legacy_face() -> void:
	for face_part in ["EyeWhiteLeft", "EyeWhiteRight", "EyeLeft", "EyeRight", "Muzzle", "Nose"]:
		var mesh := ball.get_node_or_null(NodePath(face_part))
		if mesh is Node3D:
			(mesh as Node3D).reparent(_face_rig)
			if face_part.begins_with("Eye"):
				_blink_meshes.append(mesh as MeshInstance3D)
				_blink_base.append((mesh as Node3D).scale.y)

	for eye_name in ["EyeLeft", "EyeRight"]:
		var eye := _face_rig.get_node_or_null(NodePath(eye_name)) as Node3D
		if eye != null:
			_add_catchlight(eye)

		# Cute lion ears (asset pack lion reference): outer round ear + soft cream inner ear.
		var ear_outer_mat := StandardMaterial3D.new()
		ear_outer_mat.albedo_color = Color(0.98, 0.74, 0.26)
		ear_outer_mat.roughness = 0.6
		var ear_inner_mat := StandardMaterial3D.new()
		ear_inner_mat.albedo_color = Color(0.98, 0.82, 0.70)
		ear_inner_mat.roughness = 0.7
		for side in [-1.0, 1.0]:
			var ear_outer := MeshInstance3D.new()
			var outer_mesh := SphereMesh.new()
			outer_mesh.radius = 0.068
			outer_mesh.height = 0.12
			ear_outer.mesh = outer_mesh
			ear_outer.material_override = ear_outer_mat
			ear_outer.position = Vector3(side * 0.175, 0.20, 0.04)
			ear_outer.scale = Vector3(1.0, 1.15, 0.6)
			_face_rig.add_child(ear_outer)
			_ears.append(ear_outer)

			var ear_inner := MeshInstance3D.new()
			var inner_mesh := SphereMesh.new()
			inner_mesh.radius = 0.042
			inner_mesh.height = 0.075
			ear_inner.mesh = inner_mesh
			ear_inner.material_override = ear_inner_mat
			ear_inner.position = Vector3(side * 0.175, 0.20, 0.072)
			ear_inner.scale = Vector3(1.0, 1.0, 0.5)
			_face_rig.add_child(ear_inner)
			_ears.append(ear_inner)

	# The mane becomes a halo behind the face (asset-pack lion look): the
	# authored torus rings the ball's equator like Saturn, which reads as a
	# headband once the face billboards. Re-ring it around the face axis.
	var mane := _visual_root.get_node_or_null(NodePath("ManeMesh")) as Node3D
	if mane != null:
		mane.reparent(_face_rig)
		mane.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, 0.02, 0.10))
		mane.scale = Vector3(1.5, 1.5, 1.5)
		_mane = mane
		_mane_base = mane.scale


## Cartoon specular eye catchlight: makes the character look lively and awake.
func _add_catchlight(eye: Node3D) -> void:
	var shine_mat := StandardMaterial3D.new()
	shine_mat.albedo_color = Color(1.0, 1.0, 1.0)
	shine_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var shine := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.018
	sphere.height = 0.036
	shine.mesh = sphere
	shine.material_override = shine_mat
	shine.position = Vector3(0.016, 0.018, 0.038)
	eye.add_child(shine)


## Mode-independent expression layer: brows, smile + tongue, O-mouth, blink
## timer targets — driven by _set_expression/_animate_character.
func _build_expression_layer() -> void:
	# Eyebrows: expressive dark arches that react to aim, charge, and outcomes.
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color("2a1f1a")
	var brow_box := BoxMesh.new()
	brow_box.size = Vector3(0.048, 0.013, 0.015)
	for side in [-1.0, 1.0]:
		var brow := MeshInstance3D.new()
		brow.mesh = brow_box
		brow.material_override = dark
		var base_pos := Vector3(side * 0.075, 0.142, 0.22)
		var base_rot := Vector3(0, 0, side * -8.0)
		brow.position = base_pos
		brow.rotation_degrees = base_rot
		_face_rig.add_child(brow)
		_brows.append(brow)
		_brow_base_pos.append(base_pos)
		_brow_base_rot.append(base_rot)

	# Expressions: smile (with cute pink tongue) and O-mouth (surprised/roar/sad)
	var tongue_mat := StandardMaterial3D.new()
	tongue_mat.albedo_color = Color("f06292")
	tongue_mat.roughness = 0.5

	_mouth_smile = MeshInstance3D.new()
	var smile_mesh := BoxMesh.new()
	smile_mesh.size = Vector3(0.13, 0.038, 0.02)
	_mouth_smile.mesh = smile_mesh
	_mouth_smile.material_override = dark
	_mouth_smile.position = Vector3(0, -0.125, 0.265)
	_mouth_smile.rotation_degrees = Vector3(0, 0, 4)
	_face_rig.add_child(_mouth_smile)
	_mouth_smile_base = _mouth_smile.scale

	_mouth_tongue = MeshInstance3D.new()
	var tongue_mesh := SphereMesh.new()
	tongue_mesh.radius = 0.026
	tongue_mesh.height = 0.035
	_mouth_tongue.mesh = tongue_mesh
	_mouth_tongue.material_override = tongue_mat
	_mouth_tongue.position = Vector3(0.0, -0.012, 0.008)
	_mouth_tongue.scale = Vector3(1.2, 0.8, 0.6)
	_mouth_smile.add_child(_mouth_tongue)

	_mouth_o = MeshInstance3D.new()
	var o_mesh := SphereMesh.new()
	o_mesh.radius = 0.042
	o_mesh.height = 0.04
	_mouth_o.mesh = o_mesh
	_mouth_o.material_override = dark
	_mouth_o.position = Vector3(0, -0.125, 0.265)
	_mouth_o.visible = false
	_face_rig.add_child(_mouth_o)

	var o_tongue := MeshInstance3D.new()
	var o_tongue_mesh := SphereMesh.new()
	o_tongue_mesh.radius = 0.022
	o_tongue_mesh.height = 0.025
	o_tongue.mesh = o_tongue_mesh
	o_tongue.material_override = tongue_mat
	o_tongue.position = Vector3(0.0, -0.016, 0.008)
	_mouth_o.add_child(o_tongue)


func _set_expression(kind: String) -> void:
	if _mouth_smile == null or _mouth_o == null:
		return
	match kind:
		"surprised":
			_mouth_smile.visible = false
			_mouth_o.visible = true
			_start_expression_timeout(0.9)
			_apply_brow_offsets(Vector3(0, 0.025, 0), Vector3(0, 0, 14.0))
		"happy":
			# Big grin for the finish moment, back to idle after the burst.
			_mouth_smile.visible = true
			_mouth_o.visible = false
			_mouth_smile.scale = Vector3(_mouth_smile_base.x * 1.7, _mouth_smile_base.y * 1.3, _mouth_smile_base.z)
			_start_expression_timeout(1.4)
			_apply_brow_offsets(Vector3(0, 0.015, 0), Vector3(0, 0, 6.0))
		"sad":
			_mouth_smile.visible = false
			_mouth_o.visible = true
			_sad_active = true
			_start_expression_timeout(1.2)
			_apply_brow_offsets(Vector3(0, -0.015, 0), Vector3(0, 0, -20.0))
		"concentrating":
			_mouth_smile.visible = true
			_mouth_o.visible = false
			_mouth_smile.scale = _mouth_smile_base
			_apply_brow_offsets(Vector3(0, -0.012, 0), Vector3(0, 0, 18.0))
		_:
			_sad_active = false
			_mouth_smile.visible = true
			_mouth_o.visible = false
			_mouth_smile.scale = _mouth_smile_base
			_apply_brow_offsets(Vector3.ZERO, Vector3.ZERO)


func _apply_brow_offsets(pos_offset: Vector3, rot_offset: Vector3) -> void:
	for i: int in _brows.size():
		var side := -1.0 if i == 0 else 1.0
		_brows[i].position = _brow_base_pos[i] + pos_offset
		_brows[i].rotation_degrees = _brow_base_rot[i] + Vector3(rot_offset.x, rot_offset.y, rot_offset.z * side)


func _start_expression_timeout(seconds: float) -> void:
	_expression_timer = get_tree().create_timer(seconds, true)
	_expression_timer.timeout.connect(func() -> void: _set_expression("idle"))


## Asset-pack VFX: short one-shot particle bursts (confetti, grass, dust).
func _spawn_burst(pos: Vector3, color: Color, count: int, speed: float) -> void:
	var particles := CPUParticles3D.new()
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = count
	particles.lifetime = 1.1
	particles.direction = Vector3.UP
	particles.spread = 75.0
	particles.initial_velocity_min = speed * 0.5
	particles.initial_velocity_max = speed
	particles.gravity = Vector3(0, -9.8, 0)
	particles.scale_amount_min = 0.6
	particles.scale_amount_max = 1.2
	var chunk := BoxMesh.new()
	chunk.size = Vector3(0.055, 0.055, 0.055)
	particles.mesh = chunk
	particles.color = color
	add_child(particles)
	particles.global_position = pos
	particles.emitting = true
	particles.finished.connect(particles.queue_free)


## Portal Peaks gets the asset-pack sunset sky; Cloud Cliffs keeps sunny day.
func _apply_world_sky(level_id: String) -> void:
	var env := ($WorldRoot/Lighting/WorldEnvironment.environment as Environment)
	if env == null or env.sky == null:
		return
	# Ambient is pinned to a near-white color instead of the sky's: the scene
	# has no ambient override, so a saturated zenith would tint every surface
	# teal/blue. Sky stays decorative; sun + neutral ambient light the course.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1.0, 0.98, 0.94)
	env.ambient_light_energy = 1.0
	var sky_mat := env.sky.sky_material as ProceduralSkyMaterial
	var sun := $WorldRoot/Lighting/DirectionalLight3D as DirectionalLight3D
	if level_id.begins_with("PP"):
		if sky_mat != null:
			sky_mat.sky_top_color = Color("4a2d6e")
			sky_mat.sky_horizon_color = Color("ff9a5c")
			sky_mat.ground_horizon_color = Color("e8875a")
			sky_mat.ground_bottom_color = Color("3a2b4f")
		if sun != null:
			sun.light_color = Color("ffd2a0")
			# The purple dusk sky tints every sky-ambient surface; extra direct sun
			# keeps the turf reading green under the sunset mood.
			sun.light_energy = 1.4
		_apply_fog(env, Color("e8a06a"), 0.010)
	else:
		# CC worlds (M5 art pass): crisp high-altitude daylight — deeper cyan
		# zenith so the green course pops, warm horizon, light depth fog so
		# distant islands read as atmosphere instead of floating cutouts.
		if sky_mat != null:
			sky_mat.sky_top_color = Color("3a86dd")
			sky_mat.sky_horizon_color = Color("cfe9ff")
			sky_mat.ground_horizon_color = Color("aedcf5")
			sky_mat.ground_bottom_color = Color("6f95a8")
		if sun != null:
			sun.light_color = Color("fff4dd")
			sun.light_energy = 1.15
		_apply_fog(env, Color("e6dfc8"), 0.004)


## Light aerial perspective: starts past the playfield so gameplay contrast is
## untouched, and melts distant scenery into the sky.
func _apply_fog(env: Environment, color: Color, density: float) -> void:
	env.fog_enabled = true and OS.get_environment("ROAR3D_NO_FOG").is_empty()
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = color
	env.fog_density = density
	env.fog_sky_affect = 0.0  # sky already carries its own gradient


func _build_aim_guide() -> void:
	# Stylized trajectory guide matching 01_original_gameplay.png:
	# circular glowing dotted nodes and a prominent 3D chevron arrowhead pointing along -Z.
	_aim_guide = Node3D.new()
	_aim_guide.name = "AimGuide"
	for i: int in 10:
		var segment := MeshInstance3D.new()
		var disk := CylinderMesh.new()
		var r := 0.06 + float(i) * 0.006
		disk.top_radius = r
		disk.bottom_radius = r
		disk.height = 0.015
		segment.mesh = disk
		segment.position = Vector3(0.0, 0.0, -0.42 - float(i) * 0.36)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(1.0, 1.0, 1.0, 0.70)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		segment.material_override = material
		_aim_guide.add_child(segment)
		_aim_segments.append(segment)

	# Forward Arrowhead at the guide tip pointing along -Z (local +Y rotated to -Z)
	_aim_arrow = MeshInstance3D.new()
	_aim_arrow.name = "AimArrow"
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.16
	cone.height = 0.28
	_aim_arrow.mesh = cone
	_aim_arrow.rotation_degrees = Vector3(90, 0, 0)
	var arrow_mat := StandardMaterial3D.new()
	arrow_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.90)
	arrow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	arrow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_aim_arrow.material_override = arrow_mat
	_aim_arrow.position = Vector3(0.0, 0.0, -2.5)
	_aim_guide.add_child(_aim_arrow)
	camera_rig.add_child(_aim_guide)


func _process(delta: float) -> void:
	if _face_rig != null and is_instance_valid(ball) and camera_rig != null:
		_face_rig.global_position = ball.global_position
		var cam := camera_rig.camera
		if cam != null:
			# Full billboard (D-021): look_at aims -Z at the camera, so the
			# old rotate_y(PI) flip mirrored the elevation — the face pointed
			# 40° down at a camera sitting 40° up and bunched at the bottom of
			# the ball's silhouette. Build the basis directly so +Z (the face
			# side) tracks the camera's true direction, elevation included.
			var z := (cam.global_position - _face_rig.global_position).normalized()
			var x := Vector3.UP.cross(z)
			x = x.normalized() if x.length_squared() > 0.0001 else Vector3.RIGHT
			_face_rig.basis = Basis(x, z.cross(x), z)
		_animate_character(delta)
	if _flag_mesh != null and not SettingsStore.reduced_motion():
		_flag_time += delta
		# Flutter intensity breathes with the ball's proximity: a rolling
		# ball "stirs the air" so the flag reacts to the play, not just time.
		var flutter := 1.0
		if _sinking:
			flutter = 3.2  # celebration wobble on the finished hole
		elif is_instance_valid(ball) and session != null and session.level != null:
			var d := ball.global_position.distance_to(level.cup_position())
			flutter = 1.0 + clampf(2.2 - d * 0.28, 0.0, 1.6)
		_flag_mesh.rotation.z = sin(_flag_time * 3.1) * 0.13 * flutter
		_flag_mesh.rotation.x = sin(_flag_time * 2.3) * 0.06 * flutter
	if _perf_label != null:
		_perf_frames += 1
		_perf_accum += delta
		if _perf_accum >= 0.5:
			var fps := _perf_frames / _perf_accum
			_perf_label.text = "%d fps · %.1f ms" % [roundi(fps), _perf_accum / _perf_frames * 1000.0]
			_perf_accum = 0.0
			_perf_frames = 0
	# Camera anticipation feed: slingshot stretch (or roar-band voice preview)
	# pulls the camera back slightly; release snaps forward via follow lerp.
	if coordinator != null and coordinator.is_slinging():
		camera_rig.set_charge(coordinator.slingshot_power())
	else:
		camera_rig.set_charge(0.0)

	# Rolling particle trail: kicks up subtle turf speckles while moving
	if ball != null and ball.linear_speed() > 1.4 and ball.is_supported():
		_roll_particle_timer -= delta
		if _roll_particle_timer <= 0.0:
			_roll_particle_timer = 0.12
			_spawn_burst(ball.global_position + Vector3(0, -0.15, 0), Color(0.48, 0.78, 0.42), 3, 0.8)
	# Rolling texture follows ball speed; airborne or resting = silent.
	if ball != null and not _sinking:
		var roll := ball.linear_speed() / 8.0 if ball.is_supported() else 0.0
		AudioDirector.set_roll_intensity(roll)

	if _aim_guide == null or session == null:
		return
	var show_guide := session.can_aim() and not camera_rig.is_overview()
	_aim_guide.visible = show_guide
	if show_guide:
		_aim_pulse_time += delta * 4.0
		var ball_pos := session.ball.global_position
		_aim_guide.global_position = ball_pos + Vector3(0.0, 0.03, 0.0)
		_aim_guide.look_at(ball_pos + session.aim_direction, Vector3.UP)

		# Slingshot / Voice feedback: length scales dynamically with pull, color shifts whisper→speak→roar
		var power := 0.0
		var is_sling := coordinator != null and coordinator.is_slinging()
		if is_sling:
			power = coordinator.slingshot_power()
			# Tension audio clicks at power tier crossings (35% speak, 70% roar)
			var band := 0 if power < 0.35 else (1 if power < 0.70 else 2)
			if _last_sling_band != -1 and band > _last_sling_band:
				AudioDirector.play_effect("stretch", 0.45 + band * 0.15)
				if band == 2:
					# Roar ignition (M5 feel pass): one restrained ember burst
					# when the pull crosses into the loft tier.
					_spawn_burst(ball.global_position + Vector3(0, 0.15, 0), RoarTheme.METER_ROAR, 10, 2.2)
					_set_expression("surprised")
			_last_sling_band = band
		elif voice != null and voice.is_listening():
			power = float(voice.published_preview()["power"])
		else:
			_last_sling_band = -1

		var active_count := 6 if power <= 0.0 else clampi(3 + int(round(power * 7.0)), 3, 10)
		var tint := Color(1.0, 1.0, 1.0, 0.65) if power <= 0.0 \
			else RoarTheme.METER_WHISPER.lerp(RoarTheme.METER_ROAR, power)

		# 3D Parabolic Arc when loft is active (ROAR tier: power >= 0.70)
		var loft_height := 0.0
		if power >= 0.70:
			loft_height = (power - 0.70) / 0.30 * 0.52

		for i: int in _aim_segments.size():
			var segment := _aim_segments[i]
			segment.visible = i < active_count
			var material := segment.material_override as StandardMaterial3D
			if material != null:
				var wave := sin(_aim_pulse_time - float(i) * 0.4) * 0.18 + 0.82
				material.albedo_color = Color(tint.r, tint.g, tint.b, clampf(tint.a * wave, 0.25, 0.95))
			var t := float(i) / float(maxi(active_count - 1, 1))
			segment.position = Vector3(0.0, sin(t * PI) * loft_height, -0.42 - float(i) * 0.36)

		if _aim_arrow != null:
			_aim_arrow.visible = true
			_aim_arrow.position = Vector3(0.0, 0.0, -0.42 - float(active_count) * 0.36)
			var arrow_mat := _aim_arrow.material_override as StandardMaterial3D
			if arrow_mat != null:
				arrow_mat.albedo_color = tint


# --- Pause / overview: one authority, one order of operations ---


## Character life (D-021): blink cycle, squash & stretch spring, and the
## mane puffing up while a slingshot shot charges. All writes target the
## VisualRoot subtree — physics state is never touched.
func _animate_character(delta: float) -> void:
	# Blink: fast close-open every few seconds; the sad face droops the lids.
	_blink_timer -= delta
	if _blink_phase >= 0.0:
		_blink_phase += delta
		if _blink_phase >= 0.12:
			_blink_phase = -1.0
			_blink_timer = randf_range(2.2, 4.6)
	var openness := 1.0
	if _blink_phase >= 0.0:
		var k := _blink_phase / 0.06
		openness = 1.0 - 0.92 * (k if _blink_phase < 0.06 else 2.0 - k)
	if _sad_active:
		openness = minf(openness, 0.45)
	for i: int in _blink_meshes.size():
		_blink_meshes[i].scale.y = _blink_base[i] * openness
	if _sinking:
		return  # the sink tween owns the visual scale from here
	# Squash & stretch spring toward rest.
	if not SettingsStore.reduced_motion():
		_squash_vel += (-SQUASH_SPRING_K * _squash - SQUASH_SPRING_D * _squash_vel) * delta
		_squash = clampf(_squash + _squash_vel * delta, -SQUASH_CLAMP, SQUASH_CLAMP)
	if _visual_root != null:
		var s := _squash
		_visual_root.scale = Vector3(1.0 + s * 0.55, 1.0 - s * 0.9, 1.0 + s * 0.55)
		# Mane puffs up and ears pin back with slingshot charge: the lion visibly powers up!
		if _mane != null:
			var target := 0.0
			if coordinator != null and coordinator.is_slinging() and session.can_aim():
				target = coordinator.slingshot_power()
				if not _sad_active:
					_set_expression("concentrating")
			_mane_puff = lerpf(_mane_puff, target, minf(delta * 9.0, 1.0))
			_mane.scale = _mane_base * (1.0 + 0.16 * _mane_puff)
			for ear: MeshInstance3D in _ears:
				ear.rotation.x = -0.32 * _mane_puff


## Pause cancels capture first (never a hidden hold), then cancels any
## un-committed shot in the session, then pauses the tree. Resume reverses;
## the mic never restarts by itself.
func set_gameplay_paused(paused: bool) -> void:
	if paused:
		if camera_rig.is_overview():
			camera_rig.set_overview_active(false)
			hud.set_overview_indicator(false)
		coordinator.interrupt_capture()
		session.pause_session()  # discards COMMIT_PENDING without a stroke
		hud.show_pause()
		get_tree().paused = true
	else:
		get_tree().paused = false
		session.resume_session()
		hud.hide_pause()


## Overview is a Ready-only inspection; the whole simulation pauses
## consistently while it is open (docs/05 §7), through this same authority.
func toggle_overview() -> void:
	if camera_rig.is_overview():
		camera_rig.set_overview_active(false)
		hud.set_overview_indicator(false)
		get_tree().paused = false
		return
	if get_tree().paused or session.fsm.state != GameStateMachine.State.READY:
		return
	camera_rig.set_overview_active(true)
	hud.set_overview_indicator(true)
	get_tree().paused = true


# --- Calibration orchestration (RB-021 core; HUD drives, service measures) ---


func start_calibration_stage(stage: String) -> bool:
	if stage not in ["room", "soft", "strong"]:
		return false
	coordinator.interrupt_capture()
	if not PlatformAdapter.try_request_microphone_permission():
		hud.on_calibration_stage_done({"ok": false, "error_code": "permission_denied"})
		return true  # sheet already informed; no async stage running
	if not voice.begin_calibration_stage(stage):
		hud.on_calibration_stage_done({"ok": false, "error_code": "no_input"})
		return true
	_cal_stage = stage
	get_tree().create_timer(CAL_STAGE_SECONDS, true, false, true).timeout.connect(_finish_calibration_stage)
	return true


func _finish_calibration_stage() -> void:
	if _cal_stage.is_empty():
		return
	var summary := voice.finish_calibration_stage()
	summary["ok"] = _calibration_stage_ok(summary)
	var stage := String(summary.get("stage", ""))
	match stage:
		"room":
			_cal_room = summary
		"soft":
			_cal_soft = summary
		"strong":
			_cal_strong = summary
	_cal_stage = ""
	if stage == "strong" and bool(summary["ok"]):
		# Derive + persist before the sheet celebrates; a failed derivation
		# must offer a retry, not close into an uncalibrated voice mode.
		var result: Dictionary = voice.apply_calibration(_cal_room, _cal_soft, _cal_strong)
		if bool(result["valid"]):
			SettingsStore.set_calibration(result["calibration"])
			voice.calibration = result["calibration"]
		else:
			summary = {"ok": false, "error_code": String(result["error_code"]), "stage": "strong"}
	hud.on_calibration_stage_done(summary)


func _calibration_stage_ok(summary: Dictionary) -> bool:
	# Room only needs enough data; soft/strong need >= 0.3 s qualified
	# (docs/04 §4) and a usable level.
	if String(summary.get("stage", "")) == "room":
		return float(summary.get("noise_level_db", -999.0)) > -999.0
	return float(summary.get("qualified_sec", 0.0)) >= 0.3 and float(summary.get("level_db", -999.0)) > -999.0


func cancel_calibration_stage() -> void:
	if not _cal_stage.is_empty():
		_cal_stage = ""
		voice.end_capture()


# --- Navigation / lifecycle ---


func _restart_level() -> void:
	_teardown()
	AppRouter.goto_game(session.level_id)


func _to_map() -> void:
	_teardown()
	AppRouter.goto_map()


func _next_hole() -> void:
	_teardown()
	var next := ProgressStore.next_playable_level()
	if next.is_empty() or next == session.level_id:
		AppRouter.goto_home()
	else:
		AppRouter.goto_game(next)


func _teardown() -> void:
	get_tree().paused = false
	coordinator.interrupt_capture()
	voice.end_capture()
	level.unload()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_APPLICATION_PAUSED:
			# Background/focus loss: close capture, cancel un-committed shot,
			# pause the session; resume never restarts the mic (FR-15).
			if is_instance_valid(hud) and not hud.is_paused_sheet_visible():
				set_gameplay_paused(true)
		NOTIFICATION_PREDELETE:
			if is_instance_valid(level):
				level.unload()


# --- Dev-only visual evidence helpers (env-gated) ---


## ROAR3D_SCREENSHOT=/tmp/shot.png — Ready state capture.
func _maybe_capture_evidence_screenshot() -> void:
	var shot_path := OS.get_environment("ROAR3D_SCREENSHOT")
	if shot_path.is_empty():
		return
	for i: int in 300:
		if session.fsm.state == GameStateMachine.State.READY:
			break
		await get_tree().create_timer(0.05).timeout
	await get_tree().create_timer(0.8).timeout
	var image := get_viewport().get_texture().get_image()
	image.save_png(shot_path)
	print("screenshot saved: " + shot_path)
	# Ground-truth dump for visual verification: what occupies the ball's
	# screen position in this exact capture.
	var cam := camera_rig.camera
	var screen_pos := cam.unproject_position(ball.global_position)
	var img_size := image.get_size()
	if screen_pos.x >= 0 and screen_pos.y >= 0 and screen_pos.x < img_size.x and screen_pos.y < img_size.y:
		var px := int(screen_pos.x)
		var py := int(screen_pos.y)
		var samples: Array[String] = []
		for dy: int in range(-8, 9, 4):
			for dx: int in range(-8, 9, 4):
				var x := clampi(px + dx, 0, img_size.x - 1)
				var y := clampi(py + dy, 0, img_size.y - 1)
				var c := image.get_pixel(x, y)
				samples.append("(%d,%d)%s" % [x, y, c.to_html(false)])
		print("ball_screen=", screen_pos, " samples=", " ".join(samples))
	# Optional second capture: ROAR3D_SCREENSHOT_PAUSE — paused sheet state.
	var pause_path := OS.get_environment("ROAR3D_SCREENSHOT_PAUSE")
	if not pause_path.is_empty():
		set_gameplay_paused(true)
		await get_tree().create_timer(0.4).timeout
		var paused_image := get_viewport().get_texture().get_image()
		paused_image.save_png(pause_path)
		print("screenshot saved: " + pause_path)
		set_gameplay_paused(false)
	# Optional third capture: ROAR3D_SCREENSHOT_RESULT — restyled result
	# sheet after the star pop settles. Display-only fake payload; nothing
	# is recorded to progress storage.
	var result_path := OS.get_environment("ROAR3D_SCREENSHOT_RESULT")
	if not result_path.is_empty():
		hud._on_hole_completed({"stars": 3, "strokes": 2, "par": 3, "is_new_best": true})
		await get_tree().create_timer(1.8).timeout
		var result_image := get_viewport().get_texture().get_image()
		result_image.save_png(result_path)
		print("screenshot saved: " + result_path)
	get_tree().quit(0)
