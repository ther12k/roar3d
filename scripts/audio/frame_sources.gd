class_name VoiceFrameSource
extends RefCounted
## Where analysis frames come from. The real path wraps an AudioEffectCapture
## fed by an AudioStreamPlayer(AudioStreamMicrophone) on the MicCapture bus;
## tests inject the synthetic source so both flow through identical analysis.


func start() -> bool:
	return false


func stop() -> void:
	pass


func clear_buffer() -> void:
	pass


## All frames currently available; consumed (removed) from the source.
func pull_frames() -> PackedVector2Array:
	return PackedVector2Array()


## Frames per second of the stream feeding analysis (window sizes derive from
## this — never a hardcoded device rate; docs/04 §3).
func sample_rate() -> int:
	return 48000


func frames_discarded() -> int:
	return 0


## --- Real microphone source: player node + capture effect on MicCapture ---


class MicFrameSource extends VoiceFrameSource:
	var player: AudioStreamPlayer
	var capture: AudioEffectCapture

	static func create(parent: Node) -> MicFrameSource:
		var source := MicFrameSource.new()
		source.player = AudioStreamPlayer.new()
		source.player.name = "MicPlayer"
		source.player.stream = AudioStreamMicrophone.new()
		source.player.autoplay = false
		source.player.bus = "MicCapture"
		source.capture = AudioEffectCapture.new()
		source.capture.buffer_length = 0.25
		parent.add_child(source.player)
		return source

	func start() -> bool:
		if player == null or capture == null:
			return false
		# Add/refresh the capture effect first in the MicCapture chain.
		var bus_index := AudioServer.get_bus_index("MicCapture")
		if bus_index < 0:
			return false
		for i: int in AudioServer.get_bus_effect_count(bus_index):
			AudioServer.remove_bus_effect(bus_index, i)
		AudioServer.add_bus_effect(bus_index, capture, 0)
		capture.clear_buffer()
		player.play()
		return player.playing

	func stop() -> void:
		if player != null and player.playing:
			player.stop()
		if capture != null:
			capture.clear_buffer()

	func clear_buffer() -> void:
		if capture != null:
			capture.clear_buffer()

	func pull_frames() -> PackedVector2Array:
		if capture == null:
			return PackedVector2Array()
		var available := capture.get_frames_available()
		if available <= 0:
			return PackedVector2Array()
		# 4.7.2 API: AudioEffectCapture.get_buffer(count). There is no
		# get_frames(); a unit test pins this against ClassDB.
		return capture.get_buffer(available)

	func sample_rate() -> int:
		return AudioServer.get_mix_rate()

	func frames_discarded() -> int:
		return capture.get_discarded_frames() if capture != null else 0


## --- Synthetic source for deterministic tests (docs/04 §8 fixtures) ---


class SyntheticFrameSource extends VoiceFrameSource:
	var rate := 48000
	var _queue: Array[PackedVector2Array] = []
	var _discarded := 0

	func push_frames(frames: PackedVector2Array) -> void:
		_queue.append(frames)

	## Convenience: `ms` of a constant-amplitude stereo tone (phase-opposed
	## channels optional via sign) split into 20 ms chunks.
	func push_constant_ms(ms: int, amplitude: float, opposite_phase := false, chunk_ms := 20) -> void:
		var frames_per_ms := rate / 1000
		var total := int(float(ms) * frames_per_ms)
		var chunk_frames := int(float(chunk_ms) * frames_per_ms)
		var phase := 0.0
		var written := 0
		while written < total:
			var count := mini(chunk_frames, total - written)
			var frames := PackedVector2Array()
			frames.resize(count)
			for i: int in count:
				frames[i] = Vector2(amplitude, -amplitude if opposite_phase else amplitude)
				phase += 0.0
			_queue.append(frames)
			written += count

	func push_silence_ms(ms: int, chunk_ms := 20) -> void:
		push_constant_ms(ms, 0.0, false, chunk_ms)

	func start() -> bool:
		return true

	func pull_frames() -> PackedVector2Array:
		var pulled := PackedVector2Array()
		for chunk: PackedVector2Array in _queue:
			pulled.append_array(chunk)
		_queue.clear()
		return pulled

	func sample_rate() -> int:
		return rate

	func mark_overrun(frames: int) -> void:
		_discarded += frames

	func frames_discarded() -> int:
		return _discarded
