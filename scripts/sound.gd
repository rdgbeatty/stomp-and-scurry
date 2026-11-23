extends Node

const RATE := 22050
var muted := false
var _cues: Dictionary = {}


func _ready() -> void:
	_add_cue(&"start", _synthesize(0.24, 410.0, 820.0, 0.0), -13.0)
	_add_cue(&"warning", _synthesize(0.15, 530.0, 375.0, 0.11), -13.0)
	_add_cue(&"impact", _synthesize(0.32, 120.0, 42.0, 0.75), -9.0)
	_add_cue(&"dodge", _synthesize(0.19, 620.0, 1060.0, 0.0), -17.0)
	_add_cue(&"event", _synthesize(0.36, 350.0, 590.0, 0.15), -13.0)
	_add_cue(&"jump", _synthesize(0.19, 285.0, 720.0, 0.12), -14.0)
	_add_cue(&"pickup", _synthesize(0.21, 520.0, 1120.0, 0.0), -13.0)
	_add_cue(&"shield", _synthesize(0.23, 580.0, 240.0, 0.12), -13.0)
	_add_cue(&"bite", _synthesize(0.18, 250.0, 92.0, 0.7), -11.0)


func _add_cue(cue: StringName, stream: AudioStreamWAV, volume: float) -> void:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume
	add_child(player)
	_cues[cue] = player


func toggle_mute() -> void:
	muted = not muted
	if muted:
		for player: AudioStreamPlayer in _cues.values():
			player.stop()


func play_cue(cue: StringName) -> void:
	if not muted:
		_cues[cue].play()


func _synthesize(duration: float, start_hz: float, end_hz: float, noise: float) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.mix_rate = RATE
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	var frames := roundi(duration * RATE)
	var samples := PackedByteArray()
	samples.resize(frames * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 8172
	var phase := 0.0
	var smoothed_noise := 0.0
	for index in frames:
		var progress := float(index) / frames
		phase += TAU * lerpf(start_hz, end_hz, progress) / RATE
		smoothed_noise = lerpf(smoothed_noise, rng.randf_range(-1.0, 1.0), 0.41)
		var envelope := minf(1.0, progress * 45.0) * pow(1.0 - progress, 2.8)
		var tone := sin(phase) * 0.74 + sin(phase * 2.0) * 0.14
		var sample := (tone + smoothed_noise * noise) * envelope
		samples.encode_s16(index * 2, roundi(clampf(sample, -1.0, 1.0) * 29500.0))
	stream.data = samples
	return stream
