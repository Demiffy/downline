# The game's sounds: most made from real recordings and shipped as files (assets/sounds, listed in
# sound_files.gd: made by tools/sound_print.py from CC0 recordings, take by take); the rest synthesized
# here at startup: filters + modal synthesis (stacks of decaying partials) for metal. 3D sounds go through a
# "World" bus whose reverb follows where you are (set_space): a big hall underground, a small
# box in the train, almost dry outside.
extends RefCounted

const Files = preload("res://src/sound_files.gd")
const RATE := 22050
const LOOPS := ["truck_idle", "truck_rev", "fork_idle", "fork_work", "drone", "motor", "chug", "muzak", "wind", "grind", "rumble", "rail_roll", "prime_lo", "prime_mid", "prime_hi", "turbo", "traction",
	"diesel", "amb_factory", "amb_lab", "amb_flesh", "amb_backrooms", "amb_yard",
	"servo", "heartbeat", "searchlight", "drip_loop", "rattle", "chime", "steam", "buzz", "flare", "diesel_idle", "compressor", "lens_tick", "whisper", "breath", "heart", "shred_motor", "conveyor", "rain", "rain_roof", "flicker_buzz", "waterfall", "amb_dam", "plane_loop"]
const STEPS := ["concrete", "metal", "wood", "sand", "snow", "flesh", "carpet", "tiles", "water", "mud", "grass"]
static var _cache := {}
static var net_hook: Callable   # net.gd: decides whether a sound plays here and passes it on
static var _reverb: AudioEffectReverb
static var _take := 0
static var _r := RandomNumberGenerator.new()
static var _lock := Mutex.new()
static var _warming := false
## Everything _make() knows (warm() makes them all ahead).
const ALL := ["beep", "ding", "pickup", "error", "key", "click", "step", "hurt", "boom", "door", "alarm", "horn", "diesel_idle", "compressor", "air_release", "scan", "blip", "screech", "drone", "creak", "grind", "rumble", "roar", "growl", "shriek", "thud", "snap", "slurp", "chitter", "clack", "hiss", "flash", "wind", "rain", "rain_roof", "thunder", "stamp", "flicker_buzz", "motor", "chug", "muzak", "step_concrete", "step_tiles", "step_metal", "step_wood", "step_sand", "step_snow", "step_flesh", "step_carpet", "land", "clank", "clang_big", "thunk", "rustle", "slide", "clunk", "open_box", "heavy_lift", "amb_factory", "amb_lab", "amb_flesh", "amb_backrooms", "amb_yard", "diesel", "rail_clack", "rail_roll", "prime_lo", "prime_mid", "prime_hi", "turbo", "traction", "far_bang", "groan", "drip", "pipe_knock", "far_screech", "far_steps", "servo", "heartbeat", "searchlight", "drip_loop", "rattle", "chime", "step_water", "power_down", "power_up", "zap", "crackle", "buzz", "steam", "steam_burst", "cough", "quake", "debris", "plane", "flare", "shutter", "flash_whine", "flashbulb", "tinnitus", "lens_tick", "whisper", "wraith_shriek", "wraith_grab", "dissolve", "swish", "shotgun", "dry_fire", "breath", "heart", "gurgle", "alarm_bell", "bulkhead", "crack_glass", "klaxon", "door_open", "door_shut", "breaker", "shred_motor", "shred_metal", "shred_soft", "shred_jam", "ratchet", "conveyor", "waterfall", "amb_dam", "clap", "plane_loop", "chute_pop", "explosion_far", "crate_pry", "drop_fall", "drop_land", "backfire", "squeak", "jingle", "toot", "phone_ring", "vroom", "reverse_beep", "robot", "radio_tune", "typewriter", "speaker_pop", "whistle", "fart", "mumble", "truck_idle", "truck_rev", "fork_idle", "fork_work"]
## Sounds that come in several takes (so ten footsteps in a row aren't ten copies of one).
const TAKES := 4
static func _has_takes(sound: String) -> bool:
	return _takes(sound) > 1


## How many takes: a sound from files, as many as there are; of the synthesised ones footsteps and
## the other often-heard ones four (each with its own dice).
static func _takes(sound: String) -> int:
	if Files.TAKES.has(sound):
		return Files.TAKES[sound]
	return TAKES if sound.begins_with("step_") or sound in ["thunk", "clank", "door_shut", "drip", "rail_clack"] else 1


