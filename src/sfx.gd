# Every sound is synthesized at runtime, so the project ships with zero audio files.
# Filters + modal synthesis (stacks of decaying partials) for metal; 3D sounds go through a
# "World" bus whose reverb follows where you are (set_space): a big hall underground, a small
# box in the train, almost dry outside.
extends RefCounted

const RATE := 22050
const LOOPS := ["drone", "motor", "chug", "muzak", "wind", "grind", "rumble",
	"diesel", "amb_factory", "amb_lab", "amb_flesh", "amb_backrooms", "amb_yard",
	"servo", "heartbeat", "searchlight", "drip_loop", "rattle", "chime", "steam", "buzz", "flare", "diesel_idle", "compressor", "lens_tick", "whisper", "breath", "heart", "shred_motor", "conveyor", "rain", "rain_roof", "flicker_buzz"]
const STEPS := ["concrete", "metal", "wood", "sand", "snow", "flesh", "carpet", "tiles", "water"]
static var _cache := {}
static var net_hook: Callable   # net.gd: decides whether a sound plays here and passes it on
static var _reverb: AudioEffectReverb
static var _take := 0
static var _r := RandomNumberGenerator.new()
static var _lock := Mutex.new()
static var _warming := false
## Everything _make() knows (warm() makes them all ahead).
const ALL := ["beep", "ding", "pickup", "error", "key", "click", "step", "hurt", "boom", "door", "alarm", "horn", "diesel_idle", "compressor", "air_release", "scan", "blip", "screech", "drone", "creak", "grind", "rumble", "roar", "growl", "shriek", "thud", "snap", "slurp", "chitter", "clack", "hiss", "flash", "wind", "rain", "rain_roof", "thunder", "stamp", "flicker_buzz", "motor", "chug", "muzak", "step_concrete", "step_tiles", "step_metal", "step_wood", "step_sand", "step_snow", "step_flesh", "step_carpet", "land", "clank", "clang_big", "thunk", "rustle", "slide", "clunk", "open_box", "heavy_lift", "amb_factory", "amb_lab", "amb_flesh", "amb_backrooms", "amb_yard", "diesel", "rail_clack", "far_bang", "groan", "drip", "pipe_knock", "far_screech", "far_steps", "servo", "heartbeat", "searchlight", "drip_loop", "rattle", "chime", "step_water", "power_down", "power_up", "zap", "crackle", "buzz", "steam", "steam_burst", "cough", "quake", "debris", "plane", "flare", "shutter", "flash_whine", "flashbulb", "tinnitus", "lens_tick", "whisper", "wraith_shriek", "wraith_grab", "dissolve", "swish", "shotgun", "dry_fire", "breath", "heart", "gurgle", "alarm_bell", "bulkhead", "crack_glass", "klaxon", "door_open", "door_shut", "breaker", "shred_motor", "shred_metal", "shred_soft", "shred_jam", "ratchet", "conveyor"]
## Sounds that come in several takes (so ten footsteps in a row aren't ten copies of one).
const TAKES := 4
static func _has_takes(sound: String) -> bool:
	return sound.begins_with("step_") or sound in ["thunk", "clank", "door_shut", "drip"]


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
	AudioServer.add_bus_effect(AudioServer.get_bus_index("World"), _reverb)
	var amb_rev := AudioEffectReverb.new()
	amb_rev.room_size = 0.9
	amb_rev.wet = 0.25
	AudioServer.add_bus_effect(AudioServer.get_bus_index("Ambience"), amb_rev)
	set_space("outside")
	for n in STEPS:   # generate up front so nothing hitches the first time it plays (every take)
		for k in TAKES:
			stream("step_%s#%d" % [n, k])
	for n in ["land", "clank", "thunk", "rustle", "amb_factory", "amb_lab", "amb_flesh", "amb_backrooms", "amb_yard", "diesel", "rail_clack", "wind"]:
		stream(n)
	warm()   # (the rest on a worker thread)


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


static func stream(sound: String) -> AudioStreamWAV:
	if _has_takes(sound) and not "#" in sound:
		_take += 1
		sound = "%s#%d" % [sound, _take % TAKES]
	_lock.lock()   # (warm() may be making sounds on another thread)
	if not _cache.has(sound):
		_r.seed = hash(sound)   # synthesis has its own dice (each take its own), the same on every machine
		_cache[sound] = _make(sound)
	var w: AudioStreamWAV = _cache[sound]
	_lock.unlock()
	return w


## Every sound made ahead, on a worker thread, so none is synthesised the moment it first plays
## (that took tens of milliseconds a sound: a hitch on the first door slam, the first roar...).
static func warm() -> void:
	if _warming:
		return
	_warming = true
	WorkerThreadPool.add_task(_warm_all, false, "sfx warm")


