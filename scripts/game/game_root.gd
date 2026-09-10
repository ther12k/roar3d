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

@onready var session: GameSessionController = $GameSessionController
@onready var coordinator: InputCoordinator = $InputCoordinator
@onready var level: LevelController = $WorldRoot/LevelController
@onready var ball: BallController = $WorldRoot/Ball
@onready var camera_rig: CameraRig = $WorldRoot/CameraRig
@onready var voice: VoiceInputService = $VoiceInputService
@onready var hud: HUDPresenter = $GameUI/SafeAreaRoot

var _aim_guide: Node3D = null
var _aim_segments: Array[MeshInstance3D] = []
var _face_rig: Node3D = null
var _mouth_smile: MeshInstance3D = null
var _mouth_o: MeshInstance3D = null
var _expression_timer: SceneTreeTimer = null
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
		_set_expression("surprised")
	)
	session.hole_completed.connect(func(_result: Dictionary) -> void:
		AudioDirector.play_effect("cup")
		_spawn_burst(level.cup_position() + Vector3(0, 0.4, 0), RoarTheme.WARM_ACCENT, 26, 5.0)
		_spawn_burst(level.cup_position() + Vector3(0, 0.5, 0), RoarTheme.VOICE_CYAN, 18, 4.5)
		_spawn_burst(level.cup_position() + Vector3(0, 0.6, 0), RoarTheme.PRIMARY_GREEN, 18, 4.5)
		_set_expression("happy")
	)
	ball.fall_detected.connect(func(_reason: String) -> void: _on_any_fall())
	level.kill_zone_entered.connect(func() -> void: _on_any_fall())
	ball.settled.connect(func(_t: Transform3D, _ok: bool) -> void:
		_spawn_burst(ball.global_position, Color(0.75, 0.72, 0.66), 8, 1.2))  # landing dust

	_apply_equipped_cosmetic()
	_build_face_rig()
	_build_aim_guide()
	ball.freeze = true
	session.start_level()
	ball.freeze = false
	_maybe_capture_evidence_screenshot()


## Cosmetics are visual-only (docs/07 §5): collider, mass, and physics stay
## identical; the equipped ball just re-tints the body mesh.
func _apply_equipped_cosmetic() -> void:
	var equipped := ProgressStore.equipped_cosmetic()
	var mesh: MeshInstance3D = ball.find_child("BallMesh", true, false)
	var mane: MeshInstance3D = ball.find_child("ManeMesh", true, false)
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
	hud.show_out_of_bounds()


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
	var half_w := minf(bounds.size.x * 0.5, 3.0)
	# Floating islands flanking BOTH sides of the course, close enough to the
	# rails and high enough to read in the narrow portrait camera frame.
	for i: int in 10:
		var variant := rng.randi_range(0, 3)
		var piece := Scenery.build(variant, rng.randf_range(1.0, 2.2))
		add_child(piece)
		_disable_cast_shadow(piece)
		var side := -1.0 if i % 2 == 0 else 1.0
		var out := rng.randf_range(half_w + 1.2, half_w + 2.8)
		piece.position = Vector3(
			side * out,
			rng.randf_range(0.4, 3.2),
			bounds.position.z + bounds.size.z * (0.25 + 0.7 * rng.randf())
		)
		piece.rotation_degrees = Vector3(0.0, rng.randf_range(0.0, 360.0), 0.0)
	_spawn_clouds(bounds, level_id)


## Dressing must never shadow the playfield: the sun sits at ~40°, so island
## and cloud shadows would sweep across the course and darken every hole.
func _disable_cast_shadow(node: Node) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_disable_cast_shadow(child)