## Buses: World (3D effects, with reverb) and Ambience. Call once at startup.
static func setup() -> void:
	if AudioServer.get_bus_index("World") >= 0:
		return
	for name in ["World", "Ambience"]:
		var i := AudioServer.bus_count
		AudioServer.add_bus(i)
		AudioServer.set_bus_name(i, name)
		AudioServer.set_bus_send(i, "Master")
	_reverb = AudioEffectReverb.new()
	_reverb.predelay_feedback = 0.0   # (fed back, the predelay rang at ~33 Hz on the engine's chug and ran away: the tunnel clipped solid)
	_reverb.hipass = 0.15   # (the deep rumble stays dry; reverberated it only piles up into mud)
	AudioServer.add_bus_effect(AudioServer.get_bus_index("World"), _reverb)
	var lim := AudioEffectHardLimiter.new()   # whatever piles up, never a clipped square wave
	lim.ceiling_db = -0.5
	AudioServer.add_bus_effect(0, lim)
	var amb_rev := AudioEffectReverb.new()
	amb_rev.room_size = 0.9
	amb_rev.wet = 0.25
	AudioServer.add_bus_effect(AudioServer.get_bus_index("Ambience"), amb_rev)
	set_space("outside")
	if DirAccess.dir_exists_absolute("user://sfx_cache"):   # (the sounds built at startup once were cached there: files now)
		for f in DirAccess.get_files_at("user://sfx_cache"):
			DirAccess.remove_absolute("user://sfx_cache/" + f)
		DirAccess.remove_absolute("user://sfx_cache")
	warm()   # (all of them on a worker thread, the first-heard first: building them here held up the start by seconds)


## "underground" / "train" / "outside": how the world sounds around you.
static func set_space(space: String) -> void:
	if _reverb == null:
		return
	match space:
		"underground":
			_reverb.room_size = 0.85
			_reverb.damping = 0.35
			_reverb.wet = 0.32
			_reverb.predelay_msec = 60.0
		"tunnel":   # a long hard bore: the train's own din comes back at it
			_reverb.room_size = 0.7
			_reverb.damping = 0.3
			_reverb.wet = 0.3
			_reverb.predelay_msec = 30.0
		"train":
			_reverb.room_size = 0.25
			_reverb.damping = 0.6
			_reverb.wet = 0.12
			_reverb.predelay_msec = 10.0
		_:
			_reverb.room_size = 0.15
			_reverb.damping = 0.8
			_reverb.wet = 0.05
			_reverb.predelay_msec = 20.0


static func stream(sound: String) -> AudioStream:
	if _has_takes(sound) and not "#" in sound:
		_take += 1
		sound = "%s#%d" % [sound, _take % _takes(sound)]
	_lock.lock()   # (warm() may be making sounds on another thread)
	if not _cache.has(sound):
		var base := sound.get_slice("#", 0)
		if Files.TAKES.has(base):   # (a file: assets/sounds/<name>.ogg, or <name>_<take>.ogg)
			var path := "res://assets/sounds/%s.ogg" % (base if Files.TAKES[base] == 1 else "%s_%s" % [base, sound.get_slice("#", 1)])
			var o: AudioStreamOggVorbis = load(path)
			o.loop = base in LOOPS
			_cache[sound] = o
		else:
			_r.seed = hash(sound)   # synthesis has its own dice (each take its own), the same on every machine
			_cache[sound] = _make(sound)
	var w: AudioStream = _cache[sound]
	_lock.unlock()
	return w


## The name a stream was made or read in under ("step_metal#2"), or "" for one that isn't ours.
static func name_of(s: AudioStream) -> String:
	_lock.lock()
	var n = _cache.find_key(s)
	_lock.unlock()
	return "" if n == null else String(n)


## Every sound made (or read in) ahead on a worker thread, so none is made the moment it first plays
## (a hitch on the first door slam, the first roar...). The startup log waits for them (warm_progress).
static var _warm_total := 0
static var _warm_done := 0


static func warm() -> void:
	if _warming:
		return
	_warming = true
	var all: Array[String] = []
	for name: String in STEPS.map(func(k): return "step_" + k) + FIRST + ALL:
		if _has_takes(name):
			for t in _takes(name):
				all.append("%s#%d" % [name, t])
		else:
			all.append(name)
	_warm_total = all.size()
	WorkerThreadPool.add_task(func():
		for k in all:
			stream(k)
			_lock.lock()
			_warm_done += 1
			_lock.unlock(), false, "sfx warm")


## How far the warm-up has got, 0..1 (1: every sound is ready).
static func warm_progress() -> float:
	if not _warming:
		return 0.0
	_lock.lock()
	var f := float(_warm_done) / maxf(1.0, _warm_total)
	_lock.unlock()
	return f


const FIRST := ["land", "clank", "thunk", "rustle", "amb_factory", "amb_lab", "amb_flesh", "amb_backrooms", "amb_yard", "diesel", "rail_clack", "wind"]


## pos == null plays it flat (UI); a Vector3 plays it in 3D at that spot.
static func play(parent: Node, sound: String, pos: Variant = null, db := 0.0, pitch := 1.0) -> void:
	if not parent.is_inside_tree() or Engine.has_meta("hush"):
		return
	if net_hook.is_valid() and not net_hook.call(parent, sound, pos, db, pitch):
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
		a3.bus = "World" if AudioServer.get_bus_index("World") >= 0 else "Master"
		parent.add_child(a3)
		a3.global_position = pos
		a3.finished.connect(a3.queue_free)
		a3.play()


