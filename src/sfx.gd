# Every sound is synthesized at runtime, so the project ships with zero audio files.
# ponytail: placeholder synth; swap streams for real .ogg files when you have them.
extends RefCounted

const RATE := 22050
static var _cache := {}


static func stream(sound: String) -> AudioStreamWAV:
	if not _cache.has(sound):
		_cache[sound] = _make(sound)
	return _cache[sound]


## pos == null plays it flat (UI); a Vector3 plays it in 3D at that spot.
static func play(parent: Node, sound: String, pos: Variant = null, db := 0.0, pitch := 1.0) -> void:
	if not parent.is_inside_tree():
		return
	if pos == null:
		var a := AudioStreamPlayer.new()
		a.stream = stream(sound)
		a.volume_db = db
		a.pitch_scale = pitch
		parent.add_child(a)
		a.finished.connect(a.queue_free)
		a.play()
	else:
		var a3 := AudioStreamPlayer3D.new()
		a3.stream = stream(sound)
		a3.volume_db = db
		a3.pitch_scale = pitch
		a3.unit_size = 6.0
		a3.max_distance = 70.0
		parent.add_child(a3)
		a3.global_position = pos
		a3.finished.connect(a3.queue_free)
		a3.play()


static func _make(sound: String) -> AudioStreamWAV:
	var s: PackedFloat32Array
	match sound:
		"beep": s = _tone(1500.0, 0.06, 0.0, true)
		"ding": s = _mix(_tone(988.0, 1.2, 3.0), _tone(1319.0, 1.2, 3.5))
		"pickup": s = _tone(700.0, 0.08, 25.0)
		"error": s = _tone(160.0, 0.2, 2.0, true)
		"key": s = _noise(0.012, 200.0, 0.2)
		"click": s = _noise(0.025, 120.0, 0.0)
		"step": s = _noise(0.09, 40.0, 0.92)
		"hurt": s = _noise(0.3, 9.0, 0.6)
		"boom": s = _noise(1.5, 3.0, 0.985)
		"door": s = _noise(1.0, 2.0, 0.97)
		"alarm": s = _siren(1.6)
		"horn": s = _mix(_tone(233.0, 1.6, 0.5, true), _tone(294.0, 1.6, 0.5, true))
		"scan": s = _sweep(400.0, 1600.0, 0.35, 6.0)
		"screech": s = _mix(_sweep(900.0, 2600.0, 0.6, 3.0), _noise(0.6, 4.0, 0.3))
		"drone": s = _drone(6.0)
		_: s = _tone(440.0, 0.1, 10.0)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	var b := PackedByteArray()
	b.resize(s.size() * 2)
	for i in s.size():
		b.encode_s16(i * 2, int(clampf(s[i], -1.0, 1.0) * 32000.0))
	w.data = b
	if sound == "drone":
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = s.size()
	return w


static func _env(i: int, n: int) -> float:
	return minf(1.0, i / 60.0) * minf(1.0, (n - i) / 200.0)


static func _tone(f: float, dur: float, decay: float, square := false) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var v := sin(TAU * f * t)
		if square:
			v = 0.5 * signf(v)
		out[i] = v * exp(-decay * t) * _env(i, n) * 0.6
	return out


static func _noise(dur: float, decay: float, smooth: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var gain := sqrt((1.0 + smooth) / (1.0 - smooth)) * 0.5
	var last := 0.0
	for i in n:
		last = lerpf(randf_range(-1.0, 1.0), last, smooth)
		out[i] = last * gain * exp(-decay * float(i) / RATE) * _env(i, n)
	return out


static func _sweep(f0: float, f1: float, dur: float, decay: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		ph += TAU * lerpf(f0, f1, float(i) / n) / RATE
		out[i] = sin(ph) * exp(-decay * float(i) / RATE) * _env(i, n) * 0.5
	return out


static func _siren(dur: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		ph += TAU * (650.0 + 250.0 * signf(sin(TAU * 2.5 * t))) / RATE
		out[i] = 0.35 * signf(sin(ph)) * _env(i, n)
	return out


static func _drone(dur: float) -> PackedFloat32Array:
	# Frequencies chosen to complete whole cycles so the loop is seamless.
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var last := 0.0
	for i in n:
		var t := float(i) / RATE
		last = lerpf(randf_range(-1.0, 1.0), last, 0.995)
		var wobble := 0.6 + 0.4 * sin(TAU * t / 3.0)
		out[i] = (0.35 * sin(TAU * 55.0 * t) + 0.2 * sin(TAU * 82.5 * t)) * wobble + last * 3.0
	return out


static func _mix(a: PackedFloat32Array, b: PackedFloat32Array) -> PackedFloat32Array:
	var n := mini(a.size(), b.size())
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = (a[i] + b[i]) * 0.7
	return out