## Puffs BEYOND the course ends (course kit forward is -Z) so they sit small
## and bright near the horizon inside the narrow portrait frustum.
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
			sphere.radius = rng.randf_range(1.8, 3.4)
			sphere.height = sphere.radius * 2.0
			puff.mesh = sphere
			puff.material_override = cloud_material
			puff.scale = Vector3(1.4, 0.5, 1.0)
			puff.position = Vector3(p * sphere.radius * 1.1 - sphere.radius * 0.5, rng.randf_range(-0.3, 0.3), 0.0)
			cloud.add_child(puff)
		var ahead := bounds.position.z - rng.randf_range(14.0, 46.0)
		var behind := bounds.end.z + rng.randf_range(16.0, 40.0)
		cloud.position = Vector3(
			rng.randf_range(-14.0, 14.0),
			rng.randf_range(2.5, 7.0),
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
func _build_face_rig() -> void:
	_face_rig = Node3D.new()
	_face_rig.name = "FaceRig"
	ball.add_child(_face_rig)
	for face_part in ["EyeWhiteLeft", "EyeWhiteRight", "EyeLeft", "EyeRight", "Muzzle", "Nose"]:
		var mesh := ball.get_node_or_null(NodePath(face_part))
		if mesh is Node3D:
			(mesh as Node3D).reparent(_face_rig)
	# Expressions: smile (default) and O-mouth (surprised)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color("2a1f1a")
	_mouth_smile = MeshInstance3D.new()
	var smile_mesh := BoxMesh.new()
	smile_mesh.size = Vector3(0.13, 0.035, 0.02)
	_mouth_smile.mesh = smile_mesh
	_mouth_smile.material_override = dark
	_mouth_smile.position = Vector3(0, -0.095, 0.245)
	_mouth_smile.rotation_degrees = Vector3(0, 0, 8)
	_face_rig.add_child(_mouth_smile)
	_mouth_o = MeshInstance3D.new()
	var o_mesh := SphereMesh.new()
	o_mesh.radius = 0.035
	o_mesh.height = 0.03
	_mouth_o.mesh = o_mesh
	_mouth_o.material_override = dark
	_mouth_o.position = Vector3(0, -0.10, 0.245)
	_mouth_o.visible = false
	_face_rig.add_child(_mouth_o)


func _set_expression(kind: String) -> void:
	if _mouth_smile == null or _mouth_o == null:
		return
	match kind:
		"surprised":
			_mouth_smile.visible = false
			_mouth_o.visible = true
			_expression_timer = get_tree().create_timer(0.9, true)
			_expression_timer.timeout.connect(func() -> void: _set_expression("idle"))
		"happy":
			_mouth_smile.visible = true
			_mouth_o.visible = false
		_:
			_mouth_smile.visible = true
			_mouth_o.visible = false


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
	if not level_id.begins_with("PP"):
		return
	var env := ($WorldRoot/Lighting/WorldEnvironment.environment as Environment)
	if env == null or env.sky == null:
		return
	var sky_mat := env.sky.sky_material as ProceduralSkyMaterial
	if sky_mat != null:
		sky_mat.sky_top_color = Color("4a2d6e")
		sky_mat.sky_horizon_color = Color("ff9a5c")
		sky_mat.ground_horizon_color = Color("e8875a")
		sky_mat.ground_bottom_color = Color("3a2b4f")
	var sun := $WorldRoot/Lighting/DirectionalLight3D as DirectionalLight3D
	if sun != null:
		sun.light_color = Color("ffd2a0")


func _build_aim_guide() -> void:
	# Dotted guide pointing along the aim direction; length and color grow
	# with slingshot power while dragging (never a trajectory promise).
	_aim_guide = Node3D.new()
	_aim_guide.name = "AimGuide"
	for i: int in 6:
		var segment := MeshInstance3D.new()
		var quad := BoxMesh.new()
		quad.size = Vector3(0.08, 0.02, 0.22)
		segment.mesh = quad
		segment.position = Vector3(0.0, 0.0, -0.45 - float(i) * 0.38)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(1.0, 1.0, 1.0, 0.55)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		segment.material_override = material
		_aim_guide.add_child(segment)
		_aim_segments.append(segment)
	camera_rig.add_child(_aim_guide)


func _process(delta: float) -> void:
	if _face_rig != null and is_instance_valid(ball) and camera_rig != null:
		_face_rig.global_position = ball.global_position
		var cam := camera_rig.camera
		if cam != null:
			_face_rig.look_at(cam.global_position, Vector3.UP)
			_face_rig.rotate_y(PI)  # face meshes live on the rig's +Z side
	if _perf_label != null:
		_perf_frames += 1
		_perf_accum += delta
		if _perf_accum >= 0.5:
			var fps := _perf_frames / _perf_accum
			_perf_label.text = "%d fps · %.1f ms" % [roundi(fps), _perf_accum / _perf_frames * 1000.0]
			_perf_accum = 0.0
			_perf_frames = 0
	if _aim_guide == null or session == null:
		return
	var show_guide := session.can_aim() and not camera_rig.is_overview()
	_aim_guide.visible = show_guide
	if show_guide:
		var ball_pos := session.ball.global_position
		_aim_guide.global_position = ball_pos + Vector3(0.0, 0.03, 0.0)
		_aim_guide.look_at(ball_pos + session.aim_direction, Vector3.UP)
		# Slingshot feedback: more segments + whisper→roar tint as power grows.
		var power := 0.0
		if coordinator != null and coordinator.is_slinging():
			power = coordinator.slingshot_power()
		var lit := 6 if power <= 0.0 else 2 + int(round(power * 4.0))
		var tint := Color(1.0, 1.0, 1.0, 0.55) if power <= 0.0 \
			else RoarTheme.METER_WHISPER.lerp(RoarTheme.METER_ROAR, power)
		for i: int in _aim_segments.size():
			var segment := _aim_segments[i]
			segment.visible = i < lit
			var material := segment.material_override as StandardMaterial3D
			if material != null:
				material.albedo_color = tint


# --- Pause / overview: one authority, one order of operations ---


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
	get_tree().quit(0)