static func _warm_all() -> void:
	for name: String in ALL + STEPS.map(func(k): return "step_" + k):
		if _has_takes(name):
			for t in TAKES:
				stream("%s#%d" % [name, t])
		else:
			stream(name)


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
		"alarm": s = _klaxon(1.6)   # (the old square-wave siren was shrill)
		"horn": s = _horn()
		"diesel_idle": s = _diesel_idle(2.0)
		"compressor": s = _compressor(1.0)
		"air_release": s = _add(_hp(_noise(1.4, 2.2, 0.15), 900.0), _lp(_noise(0.3, 12.0, 0.7), 500.0), 0.6)
		"scan": s = _add(_add(_sweep(220.0, 1500.0, 0.5, 3.5), _lp(_noise(0.9, 3.0, 0.9), 900.0), 0.5), _shift(_modal([1760.0, 2637.0, 3520.0], [5.0, 6.0, 8.0], [0.3, 0.2, 0.1], 1.4), 0.12), 0.8)
		"blip": s = _add(_tone(1320.0, 0.18, 22.0), _shift(_tone(1980.0, 0.12, 30.0), 0.035), 0.5)
		"screech": s = _mix(_sweep(900.0, 2600.0, 0.6, 3.0), _noise(0.6, 4.0, 0.3))
		"drone": s = _drone(6.0)
		"creak": s = _creak(0.7)
		"grind": s = _grind(2.0)
		"rumble": s = _rumble(4.0)
		"roar": s = _add(_voice(2.2, 115.0, 0.35, 24.0, [420.0, 1000.0, 2300.0], 0.2), _lp(_sweep(120.0, 55.0, 2.2, 0.8), 300.0), 0.5)
		"growl": s = _voice(1.4, 135.0, 0.1, 30.0, [460.0, 1100.0, 2400.0], 0.15)
		"shriek": s = _voice(0.8, 680.0, -0.15, 45.0, [1150.0, 2250.0, 3400.0], 0.3)
		"thud": s = _mix(_tone(55.0, 0.35, 9.0), _noise(0.3, 14.0, 0.95))
		"snap": s = _mix(_noise(0.15, 30.0, 0.2), _tone(900.0, 0.12, 30.0, true))
		"slurp": s = _sweep(300.0, 90.0, 0.6, 3.0)
		"chitter": s = _chitter(0.5)
		"clack": s = _mix(_tone(1200.0, 0.04, 80.0, true), _noise(0.04, 90.0, 0.3))
		"hiss": s = _noise(0.8, 3.0, 0.1)
		"flash": s = _sweep(2400.0, 5200.0, 0.25, 8.0)
		"wind": s = _wind(6.0)
		"rain": s = _rain(5.0, false)
		"rain_roof": s = _rain(5.0, true)
		"thunder": s = _thunder(6.5)
		"stamp": s = _stamp()
		"flicker_buzz": s = _flicker_buzz(3.0)
		"motor": s = _motor(4.0)
		"chug": s = _chug(1.0)
		"muzak": s = _muzak()
		# --- footsteps by surface ---
		"step_concrete", "step_tiles", "step_metal", "step_wood", "step_sand", "step_snow":
			s = _step(sound.trim_prefix("step_"))
		"step_flesh": s = _add(_lp(_noise(0.2, 14.0, 0.7), 900.0), _sweep(320.0, 90.0, 0.2, 10.0), 0.6)
		"step_carpet": s = _step("carpet")
		"land": s = _add(_tone(70.0, 0.25, 16.0), _lp(_noise(0.2, 20.0, 0.5), 1400.0), 1.0)
		# --- objects ---
		"clank": s = _clank()
		"clang_big": s = _modal([110.0, 287.0, 523.0, 861.0, 1307.0], [2.5, 3.5, 4.5, 6.0, 8.0], [0.6, 0.5, 0.35, 0.25, 0.15], 2.8)
		"thunk": s = _thunk()
		"rustle": s = _bp(_noise(0.22, 12.0, 0.2), 900.0, 4500.0)
		"slide": s = _add(_bp(_noise(1.1, 0.8, 0.6), 200.0, 1800.0), _rattle(1.1, 24.0), 0.6)
		"clunk": s = _add(_modal([90.0, 240.0, 470.0], [6.0, 9.0, 14.0], [0.6, 0.4, 0.25], 0.8), _lp(_noise(0.3, 18.0, 0.6), 800.0), 1.0)
		"open_box": s = _add(_creak(0.45), _modal([260.0, 640.0], [18.0, 24.0], [0.3, 0.2], 0.3), 0.6)
		"heavy_lift": s = _add(_lp(_noise(0.5, 4.0, 0.85), 600.0), _sweep(140.0, 90.0, 0.5, 4.0), 0.7)
		# --- ambience beds (loops) ---
		"amb_factory": s = _amb_factory(8.0)
		"amb_lab": s = _amb_lab(8.0)
		"amb_flesh": s = _amb_flesh(8.0)
		"amb_backrooms": s = _amb_backrooms(8.0)
		"amb_yard": s = _amb_yard(8.0)
		"diesel": s = _diesel(2.0)
		"rail_clack": s = _add(_modal([620.0, 1550.0], [30.0, 40.0], [0.5, 0.3], 0.18), _shift(_modal([600.0, 1500.0], [30.0, 40.0], [0.4, 0.25], 0.18), 0.09), 1.0)
		# --- distant one-shots for underground ---
		"far_bang": s = _lp(_modal([95.0, 230.0, 410.0, 690.0], [1.5, 2.2, 3.0, 4.5], [0.6, 0.45, 0.3, 0.2], 3.0), 1600.0)
		"groan": s = _groan(3.0)
		"drip": s = _drip()
		"pipe_knock": s = _knocks(1.4)
		"far_screech": s = _lp(_mix(_sweep(700.0, 1900.0, 1.2, 1.5), _noise(1.2, 2.5, 0.4)), 1800.0)
		"far_steps": s = _far_steps(2.4)
		# --- creature loops ---
		"servo": s = _servo(2.0)
		"heartbeat": s = _heartbeat(2.0, 0.5)
		"searchlight": s = _searchlight(2.0)
		"drip_loop": s = _drip_loop(4.0)
		"rattle": s = _rattle(2.0, 9.0)
		"chime": s = _chime(4.0)
		# --- hazards and events ---
		"step_water": s = _add(_lp(_noise(0.32, 9.0, 0.55), 1500.0), _sweep(260.0, 700.0, 0.18, 14.0), 0.35)
		"power_down": s = _add(_sweep(240.0, 28.0, 2.2, 1.2), _modal([90.0, 240.0, 470.0], [6.0, 9.0, 14.0], [0.6, 0.4, 0.25], 1.0), 0.8)
		"power_up": s = _add(_shift(_sweep(30.0, 120.0, 2.0, 0.3), 0.25), _modal([90.0, 240.0, 470.0], [6.0, 9.0, 14.0], [0.6, 0.4, 0.25], 0.8), 1.0)
		"zap": s = _add(_hp(_grains(0.45, 220, 0.4), 1500.0), _buzz_tone(0.45, 120.0), 0.7)
		"crackle": s = _hp(_grains(0.7, 90, 0.9), 2200.0)
		"buzz": s = _buzz_tone(2.0, 60.0)
		"steam": s = _steam(2.0)
		"steam_burst": s = _add(_hp(_noise(2.4, 0.5, 0.15), 900.0), _lp(_noise(0.4, 8.0, 0.8), 400.0), 1.2)
		"cough": s = _cough()
		"quake": s = _add(_lp(_noise(4.5, 0.4, 0.993), 220.0), _shift(_groan(3.0), 0.6), 0.35)
		"debris": s = _add(_lp(_noise(0.6, 7.0, 0.85), 900.0), _modal([140.0, 330.0, 610.0], [9.0, 13.0, 18.0], [0.5, 0.3, 0.2], 0.6), 0.9)
		"plane": s = _plane(7.0)
		"flare": s = _hp(_loop_noise(int(2.0 * RATE), 0.3), 1400.0)
		# Observer: a leaf shutter (cock, release, spring), a flash capacitor whining up, the bulb going off.
		"shutter": s = _add(_add(_hp(_noise(0.02, 160.0, 0.0), 2500.0), _modal([2900.0, 4100.0, 6100.0], [70.0, 90.0, 120.0], [0.4, 0.3, 0.15], 0.06)), _shift(_add(_hp(_noise(0.03, 110.0, 0.1), 1800.0), _modal([1700.0, 3300.0], [55.0, 70.0], [0.45, 0.2], 0.09)), 0.075), 0.9)
		"flash_whine": s = _add(_sweep(700.0, 7400.0, 0.7, 0.0), _hp(_noise(0.7, 0.0, 0.2), 4000.0), 0.08)
		"flashbulb": s = _add(_add(_lp(_noise(0.5, 12.0, 0.4), 3000.0), _hp(_noise(0.7, 5.0, 0.0), 5000.0), 0.5), _tone(70.0, 0.25, 14.0), 0.9)
		"tinnitus": s = _tinnitus(5.0)
		"lens_tick": s = _lens_tick(3.0)
		# Wraith: a crowd of whispers, a shriek when the light burns it, a cold hiss when it takes hold.
		"whisper": s = _whisper(6.0)
		"wraith_shriek": s = _add(_add(_bp(_noise(1.3, 2.2, 0.2), 1400.0, 6000.0), _sweep(1500.0, 520.0, 1.3, 1.6), 0.7), _shift(_sweep(2300.0, 900.0, 0.9, 2.5), 0.12), 0.4)
		"wraith_grab": s = _add(_bp(_noise(1.4, 2.0, 0.5), 300.0, 2600.0), _sweep(220.0, 70.0, 1.4, 1.5), 0.8)
		"dissolve": s = _add(_hp(_noise(1.6, 1.8, 0.3), 1200.0), _sweep(900.0, 120.0, 1.6, 1.2), 0.5)
		# Weapons: a swing through the air, a shotgun blast with its tail rolling off the walls.
		"swish": s = _bp(_noise(0.32, 9.0, 0.3), 500.0, 3200.0)
		"shotgun": s = _add(_add(_lp(_noise(1.2, 4.0, 0.6), 2200.0), _hp(_noise(0.12, 40.0, 0.0), 2500.0), 0.8), _tone(52.0, 0.3, 10.0), 1.0)
		"dry_fire": s = _add(_modal([2400.0, 3900.0], [90.0, 120.0], [0.4, 0.25], 0.06), _hp(_noise(0.02, 200.0, 0.0), 3000.0), 0.6)
		# Inside your helmet: breathing and your own heartbeat (pitch them up to speed them up).
		"breath": s = _breath(4.0)
		"heart": s = _heartbeat(1.0, 1.0)
		"gurgle": s = _gurgle(1.1)
		"alarm_bell": s = _alarm_bell(0.4)
		"bulkhead": s = _bulkhead(1.5)
		"crack_glass": s = _crack_glass()
		"klaxon": s = _klaxon(1.8)
		"door_open": s = _add(_latch(), _shift(_hinge(0.5, 1.0), 0.05), 0.8)
		"door_shut": s = _add(_hinge(0.3, 0.8), _shift(_slam(), 0.26), 1.0)
		"breaker": s = _add(_modal([70.0, 190.0, 430.0, 900.0], [5.0, 8.0, 12.0, 20.0], [0.7, 0.5, 0.3, 0.2], 1.0), _hp(_noise(0.05, 80.0, 0.0), 2500.0), 0.8)
		"shred_motor": s = _shred_motor(2.0)
		"shred_metal": s = _shred_chew(1.3, true)
		"shred_soft": s = _shred_chew(1.1, false)
		"shred_jam": s = _shred_jam()
		"ratchet": s = _ratchet(0.32, 7)
		"conveyor": s = _conveyor(2.0)
		_: s = _tone(440.0, 0.1, 10.0)
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