static func _make(sound: String) -> AudioStreamWAV:
	var s: PackedFloat32Array
	sound = sound.get_slice("#", 0)
	match sound:
		"error": s = _tone(160.0, 0.2, 2.0, true)
		"key": s = _noise(0.012, 200.0, 0.2)
		"click": s = _noise(0.025, 120.0, 0.0)
		"diesel_idle": s = _diesel_idle(2.0)
		"prime_lo": s = _prime_mover(400.0, 0.0)
		"prime_mid": s = _prime_mover(720.0, 0.5)
		"prime_hi": s = _prime_mover(1050.0, 1.0)
		"air_release": s = _add(_hp(_noise(1.4, 2.2, 0.15), 900.0), _lp(_noise(0.3, 12.0, 0.7), 500.0), 0.6)
		"scan": s = _add(_add(_sweep(220.0, 1500.0, 0.5, 3.5), _lp(_noise(0.9, 3.0, 0.9), 900.0), 0.5), _shift(_modal([1760.0, 2637.0, 3520.0], [5.0, 6.0, 8.0], [0.3, 0.2, 0.1], 1.4), 0.12), 0.8)
		"blip": s = _add(_tone(1320.0, 0.18, 22.0), _shift(_tone(1980.0, 0.12, 30.0), 0.035), 0.5)
		"flash": s = _sweep(2400.0, 5200.0, 0.25, 8.0)
		"wind": s = _wind(6.0)
		"stamp": s = _stamp()
		"flicker_buzz": s = _flicker_buzz(3.0)
		# --- footsteps by surface ---
		"step_concrete", "step_tiles", "step_metal", "step_wood", "step_sand", "step_snow", "step_mud", "step_grass":
			s = _step(sound.trim_prefix("step_"))
		# --- objects ---
		# --- ambience beds (loops) ---
		"amb_lab": s = _amb_lab(8.0)
		"amb_backrooms": s = _amb_backrooms(8.0)
		"amb_yard": s = _amb_yard(8.0)
		"diesel": s = _diesel(2.0)
		# --- distant one-shots for underground ---
		# --- creature loops ---
		"heartbeat": s = _heartbeat(2.0, 0.5)
		"searchlight": s = _searchlight(2.0)
		# --- hazards and events ---
		# --- toys and things that make a noise when you use them (data.gd "toy") ---
		"squeak": s = _squeak()
		"jingle": s = _jingle()
		"phone_ring": s = _phone_ring()
		"reverse_beep": s = _reverse_beep()
		"robot": s = _robot()
		"speaker_pop": s = _add(_hp(_grains(0.7, 60, 0.8), 1800.0), _buzz_tone(0.7, 50.0), 0.5)
		"buzz": s = _buzz_tone(2.0, 60.0)
		"explosion_far": s = _explosion_far()
		# Observer: a leaf shutter (cock, release, spring), a flash capacitor whining up, the bulb going off.
		"flash_whine": s = _add(_sweep(700.0, 7400.0, 0.7, 0.0), _hp(_noise(0.7, 0.0, 0.2), 4000.0), 0.08)
		# Wraith: a crowd of whispers, a shriek when the light burns it, a cold hiss when it takes hold.
		# Weapons: a swing through the air, a shotgun blast with its tail rolling off the walls.
		# Inside your helmet: breathing and your own heartbeat (pitch them up to speed them up).
		"heart": s = _heartbeat(1.0, 1.0)
		_: s = _tone(440.0, 0.1, 10.0)
	return _finish(sound, s)


## Samples into a stream: kept off clipping, loops set up.
static func _finish(sound: String, s: PackedFloat32Array) -> AudioStreamWAV:
	if sound in LOOPS:
		_seamless(s)
	var peak := 0.0
	for v in s:
		peak = maxf(peak, absf(v))
	if peak > 0.9:   # no clipping
		var k := 0.9 / peak
		for i in s.size():
			s[i] *= k
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	var n := s.size()
	if sound in LOOPS:   # the head again past the end: playback interpolates across loop_end into whatever lies there (zeros: a click every time round)
		s.append_array(s.slice(0, mini(64, n)))
	var b := PackedByteArray()
	b.resize(s.size() * 2)
	for i in s.size():
		b.encode_s16(i * 2, int(clampf(s[i], -1.0, 1.0) * 32000.0))
	w.data = b
	if sound in LOOPS:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = n
	return w


## A loop's last 0.1 s bent so it runs on into its first sample: filters start cold and noise
## doesn't wrap, so most loops jumped at the seam, a click every time round.
static func _seamless(s: PackedFloat32Array) -> void:
	var n := s.size()
	if n < 8:
		return
	var m := mini(RATE / 10, n / 4)
	var d := (2.0 * s[0] - s[1]) - s[n - 1]   # (where the end should be, to run on into the start)
	for i in m:
		s[n - m + i] += d * smoothstep(0.0, 1.0, float(i + 1) / m)


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
		last = lerpf(_r.randf_range(-1.0, 1.0), last, smooth)
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


