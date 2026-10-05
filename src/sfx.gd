# Every sound is synthesized at runtime, so the project ships with zero audio files.
# ponytail: placeholder synth; swap streams for real .ogg files when you have them.
extends RefCounted

const RATE := 22050
const LOOPS := ["drone", "motor", "chug", "muzak", "wind", "grind", "rumble"]
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
		"creak": s = _creak(0.7)
		"grind": s = _grind(2.0)
		"rumble": s = _rumble(4.0)
		"roar": s = _mix(_sweep(160.0, 55.0, 2.2, 0.8), _noise(2.2, 1.0, 0.97))
		"thud": s = _mix(_tone(55.0, 0.35, 9.0), _noise(0.3, 14.0, 0.95))
		"snap": s = _mix(_noise(0.15, 30.0, 0.2), _tone(900.0, 0.12, 30.0, true))
		"slurp": s = _sweep(300.0, 90.0, 0.6, 3.0)
		"chitter": s = _chitter(0.5)
		"clack": s = _mix(_tone(1200.0, 0.04, 80.0, true), _noise(0.04, 90.0, 0.3))
		"hiss": s = _noise(0.8, 3.0, 0.1)
		"flash": s = _sweep(2400.0, 5200.0, 0.25, 8.0)
		"wind": s = _wind(6.0)
		"motor": s = _motor(4.0)
		"chug": s = _chug(1.0)
		"muzak": s = _muzak()
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
	if sound in LOOPS:
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


static func _motor(dur: float) -> PackedFloat32Array:
	# Elevator winch hum: 50 Hz + harmonics, whole cycles over the loop.
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		out[i] = 0.3 * sin(TAU * 50.0 * t) + 0.15 * sin(TAU * 100.0 * t) + 0.08 * sin(TAU * 150.0 * t) * (0.7 + 0.3 * sin(TAU * t))
	return out


static func _chug(dur: float) -> PackedFloat32Array:
	# Four exhaust bursts per loop; pitch it up with speed.
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var last := 0.0
	for i in n:
		var ph := fmod(float(i) / n * 4.0, 1.0)
		last = lerpf(randf_range(-1.0, 1.0), last, 0.9)
		out[i] = last * 1.6 * exp(-ph * 9.0) + 0.15 * sin(TAU * 40.0 * float(i) / RATE)
	return out


static func _muzak() -> PackedFloat32Array:
	# A cheerful little elevator tune. Notes in Hz, 0 = rest.
	var notes := [523.3, 659.3, 784.0, 659.3, 698.5, 587.3, 0.0, 587.3, 523.3, 659.3, 784.0, 1046.5, 987.8, 784.0, 0.0, 0.0]
	var step := int(0.32 * RATE)
	var out := PackedFloat32Array()
	out.resize(step * notes.size())
	for k in notes.size():
		var f: float = notes[k]
		for j in step:
			var t := float(j) / RATE
			var v := 0.0
			if f > 0.0:
				v = (sin(TAU * f * t) + 0.3 * sin(TAU * f * 2.0 * t)) * exp(-t * 5.0) * 0.35
			v += 0.12 * sin(TAU * [130.8, 98.0, 110.0, 87.3][k / 4] * t) * minf(1.0, j / 300.0) * minf(1.0, (step - j) / 300.0)
			out[k * step + j] = v
	return out


static func _creak(dur: float) -> PackedFloat32Array:
	# Stick-slip hinge: a jittery low buzz that wobbles in pitch.
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		ph += TAU * (170.0 + 60.0 * sin(TAU * 1.3 * t) + randf_range(-25.0, 25.0)) / RATE
		var saw := fmod(ph / TAU, 1.0) * 2.0 - 1.0
		out[i] = saw * 0.25 * (0.6 + 0.4 * sin(TAU * 9.0 * t)) * _env(i, n) * minf(1.0, (n - i) / 3000.0)
	return out


static func _wind(dur: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var last := 0.0
	for i in n:
		var t := float(i) / RATE
		last = lerpf(randf_range(-1.0, 1.0), last, 0.985)
		out[i] = last * 2.2 * (0.55 + 0.45 * sin(TAU * t / 3.0))
	return out


static func _grind(dur: float) -> PackedFloat32Array:
	# Stone dragging on stone: rough low noise with a scraping wobble. Loops.
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var last := 0.0
	for i in n:
		var t := float(i) / RATE
		last = lerpf(randf_range(-1.0, 1.0), last, 0.8)
		out[i] = last * 0.9 * (0.6 + 0.4 * sin(TAU * 3.0 * t)) * (0.7 + 0.3 * sin(TAU * 0.5 * t))
	return out


static func _rumble(dur: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var last := 0.0
	for i in n:
		var t := float(i) / RATE
		last = lerpf(randf_range(-1.0, 1.0), last, 0.996)
		out[i] = last * 5.0 + 0.3 * sin(TAU * 31.0 * t) * (0.6 + 0.4 * sin(TAU * t / 2.0))
	return out


static func _chitter(dur: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var burst := 1.0 if fmod(t * 22.0, 1.0) < 0.35 else 0.0
		out[i] = randf_range(-1.0, 1.0) * burst * 0.4 * _env(i, n)
	return out