static func _drone(dur: float) -> PackedFloat32Array:
	# Frequencies chosen to complete whole cycles so the loop is seamless.
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var last := 0.0
	for i in n:
		var t := float(i) / RATE
		last = lerpf(_r.randf_range(-1.0, 1.0), last, 0.995)
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
		last = lerpf(_r.randf_range(-1.0, 1.0), last, 0.9)
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


static func _grind(dur: float) -> PackedFloat32Array:
	# Stone dragging on stone: rough low noise with a scraping wobble. Loops.
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var last := 0.0
	for i in n:
		var t := float(i) / RATE
		last = lerpf(_r.randf_range(-1.0, 1.0), last, 0.8)
		out[i] = last * 0.9 * (0.6 + 0.4 * sin(TAU * 3.0 * t)) * (0.7 + 0.3 * sin(TAU * 0.5 * t))
	return out


## Rain: a hiss of countless drops (filtered noise) and the nearer ones as ticks; on a roof (inside
## the train) duller and drummier. Looped without a seam (the end crossfades into the start).
static func _rain(dur: float, roof: bool) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var fade := int(0.4 * RATE)
	var out := PackedFloat32Array()
	out.resize(n + fade)
	var lo := 0.0
	var hi := 0.0
	for i in n + fade:
		var w := _r.randf_range(-1.0, 1.0)
		lo += (w - lo) * (0.08 if roof else 0.35)
		hi += (lo - hi) * 0.02
		out[i] = (lo - hi) * (0.55 if roof else 0.35)
	for g in int(dur * (220 if roof else 380)):   # drops near enough to hear one by one
		var at := _r.randi() % (n + fade)
		var amp := _r.randf_range(0.05, 0.3) * (1.6 if roof else 1.0)
		var dl := 90 if roof else 30
		var f := _r.randf_range(900.0, 2600.0) if not roof else _r.randf_range(180.0, 420.0)
		for j in dl:
			if at + j < n + fade:
				out[at + j] += sin(TAU * f * j / RATE) * amp * exp(-j / (dl * 0.25))
	for i in fade:   # the seam: the tail laid over the head
		var k := float(i) / fade
		out[i] = out[i] * k + out[n + i] * (1.0 - k)
	out.resize(n)
	return out