static func _creak(dur: float) -> PackedFloat32Array:
	# Stick-slip hinge: a jittery low buzz that wobbles in pitch.
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		ph += TAU * (170.0 + 60.0 * sin(TAU * 1.3 * t) + _r.randf_range(-25.0, 25.0)) / RATE
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
		last = lerpf(_r.randf_range(-1.0, 1.0), last, 0.994)
		out[i] = last * 2.6 * (0.6 + 0.4 * sin(TAU * t / 6.0))
	return out


## A failing fluorescent tube: mains buzz that catches and drops out.
static func _flicker_buzz(dur: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var gate := 1.0
	for i in n:
		var t := float(i) / RATE
		if i % 800 == 0:
			gate = 1.0 if _r.randf() < 0.82 else 0.15
		var tone := sin(TAU * 120.0 * t) * 0.5 + sin(TAU * 240.0 * t) * 0.25 + signf(sin(TAU * 120.0 * t)) * 0.12
		out[i] = tone * gate * 0.5
	return _lp(out, 3000.0)


## A rubber stamp brought down hard on paper on a desk: the slap, the thump of the desk under it.
static func _stamp() -> PackedFloat32Array:
	var n := int(0.5 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var b := 0.0
	for i in n:
		var t := float(i) / RATE
		b += (_r.randf_range(-1.0, 1.0) - b) * 0.3
		out[i] = sin(TAU * 68.0 * t) * exp(-t * 18.0) * 0.95 + b * exp(-t * 60.0) * 0.8 + sin(TAU * 140.0 * t) * exp(-t * 30.0) * 0.3
	return out


## `wrap`: for a loop, start from the state it ends in (a cold start is a jump at the seam).
static func _lp(a: PackedFloat32Array, cutoff: float, wrap := false) -> PackedFloat32Array:
	var k := 1.0 - exp(-TAU * cutoff / RATE)
	var y := 0.0
	if wrap:
		for i in a.size():
			y += (a[i] - y) * k
	for i in a.size():
		y += (a[i] - y) * k
		a[i] = y
	return a


static func _hp(a: PackedFloat32Array, cutoff: float, wrap := false) -> PackedFloat32Array:
	var k := 1.0 - exp(-TAU * cutoff / RATE)
	var low := 0.0
	if wrap:
		for i in a.size():
			low += (a[i] - low) * k
	for i in a.size():
		low += (a[i] - low) * k
		a[i] = a[i] - low
	return a


static func _bp(a: PackedFloat32Array, lo: float, hi: float, wrap := false) -> PackedFloat32Array:
	return _lp(_hp(a, lo, wrap), hi, wrap)


## Sum of exponentially decaying sine partials: bells, plates, pipes, struck metal.
static func _modal(freqs: Array, decays: Array, amps: Array, dur: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for k in freqs.size():
		var w: float = TAU * freqs[k] / RATE
		var d: float = decays[k]
		var amp: float = amps[k]
		for i in n:
			out[i] += sin(w * i) * amp * exp(-d * float(i) / RATE)
	for i in mini(n, 40):
		out[i] *= i / 40.0
	return out


static func _add(a: PackedFloat32Array, b: PackedFloat32Array, gain_b := 1.0) -> PackedFloat32Array:
	var n := maxi(a.size(), b.size())
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = (a[i] if i < a.size() else 0.0) + (b[i] * gain_b if i < b.size() else 0.0)
	return out


static func _shift(a: PackedFloat32Array, secs: float) -> PackedFloat32Array:
	var pad := PackedFloat32Array()
	pad.resize(int(secs * RATE))
	pad.append_array(a)
	return pad


## Crunchy grains (sand, snow, gravel): sparse random clicks.
static func _grains(dur: float, count: int, decay_frac: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for g in count:
		var at := int(pow(_r.randf(), 1.6) * n * decay_frac + _r.randf() * n * (1.0 - decay_frac) * 0.3)
		var amp := _r.randf_range(0.2, 0.7) * (1.0 - float(at) / n)
		for j in 30:
			if at + j < n:
				out[at + j] += _r.randf_range(-1.0, 1.0) * amp * exp(-j / 6.0)
	return out


static func _rattle(dur: float, rate: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var next := 0
	while next < n:
		var f := _r.randf_range(900.0, 2600.0)
		var amp := _r.randf_range(0.1, 0.35)
		for j in int(0.03 * RATE):
			if next + j < n:
				out[next + j] += sin(TAU * f * j / RATE) * amp * exp(-j / 90.0)
		next += int(RATE / rate * _r.randf_range(0.5, 1.5))
	return out


static func _loop_noise(n: int, smooth: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	var last := 0.0
	for i in n:
		last = lerpf(_r.randf_range(-1.0, 1.0), last, smooth)
		out[i] = last
	# Crossfade the tail into the head so the loop has no seam.
	var fade := mini(2000, n / 4)
	for i in fade:
		var t := float(i) / fade
		out[i] = out[i] * t + out[n - fade + i] * (1.0 - t)
	return out


# --- ambience beds (whole-cycle frequencies, seamless) ------------------------------------

static func _amb_lab(dur: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var vent := _lp(_lp(_loop_noise(n, 0.0), 500.0), 500.0)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var buzz := 0.08 * signf(sin(TAU * 120.0 * t)) + 0.05 * sin(TAU * 240.0 * t) + 0.03 * sin(TAU * 360.0 * t)
		out[i] = buzz * 0.6 * (0.85 + 0.15 * sin(TAU * 0.25 * t)) + vent[i] * 0.6
	for at in [1.3, 1.45, 5.2]:   # equipment beeps
		var b := _tone(2200.0, 0.06, 0.0, false)
		for j in b.size():
			out[int(at * RATE) + j] += b[j] * 0.15
	return out


static func _amb_backrooms(dur: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var flick := 1.0 if fmod(t, 4.0) < 3.82 else 0.4
		out[i] = (0.14 * signf(sin(TAU * 120.0 * t)) * 0.6 + 0.1 * sin(TAU * 60.0 * t) + 0.06 * sin(TAU * 180.0 * t)) * flick
	return _lp(out, 3000.0)


static func _amb_yard(dur: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var wind := _lp(_lp(_loop_noise(n, 0.0), 260.0), 260.0)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		out[i] = wind[i] * 1.6 * (0.65 + 0.35 * sin(TAU * t / 4.0)) + 0.06 * sin(TAU * 50.0 * t)
	var c := _lp(_modal([180.0, 470.0, 820.0], [3.0, 4.0, 6.0], [0.2, 0.15, 0.1], 1.5), 900.0)
	for j in c.size():
		out[int(3.0 * RATE) + j] += c[j]
	return out


## Diesel engine: uneven firing pulses over a low fundamental. Pitch it with speed.
## A diesel under load, as recorded off a railcar: nearly all of it below 150 Hz, the firing
## pulse at 39 Hz with its 78 Hz double strongest, the block's rumble, a faint mechanical
## clatter riding the pulses. Whole cycles, so it loops.
static func _diesel(dur: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var rumble := _lp(_lp(_loop_noise(n, 0.0), 160.0), 160.0)
	var clatter := _bp(_loop_noise(n, 0.0), 1500.0, 4000.0)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var ph := fmod(t * 39.0, 1.0)
		var pulse := exp(-ph * 9.0)                                   # each cylinder firing
		var uneven := 1.0 + 0.18 * sin(TAU * 6.5 * t)                 # (not every cylinder the same)
		out[i] = (0.42 * sin(TAU * 78.0 * t) + 0.3 * sin(TAU * 39.0 * t) + 0.12 * sin(TAU * 117.0 * t)) * (0.55 + 0.45 * pulse * uneven) \
			+ rumble[i] * 3.0 * (0.5 + pulse) + clatter[i] * 0.08 * pulse
	return _lp(out, 900.0)


# --- distant events ------------------------------------------------------------------------

## lub-dub every `period` seconds.
## Lub-dub, as a chest sounds: the first heavier and lower (about 105 Hz), the second shorter and
## higher (about 135), each a thump that sags in pitch, with a little flutter of the valves.
static func _heartbeat(dur: float, period: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var beats := int(round(dur / period))
	for b in beats:
		for hit in 2:
			var at := int((b * period + hit * period * 0.3) * RATE)
			var amp := 0.85 if hit == 0 else 0.55
			var f0 := 105.0 if hit == 0 else 138.0
			for j in int(0.16 * RATE):
				if at + j < n:
					var t := float(j) / RATE
					var f := f0 * (1.0 - 0.35 * t / 0.16)
					out[at + j] += (sin(TAU * f * t) + 0.25 * sin(TAU * f * 2.1 * t) * exp(-t * 60.0)) * amp * exp(-t * (24.0 if hit == 0 else 32.0)) * clampf(t / 0.006, 0.0, 1.0)
	return _lp(_lp(out, 600.0), 600.0)


static func _searchlight(dur: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		out[i] = 0.15 * sin(TAU * 100.0 * t) + 0.07 * signf(sin(TAU * 200.0 * t)) + 0.04 * sin(TAU * 3000.0 * t) * (0.5 + 0.5 * sin(TAU * 2.0 * t))
	return _lp(out, 4000.0)


static func _buzz_tone(dur: float, f: float) -> PackedFloat32Array:
	# Mains hum: a clipped fundamental with odd harmonics (whole cycles, so it loops).
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		out[i] = clampf(1.6 * sin(TAU * f * t), -1.0, 1.0) * 0.25 + 0.08 * sin(TAU * f * 3.0 * t)
	return out


## A big explosion a kilometre off, built the way they're recorded and designed: what reaches you is
## mostly the low end (the air has eaten the highs and the crack has gone to a dull thud), a sub
## drop with the weight, the body of the blast, then the rumble rolling round the hills: swelling
## and falling away again and again but never in distinct hits (copies of the blast came out as a
## string of bongs), with the debris crackling through it.
static func _explosion_far() -> PackedFloat32Array:
	var dur := 10.0
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var body := _lp(_noise(dur, 0.0, 0.0), 260.0)
	var crack := _lp(_noise(dur, 0.0, 0.0), 1700.0)
	var roll := _lp(_lp(_noise(dur, 0.0, 0.0), 140.0), 140.0)
	var deb := _lp(_grains(dur, 420, 0.5), 2200.0)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		ph += TAU * lerpf(52.0, 24.0, minf(1.0, t / 1.2)) / RATE
		var att := minf(1.0, i / 90.0)
		var blast := crack[i] * exp(-t * 26.0) * 1.6 + body[i] * exp(-t * 2.4) * 3.2 + sin(ph) * exp(-t * 2.0) * 1.1
		var swell := 0.0   # the rumble rolling round the country, in soft overlapping swells
		for e in [[0.9, 0.7, 1.0], [2.0, 0.9, 0.75], [3.4, 1.2, 0.5], [5.2, 1.6, 0.3]]:
			swell += e[2] * exp(-pow((t - e[0]) / e[1], 2.0))
		var bed := minf(1.0, t / 0.4) * exp(-t * 0.3)
		out[i] = att * blast + roll[i] * (2.2 * bed + 3.5 * swell) + deb[i] * smoothstep(0.6, 1.5, t) * exp(-t * 0.35) * 0.6
	for i in n:   # driven a little into saturation for weight, faded out at the end
		out[i] = tanh(out[i] * 1.4) * minf(1.0, (n - i) / float(RATE))
	return out


## Big two-stroke diesel at idle: uneven firing thumps at 34 Hz with their harmonics, block rattle,
## a faint turbo whine and the cam tick. Whole cycles, so it loops; pitch it up for revs.
## The locomotive's engine, after how big road diesels sound: a four-stroke V12 (as GE's), each
## cylinder firing every second turn, so at idle (400 rpm) a 40 Hz chug you can almost count, and
## opened out to run 8 (1050 rpm) still only about 105 Hz: deep however hard it works, never a whine.
## The cylinders aren't alike and the two banks fire in pairs, so the beat is uneven, chesty, with a
## lurch every working cycle (two turns). Each pulse booms the exhaust stack (metres of steel: low and
## long) with a chuff of gas and the block thumping under it. Whole cycles, wrapped round: a seamless
## loop. train.gd crossfades three of these by rpm, pitching each only a little.
static func _prime_mover(rpm: float, load: float) -> PackedFloat32Array:
	var cycle := rpm / 120.0   # working cycles a second (two turns each)
	var cyl := 12
	var cycles := maxi(2, int(round(2.8 * cycle)))
	var dur := cycles / cycle
	var n := int(dur * RATE)
	var r := RandomNumberGenerator.new()
	r.seed = int(rpm)
	var gains := PackedFloat32Array()   # each cylinder its own strength, and the firing order's unevenness
	var offs := PackedFloat32Array()
	for k in cyl:
		gains.append(r.randf_range(0.5, 1.0) * (1.0 if k % 2 == 0 else 0.82))
		offs.append(r.randf_range(-0.12, 0.12) + (0.18 if k % 2 == 1 else 0.0))   # (the banks fire in pairs, close together)
	var klen := int(RATE * 0.22)
	var kern := PackedFloat32Array()
	kern.resize(klen)
	var stack := lerpf(38.0, 52.0, load)
	var chuff := _lp(_lp(_noise(0.22, 0.0, 0.0), lerpf(380.0, 900.0, load)), lerpf(380.0, 900.0, load))
	for i in klen:
		var t := float(i) / RATE
		kern[i] = sin(TAU * stack * t) * exp(-t * lerpf(12.0, 18.0, load)) \
			+ 0.55 * sin(TAU * stack * 1.98 * t + 0.6) * exp(-t * 24.0) \
			+ 0.3 * sin(TAU * stack * 3.05 * t + 1.3) * exp(-t * 34.0) \
			+ 0.5 * sin(TAU * 24.0 * t) * exp(-t * 9.0) \
			+ chuff[i] * exp(-t * lerpf(30.0, 45.0, load)) * lerpf(2.4, 3.4, load)
		kern[i] *= minf(1.0, t / 0.003) * (1.0 - smoothstep(0.6, 1.0, float(i) / klen))   # (no step in or out: each was a click)
	var out := PackedFloat32Array()
	out.resize(n)
	var clatter := PackedFloat32Array()
	clatter.resize(n)
	var gap := 1.0 / (cycle * cyl)   # seconds between firings
	for c in cycles:
		var lurch := r.randf_range(0.85, 1.0)
		for k in cyl:
			var at := int(((c * cyl + k) + offs[k]) * gap * RATE)
			var a: float = gains[k] * lurch * r.randf_range(1.0 - lerpf(0.3, 0.1, load), 1.0)
			for i in klen:
				out[posmod(at + i, n)] += kern[i] * a
			for i in 24:
				clatter[posmod(at + i, n)] += r.randf_range(-1.0, 1.0) * exp(-i / 5.0) * a
	var block := _lp(_lp(_loop_noise(n, 0.0), 40.0, true), 40.0, true)
	clatter = _bp(clatter, 1500.0, 4500.0, true)
	for i in n:
		out[i] = out[i] + block[i] * 10.0 + clatter[i] * 0.02
	return _lp(out, lerpf(1200.0, 2200.0, load), true)


static func _diesel_idle(dur: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var f := 34.0
	var cycles := int(f * dur)
	var amps := PackedFloat32Array()
	for c in cycles:
		amps.append(rng.randf_range(0.7, 1.0))
	var rattle := _loop_noise(n, 0.4)
	for i in n:
		var t := float(i) / RATE
		var cyc := int(t * f) % cycles
		var within := fmod(t * f, 1.0)
		var thump := exp(-within * 6.0) * amps[cyc]
		out[i] = (sin(TAU * f * t) * 0.5 + sin(TAU * f * 2.0 * t) * 0.3 + sin(TAU * f * 3.0 * t) * 0.15) * (0.4 + thump * 0.6)
		out[i] += rattle[i] * 0.18 * thump
		out[i] += sin(TAU * 1250.0 * t) * 0.012 * (1.0 + 0.3 * sin(TAU * 0.5 * t))   # turbo
		var tick := fmod(t * 4.0, 1.0)
		out[i] += sin(TAU * 2900.0 * t) * exp(-tick * 160.0) * 0.06   # valve gear
	return _lp(out, 1800.0)


## A lever's ratchet: a pawl clicking over the teeth as it's thrown.
static func _ratchet(dur: float, clicks: int) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for c in clicks:
		var at := int(pow(float(c) / clicks, 0.8) * n * 0.9)
		var click := _modal([2300.0, 3700.0, 5200.0], [90.0, 120.0, 160.0], [0.5, 0.3, 0.15], 0.05)
		for j in click.size():
			if at + j < n:
				out[at + j] += click[j]
	return out


## One footstep on `kind`: the heel strike, then the toe (or a scuff) 70-110 ms later.
static func _step(kind: String) -> PackedFloat32Array:
	var r := _r.randf_range(0.9, 1.1)
	var toe_at := _r.randf_range(0.07, 0.11)
	var heel: PackedFloat32Array
	var toe: PackedFloat32Array
	match kind:
		"concrete":   # a dull thump and grit
			heel = _add(_add(_lp(_noise(0.05, 70.0, 0.2), 3200.0), _tone(92.0 * r, 0.07, 48.0), 0.9), _hp(_grains(0.07, 30, 0.8), 2500.0), 0.35)
			toe = _add(_lp(_noise(0.06, 55.0, 0.1), 4500.0), _hp(_grains(0.05, 20, 0.8), 3000.0), 0.3)
		"tiles":   # a hard click, a little ring
			heel = _add(_add(_hp(_noise(0.025, 140.0, 0.0), 1600.0), _modal([2400.0 * r, 3650.0 * r], [90.0, 120.0], [0.35, 0.2], 0.06), 1.0), _tone(130.0 * r, 0.05, 60.0), 0.6)
			toe = _hp(_noise(0.03, 120.0, 0.0), 2000.0)
		"metal":   # a plate rings, a grate rattles
			heel = _add(_modal([380.0 * r, 1010.0 * r, 1720.0 * r, 2690.0 * r], [24.0, 30.0, 38.0, 50.0], [0.5, 0.35, 0.25, 0.15], 0.4), _hp(_noise(0.02, 140.0, 0.0), 2500.0), 0.6)
			heel = _add(heel, _bp(_rattle(0.15, 70.0), 600.0, 3000.0), 0.25)
			toe = _modal([395.0 * r, 1050.0 * r, 1800.0 * r], [30.0, 36.0, 44.0], [0.35, 0.25, 0.15], 0.25)
		"wood":   # a hollow knock off the boards
			heel = _add(_modal([115.0 * r, 300.0 * r, 640.0 * r, 1150.0 * r], [28.0, 35.0, 48.0, 60.0], [0.7, 0.35, 0.2, 0.1], 0.22), _lp(_noise(0.03, 90.0, 0.3), 2200.0), 0.4)
			toe = _modal([125.0 * r, 330.0 * r, 700.0 * r], [34.0, 42.0, 55.0], [0.4, 0.2, 0.1], 0.15)
			if _r.randf() < 0.35:   # a board gives under you
				toe = _add(toe, _shift(_creak(0.18), 0.02), 0.12)
		"sand":   # soft crunch, sliding grains
			heel = _lp(_add(_grains(0.13, 260, 0.6), _lp(_noise(0.08, 40.0, 0.6), 400.0), 0.5), 3400.0)
			toe = _lp(_grains(0.11, 180, 0.7), 3800.0)
		"snow":   # a compressed squeaky crunch
			heel = _add(_hp(_lp(_grains(0.15, 420, 0.5), 5500.0), 900.0), _tone(110.0 * r, 0.06, 40.0), 0.4)
			toe = _hp(_lp(_grains(0.12, 320, 0.6), 6000.0), 1100.0)
		"mud":   # a wet suck going in, a smack, the boot pulling out
			heel = _add(_lp(_noise(0.12, 22.0, 0.7), 650.0), _sweep(190.0 * r, 80.0, 0.14, 12.0), 0.55)
			heel = _add(heel, _hp(_grains(0.08, 40, 0.7), 1800.0), 0.15)
			toe = _add(_sweep(120.0 * r, 340.0 * r, 0.12, 16.0), _lp(_noise(0.1, 30.0, 0.6), 900.0), 0.4)
		"grass":   # leaf litter and twigs: a soft dry rustle, now and then a stick snapping
			heel = _add(_bp(_grains(0.14, 300, 0.6), 900.0, 5200.0), _lp(_noise(0.07, 45.0, 0.5), 500.0), 0.5)
			toe = _bp(_grains(0.12, 220, 0.7), 1200.0, 6000.0)
			if _r.randf() < 0.2:
				toe = _add(toe, _hp(_noise(0.012, 300.0, 0.0), 1500.0), 0.5)
		"carpet":
			heel = _add(_lp(_noise(0.08, 40.0, 0.6), 700.0), _tone(75.0 * r, 0.07, 40.0), 0.6)
			toe = _lp(_noise(0.07, 45.0, 0.5), 900.0)
	return _add(heel, _shift(toe, toe_at), _r.randf_range(0.45, 0.65))


## A steel bar or pipe struck: the partials of a free bar (1 : 2.76 : 5.40 : 8.93), the low hum
## of the structure it's on ringing on, the contact click.
## An oscillator: frequency and loudness given per moment (seconds); "sine", "saw" or "square".
static func _osc(dur: float, freq: Callable, amp: Callable, shape := "sine") -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		ph = fmod(ph + float(freq.call(t)) / RATE, 1.0)
		var v: float
		match shape:
			"saw": v = ph * 2.0 - 1.0
			"square": v = 1.0 if ph < 0.5 else -1.0
			_: v = sin(TAU * ph)
		out[i] = v * float(amp.call(t)) * _env(i, n)
	return out


## A rubber duck squeezed: a nasal two-part squeak (air forced through the reed in its base).
static func _squeak() -> PackedFloat32Array:
	var tone := _osc(0.32, func(t): return 1050.0 + 650.0 * sin(PI * clampf(t / 0.3, 0.0, 1.0)) + 40.0 * sin(TAU * 31.0 * t),
		func(t): return 0.5 * clampf(t / 0.02, 0.0, 1.0) * clampf((0.32 - t) / 0.06, 0.0, 1.0), "saw")
	return _add(_bp(tone, 700.0, 3600.0), _hp(_noise(0.32, 6.0, 0.3), 2500.0), 0.12)


## Jingle bells shaken: little bells struck at odd moments, each a few bright partials.
static func _jingle() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(0.9 * RATE))
	for k in 9:
		var f := _r.randf_range(2300.0, 3300.0)
		var b := _modal([f, f * 1.48, f * 2.1], [11.0, 15.0, 22.0], [0.5, 0.3, 0.18], 0.5)
		out = _add(out, _shift(b, _r.randf_range(0.0, 0.4)), 0.55)
	return out


## An old telephone bell: the clapper hammering two gongs twenty times a second, twice.
static func _phone_ring() -> PackedFloat32Array:
	var ring := _osc(1.6, func(t): return 1040.0, func(t): return (0.45 if fmod(t, 0.05) < 0.03 else 0.12) * (1.0 if t < 0.6 or (t > 0.9 and t < 1.5) else 0.0))
	return _add(ring, _osc(1.6, func(t): return 1470.0, func(t): return (0.3 if fmod(t + 0.025, 0.05) < 0.03 else 0.08) * (1.0 if t < 0.6 or (t > 0.9 and t < 1.5) else 0.0)), 1.0)


## A reversing alarm, after a recording of one: an almost pure tone at 1263 Hz, a faint second
## harmonic, on for a third of a second every 0.57 s, the edges softened. Two beeps (it repeats).
static func _reverse_beep() -> PackedFloat32Array:
	return _osc(1.14, func(t): return 1263.0, func(t): return 0.42 * clampf(fmod(t, 0.57) / 0.012, 0.0, 1.0) * clampf((0.33 - fmod(t, 0.57)) / 0.012, 0.0, 1.0) * (1.0 + 0.08 * sin(TAU * 2526.0 * t)))


## A wind-up tin robot: the spring ratcheting, then a few bleeps.
static func _robot() -> PackedFloat32Array:
	var out := _ratchet(0.5, 9)
	for k in 5:
		var f := _r.randf_range(600.0, 1700.0)
		out = _add(out, _shift(_osc(0.08, func(t): return f, func(t): return 0.3, "square"), 0.5 + k * 0.11), 0.6)
	return out