## Thunder: the crack (bright, short), then the long roll, swelling and falling away in waves.
static func _thunder(dur: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var a := 0.0
	var b := 0.0
	var crack := _r.randf_range(0.0, 0.08)
	for i in n:
		var t := float(i) / RATE
		var w := _r.randf_range(-1.0, 1.0)
		a += (w - a) * 0.012
		b += (w - b) * 0.25
		var roll := (0.55 + 0.45 * sin(t * 4.1 + sin(t * 1.3) * 2.0)) * exp(-t * 0.55) * minf(1.0, t * 3.0)
		var snap := exp(-maxf(t - crack, 0.0) * 14.0) * (1.0 if t >= crack else 0.0)
		out[i] = a * 7.0 * roll + b * 0.5 * snap
	return _lp(out, 2400.0)


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


static func _rumble(dur: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var last := 0.0
	for i in n:
		var t := float(i) / RATE
		last = lerpf(_r.randf_range(-1.0, 1.0), last, 0.996)
		out[i] = last * 5.0 + 0.3 * sin(TAU * 31.0 * t) * (0.6 + 0.4 * sin(TAU * t / 2.0))
	return out


static func _chitter(dur: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var burst := 1.0 if fmod(t * 22.0, 1.0) < 0.35 else 0.0
		out[i] = _r.randf_range(-1.0, 1.0) * burst * 0.4 * _env(i, n)
	return out



# --- filters and building blocks ---------------------------------------------------------

static func _lp(a: PackedFloat32Array, cutoff: float) -> PackedFloat32Array:
	var k := 1.0 - exp(-TAU * cutoff / RATE)
	var y := 0.0
	for i in a.size():
		y += (a[i] - y) * k
		a[i] = y
	return a


static func _hp(a: PackedFloat32Array, cutoff: float) -> PackedFloat32Array:
	var k := 1.0 - exp(-TAU * cutoff / RATE)
	var low := 0.0
	for i in a.size():
		low += (a[i] - low) * k
		a[i] = a[i] - low
	return a


static func _bp(a: PackedFloat32Array, lo: float, hi: float) -> PackedFloat32Array:
	return _lp(_hp(a, lo), hi)


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

static func _amb_factory(dur: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var air := _lp(_lp(_loop_noise(n, 0.0), 180.0), 180.0)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var pump := 0.6 + 0.4 * pow(maxf(0.0, sin(TAU * 0.25 * t)), 4.0)
		out[i] = 0.22 * sin(TAU * 45.0 * t) + 0.1 * sin(TAU * 90.0 * t) + 0.04 * sin(TAU * 135.0 * t) * pump + air[i] * 1.2 * pump
	for k in 3:   # far-off clanks in the machinery
		var at := int((0.9 + k * 2.6) * RATE)
		var c := _lp(_modal([210.0, 560.0, 990.0], [5.0, 7.0, 10.0], [0.25, 0.18, 0.1], 1.2), 1200.0)
		for j in c.size():
			if at + j < n:
				out[at + j] += c[j]
	return out


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


static func _amb_flesh(dur: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var wet := _lp(_lp(_loop_noise(n, 0.0), 200.0), 200.0)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = wet[i] * 1.6
	var beat := _heartbeat(dur, 1.0)
	for i in n:
		out[i] += beat[i] * 0.8
	for k in 5:
		var d := _sweep(500.0 + k * 90.0, 160.0, 0.25, 12.0)
		var at := int(_r.randf_range(0.2, dur - 0.4) * RATE)
		for j in d.size():
			out[at + j] += d[j] * 0.3
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

static func _groan(dur: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		ph += TAU * (48.0 + 14.0 * sin(TAU * 0.4 * t) + _r.randf_range(-4.0, 4.0)) / RATE
		var saw := fmod(ph / TAU, 1.0) * 2.0 - 1.0
		out[i] = saw * 0.4 * sin(PI * t / dur)
	return _lp(out, 500.0)


static func _knocks(dur: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(dur * RATE))
	for k in 3:
		var kn := _modal([330.0, 820.0, 1500.0], [12.0, 18.0, 26.0], [0.4, 0.25, 0.12], 0.4)
		var at := int((0.05 + k * 0.32 + _r.randf() * 0.06) * RATE)
		for j in kn.size():
			if at + j < out.size():
				out[at + j] += kn[j]
	return out


static func _far_steps(dur: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(dur * RATE))
	for k in 5:
		var st := _lp(_add(_noise(0.1, 30.0, 0.5), _tone(70.0, 0.1, 30.0), 0.8), 600.0)
		var at := int((0.1 + k * 0.42) * RATE)
		for j in st.size():
			out[at + j] += st[j] * (0.5 + k * 0.1)
	return out


# --- creature loops ------------------------------------------------------------------------

static func _servo(dur: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var brush := _bp(_loop_noise(n, 0.0), 1500.0, 5000.0)
	for i in n:
		var t := float(i) / RATE
		out[i] = 0.12 * sin(TAU * 220.0 * t + 2.0 * sin(TAU * 6.0 * t)) + 0.05 * sin(TAU * 1760.0 * t) + brush[i] * 0.25
	return out


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


static func _drip_loop(dur: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(dur * RATE))
	for k in 4:
		var d := _sweep(_r.randf_range(600.0, 900.0), _r.randf_range(1800.0, 2600.0), 0.08, 35.0)
		var at := int((0.3 + k * 0.95 + _r.randf() * 0.2) * RATE)
		for j in d.size():
			out[at + j] += d[j]
	var wet := _lp(_loop_noise(out.size(), 0.0), 200.0)
	for i in out.size():
		out[i] += wet[i] * 0.15
	return out


static func _chime(dur: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(dur * RATE))
	var notes := [1318.5, 1568.0, 1760.0, 2093.0]
	for k in 6:
		var f: float = notes[_r.randi() % notes.size()]
		var c := _modal([f, f * 2.76], [3.0, 5.0], [0.12, 0.05], 1.0)
		var at := int(_r.randf_range(0.0, dur - 1.0) * RATE)
		for j in c.size():
			out[at + j] += c[j]
	return out


static func _buzz_tone(dur: float, f: float) -> PackedFloat32Array:
	# Mains hum: a clipped fundamental with odd harmonics (whole cycles, so it loops).
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		out[i] = clampf(1.6 * sin(TAU * f * t), -1.0, 1.0) * 0.25 + 0.08 * sin(TAU * f * 3.0 * t)
	return out


static func _steam(dur: float) -> PackedFloat32Array:
	var a := _hp(_loop_noise(int(dur * RATE), 0.2), 1200.0)
	for i in a.size():
		a[i] *= 0.6
	return a


static func _cough() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for k in 3:
		var c := _add(_bp(_noise(0.16, 16.0, 0.45), 250.0, 1600.0), _sweep(210.0, 150.0, 0.14, 18.0), 0.6)
		out.append_array(c)
		var gap := PackedFloat32Array()
		gap.resize(int(_r.randf_range(0.08, 0.16) * RATE))
		out.append_array(gap)
	return out


static func _plane(dur: float) -> PackedFloat32Array:
	# Prop plane passing over: buzzing drone that swells and drops in pitch (doppler).
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	var last := 0.0
	for i in n:
		var t := float(i) / n
		var f := lerpf(96.0, 72.0, smoothstep(0.35, 0.65, t))
		ph += TAU * f / RATE
		last = lerpf(_r.randf_range(-1.0, 1.0), last, 0.9)
		var amp := pow(sin(PI * t), 2.0)
		out[i] = (0.3 * signf(sin(ph)) * (0.6 + 0.4 * sin(ph * 0.5)) + last * 0.4) * amp
	return _lp(out, 900.0)


## Five-chime locomotive air horn (the K5LA chord: D#, F#, G#, B, D#). Each chime is a reed-like
## harmonic tone read from one wavetable, with a pitch bloom at the start, a slight drift between the
## bells, breath noise, a soft-clipped body and a falling release.
static func _horn() -> PackedFloat32Array:
	var dur := 2.4
	var n := int(dur * RATE)
	var table := PackedFloat32Array()
	table.resize(1024)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for k in range(1, 21):   # spectrum: a reedy horn, harmonics falling slowly, a formant round the 3rd-4th
		var amp := pow(float(k), -0.55) * (1.0 + 1.1 * exp(-pow(k - 3.5, 2.0) / 3.0))
		var ph := rng.randf() * TAU
		for i in 1024:
			table[i] += sin(TAU * k * i / 1024.0 + ph) * amp
	var peak := 0.0
	for v in table:
		peak = maxf(peak, absf(v))
	for i in 1024:
		table[i] /= peak
	var notes := [311.1, 370.0, 415.3, 493.9, 622.3]
	var out := PackedFloat32Array()
	out.resize(n)
	var phases := [0.0, 0.3, 0.55, 0.1, 0.8]
	for j in notes.size():
		var f: float = notes[j] * (1.0 + (j - 2) * 0.0015)
		var ph: float = phases[j]
		for i in n:
			var t := float(i) / RATE
			var bloom := 1.0 - 0.035 * exp(-t * 14.0)          # starts a little flat and blooms up
			var fall := 1.0 - 0.02 * clampf((t - (dur - 0.45)) / 0.45, 0.0, 1.0)   # sags as the air cuts
			var vib := 1.0 + 0.0025 * sin(TAU * (5.3 + j * 0.4) * t + j)
			ph = fmod(ph + f * bloom * fall * vib / RATE, 1.0)
			out[i] += table[int(ph * 1024.0) % 1024] * (0.9 if j != 4 else 0.6)
	var breath := _bp(_noise(dur, 0.3, 0.6), 300.0, 2200.0)
	for i in n:
		var t := float(i) / RATE
		var env := clampf(t / 0.12, 0.0, 1.0) * clampf((dur - t) / 0.4, 0.0, 1.0)
		var x := out[i] * 0.22 + breath[i] * 0.2
		out[i] = tanh(x * 2.4) * env
	out = _lp(out, 7000.0)
	return _add(out, _lp(_shift(out, 0.31), 1500.0), 0.18)   # a slap back off the landscape


## Big two-stroke diesel at idle: uneven firing thumps at 34 Hz with their harmonics, block rattle,
## a faint turbo whine and the cam tick. Whole cycles, so it loops; pitch it up for revs.
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


## Air compressor running: piston thumps eight times a second with a metallic knock and intake hiss.
static func _compressor(dur: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var hiss := _loop_noise(n, 0.1)
	for i in n:
		var t := float(i) / RATE
		var stroke := fmod(t * 8.0, 1.0)
		out[i] = sin(TAU * 64.0 * t) * exp(-stroke * 9.0) * 0.6 + sin(TAU * 820.0 * t) * exp(-stroke * 40.0) * 0.18 + hiss[i] * 0.05 * (0.5 + 0.5 * sin(TAU * 8.0 * t))
	return _lp(out, 3000.0)


## A high whine that rings on after the flash, wavering a little, fading slowly.
static func _tinnitus(dur: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		out[i] = 0.16 * sin(TAU * (5800.0 + 40.0 * sin(TAU * 0.7 * t)) * t) * exp(-0.65 * t) * minf(1.0, t * 30.0) * _env(i, n)
	return out


## Lens motor hunting for focus, between irregular dry ticks. Loops.
static func _lens_tick(dur: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for t0 in [0.15, 0.31, 0.9, 1.55, 1.68, 2.4]:
		var tick := _add(_hp(_noise(0.015, 200.0, 0.0), 3000.0), _modal([3700.0, 5200.0], [120.0, 160.0], [0.35, 0.2], 0.03), 0.8)
		var at := int(t0 * RATE)
		for i in tick.size():
			if at + i < n:
				out[at + i] += tick[i] * 0.8
	var whir := _bp(_loop_noise(n, 0.0), 2000.0, 6000.0)
	for i in n:   # two short focus whirs per loop (whole cycles, so it loops cleanly)
		var t := float(i) / RATE
		var g := maxf(0.0, sin(TAU * t * 2.0 / dur)) ** 8
		out[i] += (whir[i] * 0.12 + 0.05 * sin(TAU * 850.0 * t)) * g
	return out


## Several voices whispering over each other: noise shaped by moving formant bands, chopped into
## syllables. Every envelope runs a whole number of cycles over the loop, so it has no seam.
static func _whisper(dur: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for v in 4:
		var hiss := _loop_noise(n, 0.0)
		var lo := 600.0 + v * 350.0
		var voice := _bp(hiss, lo, lo + 1800.0 + v * 400.0)
		var rate := float(3 + v * 2)   # syllables per loop
		var ph := _r.randf() * TAU
		for i in n:
			var t := float(i) / n
			var syl := maxf(0.0, sin(TAU * rate * 2.0 * t + ph)) ** 2
			var phrase := 0.5 + 0.5 * sin(TAU * (v + 1) * t + ph * 0.5)
			out[i] += voice[i] * syl * phrase * 0.9
	return out


## In through the nose, out through the mouth, inside a helmet: two breaths per 4 s loop.
static func _breath(dur: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var air := _bp(_loop_noise(n, 0.0), 350.0, 2400.0)
	var rasp := _bp(_loop_noise(n, 0.0), 900.0, 4200.0)
	for i in n:
		var t := float(i) / n * 2.0   # two breaths per loop
		var ph := fmod(t, 1.0)
		var inhale := sin(PI * clampf(ph / 0.4, 0.0, 1.0)) if ph < 0.4 else 0.0
		var exhale := sin(PI * clampf((ph - 0.45) / 0.45, 0.0, 1.0)) if ph >= 0.45 and ph < 0.9 else 0.0
		out[i] = air[i] * (inhale * 0.55 + exhale * 0.9) + rasp[i] * inhale * 0.25
	return out


## A heavy steel bulkhead on its rack: a motor winding up and down in the low end, the rack chain
## rattling, rumble through the frame, and a deep clunk as it seats. Nothing sharp, nothing high.
static func _bulkhead(dur: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var rumble := _lp(_lp(_loop_noise(n, 0.0), 140.0), 140.0)
	var chain := _bp(_rattle(dur, 26.0), 250.0, 1200.0)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var run := clampf(t / 0.15, 0.0, 1.0) * clampf((dur - 0.3 - t) / 0.2, 0.0, 1.0)   # the motor runs, then cuts
		var f := 46.0 + 22.0 * run
		ph += TAU * f / RATE
		var motor := (sin(ph) * 0.5 + sin(ph * 2.0) * 0.22 + sin(ph * 3.0) * 0.08) * run
		out[i] = motor * 0.55 + rumble[i] * 2.4 * run + chain[i] * 0.35 * run
	var seat := _lp(_modal([62.0, 141.0, 233.0, 360.0], [5.0, 7.0, 10.0, 14.0], [0.7, 0.45, 0.25, 0.12], 0.9), 900.0)
	var at := int((dur - 0.32) * RATE)
	for j in seat.size():
		if at + j < n:
			out[at + j] += seat[j] * 0.9
	return _lp(out, 1600.0)


## The shredder running: a big induction motor's 50 Hz hum and its harmonics, the gearbox's whine,
## the cutter discs' teeth thumping past the combs four times a second, a low churn under it all.
## Whole cycles over the loop; pitch it up from standstill as it spools.
static func _shred_motor(dur: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var churn := _lp(_lp(_loop_noise(n, 0.0), 220.0), 220.0)
	var rasp := _bp(_loop_noise(n, 0.0), 900.0, 2600.0)
	for i in n:
		var t := float(i) / RATE
		var hum := sin(TAU * 50.0 * t) * 0.32 + sin(TAU * 100.0 * t) * 0.2 + sin(TAU * 150.0 * t) * 0.09 + sin(TAU * 300.0 * t) * 0.04
		var whine := sin(TAU * 620.0 * t + 0.4 * sin(TAU * 1.5 * t)) * 0.05
		var teeth := pow(maxf(0.0, sin(TAU * 4.0 * t)), 12.0)
		out[i] = hum * 0.6 + whine + churn[i] * 3.2 * (0.6 + 0.4 * teeth) + rasp[i] * 0.25 * teeth
	return out


## Something going through the cutters. Metal: a run of crunching clanks, a tearing screech and
## a low crush. Soft (plastic, rubber, wood): snapping, crackling, a duller crush.
static func _shred_chew(dur: float, metal: bool) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var bites := 14 if metal else 18
	for b in bites:
		var at := int(_r.randf_range(0.0, 0.85) * n)
		var hit: PackedFloat32Array
		if metal:
			var f := _r.randf_range(320.0, 900.0)
			hit = _modal([f, f * 2.37, f * 3.9, f * 5.6], [22.0, 28.0, 36.0, 50.0], [0.5, 0.35, 0.22, 0.12], 0.22)
		else:
			hit = _hp(_noise(0.06, 70.0, 0.1), _r.randf_range(900.0, 2200.0))
		var amp := _r.randf_range(0.35, 0.9)
		for j in hit.size():
			if at + j < n:
				out[at + j] += hit[j] * amp
	var crush := _lp(_noise(dur, 1.6, 0.9), 260.0)
	var tear := _bp(_noise(dur, 2.0, 0.2), 1600.0, 3800.0) if metal else _grains(dur, 60, 0.9)
	for i in n:
		var env := clampf(float(i) / (0.05 * RATE), 0.0, 1.0) * clampf(float(n - i) / (0.25 * RATE), 0.0, 1.0)
		out[i] = (out[i] + crush[i] * 3.5 + tear[i] * (0.5 if metal else 0.8)) * env
	return out


## The cutters jam on something too tough: a heavy clunk, the motor bogging down to a groan, then
## the drive kicking into reverse with a whir.
static func _shred_jam() -> PackedFloat32Array:
	var dur := 1.3
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := 50.0 - 26.0 * clampf(t / 0.6, 0.0, 1.0) + 34.0 * clampf((t - 0.75) / 0.4, 0.0, 1.0)
		ph += TAU * f / RATE
		var groan := (sin(ph) * 0.5 + sin(ph * 2.0) * 0.3 + sin(ph * 3.0) * 0.15) * clampf((dur - t) / 0.2, 0.0, 1.0)
		out[i] = groan * 0.7
	var clunk := _lp(_modal([58.0, 131.0, 260.0, 470.0], [4.0, 6.0, 9.0, 14.0], [0.8, 0.55, 0.35, 0.2], 0.9), 1100.0)
	return _add(out, clunk, 1.0)


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


## A belt conveyor: rollers rumbling under the belt, the splice slapping past.
static func _conveyor(dur: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var roll := _lp(_loop_noise(n, 0.0), 380.0)
	for i in n:
		var t := float(i) / RATE
		var slap := exp(-fmod(t, 1.0) * 40.0)
		out[i] = roll[i] * 2.0 * (0.8 + 0.2 * sin(TAU * 6.0 * t)) + slap * sin(TAU * 140.0 * t) * 0.4
	return out


# --- impacts and steps, rebuilt from measurements of real recordings ---------------------------

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
		"carpet":
			heel = _add(_lp(_noise(0.08, 40.0, 0.6), 700.0), _tone(75.0 * r, 0.07, 40.0), 0.6)
			toe = _lp(_noise(0.07, 45.0, 0.5), 900.0)
	return _add(heel, _shift(toe, toe_at), _r.randf_range(0.45, 0.65))


## Something dropped on a hard floor: three knocks off its body (round 200, 700 and 1800 Hz in
## the recordings), a click of contact, a short scrape of noise.
static func _thunk() -> PackedFloat32Array:
	var r := _r.randf_range(0.8, 1.25)
	var body := _modal([200.0 * r, 700.0 * r, 1800.0 * r, 2600.0 * r], [50.0, 45.0, 35.0, 60.0], [1.0, 0.45, 0.4, 0.12], 0.25)
	var click := _hp(_noise(0.006, 600.0, 0.0), 1500.0)
	return _add(_add(body, click, 0.6), _lp(_noise(0.06, 60.0, 0.4), 900.0), 0.3)


## A steel bar or pipe struck: the partials of a free bar (1 : 2.76 : 5.40 : 8.93), the low hum
## of the structure it's on ringing on, the contact click.
static func _clank() -> PackedFloat32Array:
	var f := _r.randf_range(480.0, 820.0)
	var bar := _modal([f, f * 2.76, f * 5.40, f * 8.93], [12.0, 18.0, 26.0, 36.0], [0.6, 0.45, 0.25, 0.12], 0.9)
	var hum := _modal([f * 0.22, f * 0.31], [3.0, 4.0], [0.12, 0.08], 0.9)
	return _add(_add(bar, hum, 1.0), _hp(_noise(0.004, 800.0, 0.0), 2000.0), 0.5)


## A swing door slamming: the leaf's woody knock (128-360 Hz), the frame's thump, the latch
## snapping home a beat later.
static func _slam() -> PackedFloat32Array:
	var r := _r.randf_range(0.94, 1.06)
	var wood := _modal([128.0 * r, 198.0 * r, 261.0 * r, 328.0 * r, 358.0 * r], [9.0, 11.0, 12.0, 14.0, 15.0], [0.5, 0.8, 0.6, 0.5, 0.45], 0.8)
	var thump := _add(_tone(50.0, 0.25, 16.0), _lp(_noise(0.03, 100.0, 0.2), 1800.0), 0.6)
	return _add(_add(wood, thump, 0.8), _shift(_latch(), 0.012), 0.5)


## A latch: a small metal click and its rattle.
static func _latch() -> PackedFloat32Array:
	return _add(_modal([2300.0, 3150.0, 4400.0], [60.0, 80.0, 100.0], [0.3, 0.2, 0.1], 0.1), _hp(_noise(0.005, 500.0, 0.0), 2500.0), 0.6)


## A water drop: the bubble rings as it closes, rising fast (400 to ~1000 Hz), over a soft tap.
static func _drip() -> PackedFloat32Array:
	var f0 := _r.randf_range(380.0, 520.0)
	var n := int(0.12 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		ph += TAU * f0 * (1.0 + 1.4 * clampf(t / 0.03, 0.0, 1.0)) / RATE
		out[i] = sin(ph) * exp(-t * 45.0) * clampf(t / 0.002, 0.0, 1.0)
	return _add(out, _lp(_noise(0.01, 300.0, 0.1), 1500.0), 0.25)


## Glass giving: a crack, then the tinkle of small pieces (2.7-4 kHz, a few hundred ms).
static func _crack_glass() -> PackedFloat32Array:
	var crack := _add(_hp(_noise(0.03, 120.0, 0.0), 2000.0), _modal([2900.0, 4300.0, 6100.0], [40.0, 55.0, 70.0], [0.3, 0.2, 0.1], 0.2), 0.6)
	var tinkle := PackedFloat32Array()
	tinkle.resize(int(0.45 * RATE))
	for k in 14:
		var at := int(_r.randf_range(0.02, 0.38) * RATE)
		var bit := _modal([_r.randf_range(2600.0, 4200.0), _r.randf_range(5000.0, 7500.0)], [70.0, 90.0], [0.25, 0.12], 0.05)
		for j in bit.size():
			if at + j < tinkle.size():
				tinkle[at + j] += bit[j] * _r.randf_range(0.3, 1.0) * (1.0 - float(at) / tinkle.size())
	return _add(crack, tinkle, 0.7)


## A creature's voice: a rough source (a sawtooth whose pitch wanders and flutters, the rasp of
## a throat at `rasp` Hz), shaped by three formants, breath under it. From recordings of big
## cats and screams: growls voice round 110-190 Hz with formants near 450 / 1100 / 2400; a
## scream round 600-1100 Hz, much brighter; both swell in over 0.1-0.2 s.
static func _voice(dur: float, f0: float, fall: float, rasp: float, formants: Array, breath: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := f0 * (1.0 - fall * t / dur) * (1.0 + 0.1 * sin(TAU * 0.9 * t) + 0.035 * sin(TAU * 7.0 * t) + _r.randf_range(-0.03, 0.03))
		ph += TAU * f / RATE
		var saw := fmod(ph / TAU, 1.0) * 2.0 - 1.0
		var flutter := 0.6 + 0.4 * sin(TAU * rasp * t) * sin(TAU * 3.0 * t)
		var env := clampf(t / 0.15, 0.0, 1.0) * clampf((dur - t) / 0.3, 0.0, 1.0) * (0.75 + 0.25 * sin(TAU * 1.3 * t))
		out[i] = tanh(saw * 1.8 * flutter) * env
	var shaped := PackedFloat32Array()
	shaped.resize(n)
	for k in formants.size():
		var fc: float = formants[k]
		shaped = _add(shaped, _bp(out, fc * 0.8, fc * 1.2), 1.0 / (1.0 + k * 0.8))
	var air := _bp(_noise(dur, 0.5, 0.3), formants[0] * 0.8, formants[-1] * 1.3)
	for i in n:
		var t := float(i) / RATE
		air[i] *= clampf(t / 0.15, 0.0, 1.0) * clampf((dur - t) / 0.3, 0.0, 1.0)
	return _add(shaped, air, breath)


## An old site klaxon: a low, gritty two-tone horn through a horn speaker. Loud, but down where it
## doesn't hurt.
static func _klaxon(dur: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := 196.0 if fmod(t, 0.9) < 0.45 else 165.0
		ph += TAU * f / RATE
		var saw := fmod(ph / TAU, 1.0) * 2.0 - 1.0
		var env := clampf(t / 0.04, 0.0, 1.0) * clampf((dur - t) / 0.15, 0.0, 1.0)
		out[i] = tanh(saw * 1.8) * 0.35 * env
	return _lp(_lp(out, 1400.0), 1400.0)


## A door on worn hinges: a low, soft stick-slip creak, filtered, no squeal.
static func _hinge(dur: float, pitch: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		ph += TAU * (95.0 + 35.0 * sin(TAU * 1.1 * t) + _r.randf_range(-12.0, 12.0)) * pitch / RATE
		var saw := fmod(ph / TAU, 1.0) * 2.0 - 1.0
		var env := sin(PI * clampf(t / dur, 0.0, 1.0))
		out[i] = saw * 0.22 * env * (0.65 + 0.35 * sin(TAU * 7.0 * t))
	return _lp(_lp(out, 900.0), 900.0)


## The door swinging to: a wooden thump with the latch clicking home.
static func _door_thump() -> PackedFloat32Array:
	return _add(_lp(_modal([85.0, 190.0, 320.0], [12.0, 16.0, 22.0], [0.7, 0.4, 0.2], 0.35), 700.0), _shift(_lp(_noise(0.03, 120.0, 0.2), 2500.0), 0.02), 0.25)


## A wind-up alarm clock going off: the hammer rattling between two small bells.
static func _alarm_bell(dur: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var hits := int(dur * 22.0)
	for k in hits:
		var f := 2350.0 if k % 2 == 0 else 2780.0
		var bell := _modal([f, f * 2.32, f * 3.1], [26.0, 38.0, 55.0], [0.5, 0.25, 0.12], 0.12)
		var at := int(k * RATE / 22.0)
		for j in bell.size():
			if at + j < n:
				out[at + j] += bell[j] * 0.6
	return out


## A wet gurgle from deep in something: a low, thick murmur with bubbles popping up through it.
static func _gurgle(dur: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := _lp(_noise(dur, 1.2, 0.9), 380.0)
	for i in n:
		var t := float(i) / RATE
		out[i] *= 1.6 * sin(PI * t / dur) * (0.7 + 0.3 * sin(TAU * 7.0 * t))
	for b in 9:   # bubbles: short upward chirps, bigger ones lower
		var at := int(_r.randf_range(0.05, dur - 0.15) * RATE)
		var f := _r.randf_range(140.0, 420.0)
		var bub := _sweep(f, f * _r.randf_range(1.6, 2.4), _r.randf_range(0.04, 0.09), 30.0)
		for j in bub.size():
			if at + j < n:
				out[at + j] += bub[j] * 0.7
	return _lp(out, 1800.0)
