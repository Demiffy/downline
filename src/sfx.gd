# Every sound is synthesized at runtime, so the project ships with zero audio files.
# Filters + modal synthesis (stacks of decaying partials) for metal; 3D sounds go through a
# "World" bus whose reverb follows where you are (set_space): a big hall underground, a small
# box in the train, almost dry outside.
extends RefCounted

const Engines = preload("res://src/engine_data.gd")
const Prints = preload("res://src/sound_prints.gd")
const SoundPrint = preload("res://src/sound_print.gd")
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
const ALL := ["beep", "ding", "pickup", "error", "key", "click", "step", "hurt", "boom", "door", "alarm", "horn", "diesel_idle", "compressor", "air_release", "scan", "blip", "screech", "drone", "creak", "grind", "rumble", "roar", "growl", "shriek", "thud", "snap", "slurp", "chitter", "clack", "hiss", "flash", "wind", "rain", "rain_roof", "thunder", "stamp", "flicker_buzz", "motor", "chug", "muzak", "step_concrete", "step_tiles", "step_metal", "step_wood", "step_sand", "step_snow", "step_flesh", "step_carpet", "land", "clank", "clang_big", "thunk", "rustle", "slide", "clunk", "open_box", "heavy_lift", "amb_factory", "amb_lab", "amb_flesh", "amb_backrooms", "amb_yard", "diesel", "rail_clack", "rail_roll", "prime_lo", "prime_mid", "prime_hi", "turbo", "traction", "far_bang", "groan", "drip", "pipe_knock", "far_screech", "far_steps", "servo", "heartbeat", "searchlight", "drip_loop", "rattle", "chime", "step_water", "power_down", "power_up", "zap", "crackle", "buzz", "steam", "steam_burst", "cough", "quake", "debris", "plane", "flare", "shutter", "flash_whine", "flashbulb", "tinnitus", "lens_tick", "whisper", "wraith_shriek", "wraith_grab", "dissolve", "swish", "shotgun", "dry_fire", "breath", "heart", "gurgle", "alarm_bell", "bulkhead", "crack_glass", "klaxon", "door_open", "door_shut", "breaker", "shred_motor", "shred_metal", "shred_soft", "shred_jam", "ratchet", "conveyor", "waterfall", "amb_dam", "clap", "plane_loop", "chute_pop", "explosion_far", "crate_pry", "drop_fall", "drop_land", "backfire", "squeak", "jingle", "toot", "phone_ring", "mama", "vroom", "reverse_beep", "robot", "radio_tune", "typewriter", "speaker_pop", "whistle", "fart", "mumble", "truck_idle", "truck_rev", "fork_idle", "fork_work"]
## Sounds that come in several takes (so ten footsteps in a row aren't ten copies of one).
const TAKES := 4
static func _has_takes(sound: String) -> bool:
	return _takes(sound) > 1


## How many takes: a print from several recordings, one per recording; footsteps and the other
## often-heard ones four (from the same print or synth, each with its own dice).
static func _takes(sound: String) -> int:
	var n: int = Prints.P[sound].size() if Prints.P.has(sound) else 0
	if n > 1:
		return n
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


static func stream(sound: String) -> AudioStreamWAV:
	if _has_takes(sound) and not "#" in sound:
		_take += 1
		sound = "%s#%d" % [sound, _take % _takes(sound)]
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


const FIRST := ["land", "clank", "thunk", "rustle", "amb_factory", "amb_lab", "amb_flesh", "amb_backrooms", "amb_yard", "diesel", "rail_clack", "wind"]


static func _warm_all() -> void:
	for name: String in STEPS.map(func(k): return "step_" + k) + FIRST + ALL:
		if _has_takes(name):
			for t in _takes(name):
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
	var take := int(sound.get_slice("#", 1)) if "#" in sound else 0
	sound = sound.get_slice("#", 0)
	match sound:
		_ when Prints.P.has(sound): s = _printed(sound, take)   # (rebuilt from a real recording)
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
		"prime_lo": s = _prime_mover(400.0, 0.0)
		"prime_mid": s = _prime_mover(720.0, 0.5)
		"prime_hi": s = _prime_mover(1050.0, 1.0)
		"turbo": s = _turbo(2.0)
		"traction": s = _traction(2.0)
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
		"waterfall": s = _waterfall(6.0)
		"clap": s = _clap()
		"amb_dam": s = _amb_dam(8.0)
		"rain_roof": s = _rain(5.0, true)
		"thunder": s = _thunder(6.5)
		"stamp": s = _stamp()
		"flicker_buzz": s = _flicker_buzz(3.0)
		"motor": s = _motor(4.0)
		"chug": s = _chug(1.0)
		"muzak": s = _muzak()
		# --- footsteps by surface ---
		"step_concrete", "step_tiles", "step_metal", "step_wood", "step_sand", "step_snow", "step_mud", "step_grass":
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
		"rail_clack": s = _rail_joint()
		"rail_roll": s = _rail_roll(4.0)
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
		# --- toys and things that make a noise when you use them (data.gd "toy") ---
		"squeak": s = _squeak()
		"jingle": s = _jingle()
		"toot": s = _toot()
		"phone_ring": s = _phone_ring()
		"mama": s = _mama()
		"vroom": s = _vroom()
		"reverse_beep": s = _reverse_beep()
		"robot": s = _robot()
		"radio_tune": s = _radio_tune()
		"typewriter": s = _typewriter()
		"speaker_pop": s = _add(_hp(_grains(0.7, 60, 0.8), 1800.0), _buzz_tone(0.7, 50.0), 0.5)
		"whistle": s = _whistle()
		"fart": s = _fart()
		"mumble": s = _mumble()
		"truck_idle": s = _engine_cycles(Engines.DIESEL_IDLE)
		"truck_rev": s = _engine_cycles(Engines.DIESEL_REV)
		"fork_idle": s = _engine_cycles(Engines.FORK_IDLE)
		"fork_work": s = _engine_cycles(Engines.FORK_WORK)
		"zap": s = _add(_hp(_grains(0.45, 220, 0.4), 1500.0), _buzz_tone(0.45, 120.0), 0.7)
		"crackle": s = _hp(_grains(0.7, 90, 0.9), 2200.0)
		"buzz": s = _buzz_tone(2.0, 60.0)
		"steam": s = _steam(2.0)
		"steam_burst": s = _add(_hp(_noise(2.4, 0.5, 0.15), 900.0), _lp(_noise(0.4, 8.0, 0.8), 400.0), 1.2)
		"cough": s = _cough()
		"quake": s = _add(_lp(_noise(4.5, 0.4, 0.993), 220.0), _shift(_groan(3.0), 0.6), 0.35)
		"debris": s = _add(_lp(_noise(0.6, 7.0, 0.85), 900.0), _modal([140.0, 330.0, 610.0], [9.0, 13.0, 18.0], [0.5, 0.3, 0.2], 0.6), 0.9)
		"plane": s = _plane(7.0)
		"plane_loop": s = _plane_loop(6.0)
		"chute_pop": s = _chute_pop()
		"explosion_far": s = _explosion_far()
		"crate_pry": s = _crate_pry()
		"drop_fall": s = _drop_fall()
		"drop_land": s = _drop_land()
		"backfire": s = _add(_lp(_noise(0.35, 14.0, 0.6), 700.0), _sweep(90.0, 45.0, 0.3, 12.0), 1.2)   # an engine coughing: a dull pop, no ring
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
	if sound in LOOPS and not Prints.P.has(sound):   # (a print's loop is already crossfaded end into start)
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


## A sound rebuilt from its print, kept on disk once built (they take a while: the next time it's read
## back instead), under its own numbers' hash and the rebuild's version.
static func _printed(sound: String, take: int) -> PackedFloat32Array:
	var p: Dictionary = Prints.P[sound][take % Prints.P[sound].size()]
	var path := "user://sfx_cache/%s_%d_%x.f32" % [sound, take, hash([p, SoundPrint.VERSION])]
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			var got := f.get_buffer(f.get_length()).to_float32_array()
			if got.size() > 0:
				return got
	var s := SoundPrint.build(p, _r)
	DirAccess.make_dir_recursive_absolute("user://sfx_cache")
	var w := FileAccess.open(path, FileAccess.WRITE)
	if w != null:
		w.store_buffer(s.to_byte_array())
	return s


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
## Under a dam: the generators' hum through the concrete (mains and its harmonics, beating slowly),
## water rushing somewhere behind the walls, the drip of seepage. Loops.
static func _amb_dam(dur: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var rush := _lp(_lp(_loop_noise(n, 0.0), 420.0, true), 420.0, true)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var beat := 0.75 + 0.25 * sin(TAU * t / dur * 2.0)
		out[i] = (0.1 * sin(TAU * 50.0 * t) + 0.07 * sin(TAU * 100.0 * t + 0.4) + 0.025 * sin(TAU * 150.0 * t) + 0.02 * sin(TAU * 101.0 * t)) * beat + rush[i] * 1.4
	for k in 5:   # seepage dripping into a puddle somewhere
		var c := _modal([1400.0 + k * 230.0, 2900.0 + k * 310.0], [40.0, 60.0], [0.05, 0.02], 0.3)
		var at := int((0.7 + k * 1.45) * RATE)
		for j in c.size():
			out[(at + j) % n] += c[j]
	return out


## Two gloved hands clapped: a dull slap (the gloves take the crack off it), a short body under it.
static func _clap() -> PackedFloat32Array:
	var n := int(0.12 * RATE)
	var noise := _bp(_noise(0.12, 0.0, 0.0), 700.0, 3200.0)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		out[i] = noise[i] * exp(-t * 55.0) * 1.6 * minf(1.0, i / 12.0) + sin(TAU * 210.0 * t) * exp(-t * 70.0) * 0.25
	return out


## A spillway in spate: a broad roar of white water with the weight of it under (the plunge into the
## basin booming low and uneven), hiss on top. Filters wrapped round: it loops seamlessly.
static func _waterfall(dur: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var hiss := _bp(_loop_noise(n, 0.0), 900.0, 5200.0, true)
	var body := _bp(_loop_noise(n, 0.0), 120.0, 900.0, true)
	var boom := _lp(_lp(_loop_noise(n, 0.0), 60.0, true), 60.0, true)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var surge := 0.8 + 0.2 * sin(TAU * t / dur * 3.0) * sin(TAU * t / dur * 5.0 + 1.0)   # (whole cycles: it loops)
		out[i] = hiss[i] * 0.28 + body[i] * 0.55 * surge + boom[i] * 9.0
	return out


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

## One wheelset over a rail joint, as jointed track sounds in recordings: the dull knock of the wheel
## dropping into the gap and the car body answering it low (most of the energy under 200 Hz), a short
## gritty clack where it climbs out, and the rail ringing faintly after. The train plays one per axle,
## front to back, so the joints come out in their rhythm: da-dum ... da-dum, da-dum.
static func _rail_joint() -> PackedFloat32Array:
	var knock := _modal([62.0 * _r.randf_range(0.93, 1.07), 104.0, 168.0], [24.0, 34.0, 50.0], [1.0, 0.55, 0.28], 0.5)
	var clack := _bp(_noise(0.07, 55.0, 0.25), 240.0, 1300.0)
	var ring := _modal([455.0, 720.0, 1180.0, 1910.0, 3050.0], [20.0, 25.0, 31.0, 40.0, 55.0], [0.09, 0.08, 0.055, 0.035, 0.02], 0.5)
	var s := _add(_add(knock, _shift(clack, 0.004), 0.9), ring, 1.0)
	return _lp(s, 2600.0)


## Rolling: a low rumble through the floor, the roar of wheel on rail in the middle, a little hiss
## on top, breathing slowly as the wheels and rails wander. A loop.
static func _rail_roll(dur: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var low := _lp(_lp(_loop_noise(n, 0.0), 95.0), 95.0)
	var mid := _bp(_loop_noise(n, 0.0), 320.0, 1700.0)
	var hiss := _bp(_loop_noise(n, 0.0), 2600.0, 6000.0)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var wander := 0.82 + 0.18 * sin(TAU * t / dur * 2.0) * sin(TAU * t / dur * 3.0)
		out[i] = (low[i] * 7.0 + mid[i] * 0.32 * wander + hiss[i] * 0.05) + 0.12 * sin(TAU * 41.0 * t) * wander
	return out


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


## Two radial engines droning, a hair out of step so they beat (the throb of an old twin): each a
## buzz of cylinders firing with the props' blade-pass under it, exhaust crackle on top. Whole cycles
## of everything, filters wrapped: it loops. (airdrop.gd plays it from the plane, with doppler.)
static func _plane_loop(dur: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var crackle := _bp(_loop_noise(n, 0.0), 900.0, 3800.0, true)
	var beat := 1.0 / dur * 3.0   # the throb: three a loop
	for i in n:
		var t := float(i) / RATE
		var e1 := 0.0
		var e2 := 0.0
		for h in [1.0, 2.0, 3.0, 4.0, 6.0]:   # firing at 75 Hz (and its harmonics), the other 75 + the beat
			var a: float = 0.5 / h
			e1 += sin(TAU * 75.0 * h * t) * a
			e2 += sin(TAU * (75.0 + beat) * h * t + h) * a
		var blade := sin(TAU * 25.0 * t) * 0.6 + sin(TAU * (25.0 + beat / 3.0) * t) * 0.6
		var pulse := 0.75 + 0.25 * sin(TAU * 25.0 * t)
		out[i] = (e1 + e2) * 0.22 * pulse + blade * 0.25 + crackle[i] * 0.18 * pulse
	return _lp(out, 1800.0, true)


## A parachute opening: the drogue's flap, then the main canopy cracking full (a run of sharp canvas
## snaps as the gores fill), a deep whump of air, the risers taking the weight with a twang, and the
## fabric fluttering on as it settles.
static func _chute_pop() -> PackedFloat32Array:
	var n := int(1.8 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var cloth := _bp(_noise(1.8, 0.0, 0.0), 250.0, 3200.0)
	var crack := _hp(_noise(1.8, 0.0, 0.0), 1800.0)
	var snaps := [0.0, 0.035, 0.06, 0.11, 0.16]
	for i in n:
		var t := float(i) / RATE
		var whump := sin(TAU * 44.0 * t - 5.0 * t * t) * exp(-t * 6.0) * minf(1.0, i / 120.0)
		var c := 0.0
		for k in snaps.size():
			var u: float = t - snaps[k]
			if u >= 0.0:
				c += exp(-u * 110.0) * (1.0 - k * 0.15)
		var flutter := (0.55 + 0.45 * sin(TAU * (16.0 - 5.0 * t) * t)) * exp(-t * 2.2)
		out[i] = whump * 1.1 + crack[i] * c * 0.9 + cloth[i] * flutter * 0.5
	var twang := _shift(_modal([182.0, 377.0, 590.0], [7.0, 11.0, 16.0], [0.35, 0.2, 0.1], 1.0), 0.12)
	return _add(out, twang, 1.0)


## The crate falling out of the door: the slipstream whipping past it, rising as it speeds up, the
## static line flapping, until the canopy (chute_pop) cuts it off.
static func _drop_fall() -> PackedFloat32Array:
	var dur := 1.6
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lo := 0.0
	var mid := 0.0
	var k := 0.0
	for i in n:
		var t := float(i) / RATE
		var u := t / dur
		var x := _r.randf_range(-1.0, 1.0)
		k = 1.0 - exp(-TAU * lerpf(250.0, 1400.0, u) / RATE)   # (the rush rising as it gains speed)
		lo += (x - lo) * k
		mid += (lo - mid) * k
		var flap := 0.7 + 0.3 * signf(sin(TAU * (9.0 + 14.0 * u) * t))
		out[i] = (lo - mid) * 2.2 * lerpf(0.3, 1.0, u) * flap * minf(1.0, (n - i) / 400.0) * minf(1.0, i / 600.0)
	return out


## A loaded crate landing on its skid: the deep thump of the weight, the plywood and honeycomb
## crushing (a dense crunch of cracks), the box's own boom, sand and grit hissing out round it.
static func _drop_land() -> PackedFloat32Array:
	var thump := _add(_sweep(70.0, 34.0, 0.6, 7.0), _lp(_noise(0.4, 12.0, 0.9), 220.0), 1.4)
	var crunch := _bp(_grains(0.35, 260, 0.6), 250.0, 2600.0)
	var box := _modal([96.0, 158.0, 231.0, 340.0], [9.0, 12.0, 15.0, 20.0], [0.5, 0.45, 0.3, 0.2], 0.7)
	var sand := _shift(_hp(_noise(1.3, 3.0, 0.2), 700.0), 0.04)
	return _add(_add(_add(thump, crunch, 1.6), box, 0.7), sand, 0.35)


## Prying the crate open (lined up with airdrop.gd's _open): the strap buckles flicked open, the straps
## whipping loose, a nail squealing out of the plywood and the lid cracking free, the lid landing
## behind, the four sides slapping down one after another, each with a little bounce.
static func _crate_pry() -> PackedFloat32Array:
	var out := _add(_latch(), _shift(_latch(), 0.07), 0.9)
	for k in 2:   # the straps letting go
		out = _add(out, _shift(_bp(_sweep(2600.0, 900.0, 0.16, 18.0), 400.0, 5000.0), 0.06 + k * 0.05), 0.5)
		out = _add(out, _shift(_bp(_noise(0.14, 26.0, 0.0), 1500.0, 6000.0), 0.06 + k * 0.05), 0.7)
	out = _add(out, _shift(_sweep(900.0, 1500.0, 0.18, 6.0), 0.1), 0.18)   # the nail squealing
	out = _add(out, _shift(_add(_hp(_noise(0.05, 70.0, 0.0), 1200.0), _modal([310.0, 520.0, 880.0], [30.0, 40.0, 55.0], [0.5, 0.35, 0.2], 0.15), 0.8), 0.24), 0.9)   # the lid cracking free
	out = _add(out, _shift(_wood_slap(1.0), 0.52), 1.0)   # the lid landing
	for k in 4:   # the sides: down, a bounce
		var r := 0.85 + k * 0.07
		out = _add(out, _shift(_wood_slap(r), 0.62 + k * 0.1), 0.8 - k * 0.08)
		out = _add(out, _shift(_wood_slap(r * 1.1), 0.62 + k * 0.1 + 0.11), 0.25)
	return out


## A sheet of plywood slapping down flat: its woody ring and the air puffed out from under it.
static func _wood_slap(r: float) -> PackedFloat32Array:
	var wood := _modal([140.0 * r, 215.0 * r, 330.0 * r, 470.0 * r], [16.0, 20.0, 26.0, 34.0], [0.6, 0.5, 0.35, 0.2], 0.35)
	return _add(_add(wood, _lp(_noise(0.08, 40.0, 0.5), 1200.0), 0.8), _hp(_noise(0.006, 500.0, 0.0), 2000.0), 0.4)


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
## A locomotive's five-chime air horn, after a recording of a Nathan Airchime K5LA (measured with
## tools/sound_analyze.py): five bells in a chord (430, 520, 643, 778, 863 Hz: A, C, E, G, A), each a
## reed's tone that's strong in its first harmonics and falls off fast above (the recording peaks round
## 500 Hz, -9 dB by 1 kHz, -13 by 2), almost no breath in it; it swells in over a fraction of a second as
## the air comes up, the chimes beating slowly against each other, and sags a touch as it's cut.
static func _horn() -> PackedFloat32Array:
	var dur := 2.4
	var n := int(dur * RATE)
	var table := PackedFloat32Array()
	table.resize(1024)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for k in range(1, 13):   # a reed: the first few harmonics strong, then falling off quickly
		var amp := pow(float(k), -1.35) * (1.0 + 0.5 * exp(-pow(k - 2.0, 2.0) / 1.5))
		var ph := rng.randf() * TAU
		for i in 1024:
			table[i] += sin(TAU * k * i / 1024.0 + ph) * amp
	var peak := 0.0
	for v in table:
		peak = maxf(peak, absf(v))
	for i in 1024:
		table[i] /= peak
	var notes := [431.7, 520.0, 643.3, 778.3, 863.3]
	var gains := [0.55, 1.0, 0.6, 0.4, 0.5]
	var out := PackedFloat32Array()
	out.resize(n)
	var phases := [0.0, 0.3, 0.55, 0.1, 0.8]
	for j in notes.size():
		var f: float = notes[j] * (1.0 + (j - 2) * 0.0012)
		var ph: float = phases[j]
		for i in n:
			var t := float(i) / RATE
			var bloom := 1.0 - 0.03 * exp(-t * 9.0)            # starts a little flat and comes up to pitch
			var fall := 1.0 - 0.018 * clampf((t - (dur - 0.4)) / 0.4, 0.0, 1.0)   # sags as the air cuts
			var vib := 1.0 + 0.0015 * sin(TAU * (4.7 + j * 0.37) * t + j)
			ph = fmod(ph + f * bloom * fall * vib / RATE, 1.0)
			out[i] += table[int(ph * 1024.0) % 1024] * float(gains[j])
	var breath := _bp(_noise(dur, 0.3, 0.6), 400.0, 1800.0)
	for i in n:
		var t := float(i) / RATE
		var env := smoothstep(0.0, 0.28, t) * clampf((dur - t) / 0.35, 0.0, 1.0)
		var x := out[i] * 0.2 + breath[i] * 0.04
		out[i] = tanh(x * 1.6) * env
	out = _lp(out, 2600.0)
	return _add(out, _lp(_shift(out, 0.31), 1200.0), 0.16)   # a slap back off the landscape


## An engine as engines sound: each firing is a short burst of gas (a click and a puff of noise) that
## rings the exhaust and the block (resonators, `res`: [Hz, Q, gain]), never two quite alike (the
## timing and strength wander a little), and a diesel's knock: a hard tick high up at each firing.
## `fire` Hz the firing rate, `cyl` cylinders (each its own strength), `dur` a whole number of cycles.
## The pattern repeats exactly, so the middle of three renders is a seamless loop.
static func _engine(fire: float, cyl: int, res: Array, knock: float, hiss: float, seed_n: int, dur := 2.0) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_n
	var count := int(round(fire * dur))
	var events := []   # [time, strength] for one loop
	var lumps := []
	for c in cyl:
		lumps.append(rng.randf_range(0.8, 1.0))
	for k in count:
		events.append([(k + rng.randf_range(-0.06, 0.06)) * dur / count, float(lumps[k % cyl]) * rng.randf_range(0.85, 1.1)])
	var exc := PackedFloat32Array()   # the excitation: three loops of it
	exc.resize(n * 3)
	var tick := PackedFloat32Array()
	tick.resize(n * 3)
	for rep in 3:
		for e in events:
			var at := int((float(e[0]) + rep * dur) * RATE)
			for j in 160:   # ~7 ms: a click and a puff
				if at + j >= exc.size():
					break
				var env := exp(-j / 22.0)
				exc[at + j] += (rng.randf_range(-1.0, 1.0) * 0.6 + (1.0 if j < 3 else 0.0)) * env * float(e[1])
			for j in 90:   # the knock: a hard, short tick
				if at + j >= tick.size():
					break
				tick[at + j] += rng.randf_range(-1.0, 1.0) * exp(-j / 9.0) * float(e[1])
	var out := PackedFloat32Array()
	out.resize(n * 3)
	for r in res:   # each resonance a two-pole band-pass, rung by the bursts
		var f: float = r[0]
		var q: float = r[1]
		var w0 := TAU * f / RATE
		var alpha := sin(w0) / (2.0 * q)
		var b0 := alpha
		var a0 := 1.0 + alpha
		var a1 := -2.0 * cos(w0)
		var a2 := 1.0 - alpha
		var x1 := 0.0
		var x2 := 0.0
		var y1 := 0.0
		var y2 := 0.0
		for i in exc.size():
			var x := exc[i]
			var y := (b0 * x - b0 * x2 - a1 * y1 - a2 * y2) / a0
			x2 = x1
			x1 = x
			y2 = y1
			y1 = y
			out[i] += y * float(r[2])
	if knock > 0.0:
		var hk := _bp(tick, 1200.0, 3500.0)   # (diesel clatter lives up there: not a fizz all the way up)
		for i in out.size():
			out[i] += hk[i] * knock
	if hiss > 0.0:
		var h := _bp(_noise(dur * 3.0, 0.0, 0.3), 400.0, 3000.0)
		for i in mini(h.size(), out.size()):
			out[i] += h[i] * hiss
	var mid := out.slice(n, n * 2)
	var peak := 0.0
	for v in mid:
		peak = maxf(peak, absf(v))
	for i in mid.size():
		mid[i] = tanh(mid[i] / maxf(peak, 0.0001) * 1.3) * 0.75
	return mid


## An engine rebuilt from its measured cycles (engine_data.gd, tools/engine_cycles.py): its own
## waveform for one cycle, laid end to end, each cycle a little longer or shorter and louder or softer
## (as measured), with the measured noise over it, shaped by its FIR and swelling through each cycle
## as it did. The jitter repeats every loop, so the middle of three renders loops without a seam.
static func _engine_cycles(d: Dictionary, dur := 2.0) -> PackedFloat32Array:
	var cyc: Array = d.cycle
	var L := cyc.size()
	var fir: Array = d.noise_fir
	var env: Array = d.noise_env
	var count := int(round(dur * RATE / float(L)))
	var rng := RandomNumberGenerator.new()
	rng.seed = L * 7919 + count
	var lens := []
	var gains := []
	var total := 0
	for k in count:
		lens.append(maxi(8, int(round(L * (1.0 + rng.randfn(0.0, float(d.len_jitter)))))))
		gains.append(1.0 + rng.randfn(0.0, float(d.gain_jitter)))
		total += lens[k]
	var rms := 0.0
	for v in cyc:
		rms += float(v) * float(v)
	rms = sqrt(rms / L)
	var out := PackedFloat32Array()
	out.resize(total * 3)
	var nrng := RandomNumberGenerator.new()
	for rep_i in 3:
		nrng.seed = 17   # (the same noise each loop: seamless)
		var at := rep_i * total
		for k in count:
			var ln: int = lens[k]
			var g: float = gains[k]
			var raw := PackedFloat32Array()
			raw.resize(ln + fir.size())
			for j in raw.size():
				raw[j] = nrng.randfn(0.0, 1.0)
			var nz := PackedFloat32Array()
			nz.resize(ln)
			var nsd := 0.0
			for j in ln:   # the noise through the FIR
				var acc := 0.0
				for q in fir.size():
					acc += float(fir[q]) * raw[j + fir.size() - 1 - q]
				nz[j] = acc
				nsd += acc * acc
			nsd = sqrt(nsd / ln)
			for j in ln:
				var ph := float(j) / ln * (L - 1)
				var i0 := int(ph)
				var c: float = lerpf(float(cyc[i0]), float(cyc[mini(i0 + 1, L - 1)]), ph - i0)
				var e: float = lerpf(float(env[int(float(j) / ln * 15.0)]), float(env[mini(int(float(j) / ln * 15.0) + 1, 15)]), fmod(float(j) / ln * 15.0, 1.0))
				out[at + j] = c * g + nz[j] / maxf(nsd, 1e-6) * rms * float(d.noise) * e
			at += ln
	var mid := out.slice(total, total * 2)
	var peak := 0.0
	for v in mid:
		peak = maxf(peak, absf(v))
	for i in mid.size():
		mid[i] = mid[i] / maxf(peak, 1e-6) * 0.8
	return mid


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


## The turbocharger: mostly a rush of air, a soft whistle down in it only when it's working hard.
static func _turbo(dur: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var air := _bp(_loop_noise(n, 0.0), 700.0, 2400.0)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		ph += TAU * (1650.0 + 25.0 * sin(TAU * 2.0 * t / dur * 4.0)) / RATE
		out[i] = sin(ph) * 0.025 + air[i] * 0.4
	return out


## The traction motors and their gears: a hum with its harmonics, a gear-mesh whine over it.
static func _traction(dur: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var grit := _bp(_loop_noise(n, 0.0), 600.0, 2500.0)
	for i in n:
		var t := float(i) / RATE
		out[i] = 0.3 * sin(TAU * 200.0 * t) + 0.18 * sin(TAU * 400.0 * t) + 0.1 * sin(TAU * 600.0 * t) + 0.06 * sin(TAU * 1200.0 * t) + grit[i] * 0.08
	return out


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


## Something dropped on a hard floor: three knocks off its body (round 200, 700 and 1800 Hz in
## the recordings), a click of contact, a short scrape of noise.
static func _thunk() -> PackedFloat32Array:
	var r := _r.randf_range(0.8, 1.25)
	var body := _modal([200.0 * r, 700.0 * r, 1800.0 * r, 2600.0 * r], [50.0, 45.0, 35.0, 60.0], [1.0, 0.45, 0.4, 0.12], 0.25)
	var click := _hp(_noise(0.006, 600.0, 0.0), 1500.0)
	return _add(_add(body, click, 0.6), _lp(_noise(0.06, 60.0, 0.4), 900.0), 0.3)


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


## A trumpet blown by someone who can't: a scoop up to the note, a wobble, a crack at the end.
static func _toot() -> PackedFloat32Array:
	var tone := _osc(1.05, func(t): return (205.0 + 28.0 * clampf(t / 0.12, 0.0, 1.0)) * (1.0 + 0.012 * sin(TAU * 5.5 * t)) * (1.18 if t > 0.86 else 1.0),
		func(t): return 0.55 * clampf(t / 0.06, 0.0, 1.0) * clampf((1.05 - t) / 0.12, 0.0, 1.0), "saw")
	return _add(_lp(tone, 3200.0), _bp(_noise(1.05, 1.0, 0.2), 900.0, 3000.0), 0.06)


## An old telephone bell: the clapper hammering two gongs twenty times a second, twice.
static func _phone_ring() -> PackedFloat32Array:
	var ring := _osc(1.6, func(t): return 1040.0, func(t): return (0.45 if fmod(t, 0.05) < 0.03 else 0.12) * (1.0 if t < 0.6 or (t > 0.9 and t < 1.5) else 0.0))
	return _add(ring, _osc(1.6, func(t): return 1470.0, func(t): return (0.3 if fmod(t + 0.025, 0.05) < 0.03 else 0.08) * (1.0 if t < 0.6 or (t > 0.9 and t < 1.5) else 0.0)), 1.0)


## A doll's pull-string "ma-ma": a thin voice through the two formants of "ah", closed for the m's.
static func _mama() -> PackedFloat32Array:
	var dur := 0.9
	var v := _osc(dur, func(t): return 420.0 - 60.0 * t + 8.0 * sin(TAU * 6.0 * t),
		func(t): return 0.6 * (0.15 + 0.85 * smoothstep(0.08, 0.16, fmod(t, 0.42))) * clampf((dur - t) / 0.1, 0.0, 1.0), "saw")
	return _add(_bp(v, 600.0, 900.0), _bp(v, 1000.0, 1400.0), 0.7)


## A toy truck pushed along: a little motor putting, revving up and settling.
static func _vroom() -> PackedFloat32Array:
	var v := _osc(1.2, func(t): return 70.0 + 90.0 * sin(PI * clampf(t / 1.2, 0.0, 1.0)), func(t): return 0.6 * (0.6 + 0.4 * sin(TAU * 24.0 * t)), "saw")
	return _lp(v, 1300.0)


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


## An old radio switched on: static, the dial swept through stations, a snatch of a tune.
static func _radio_tune() -> PackedFloat32Array:
	var hiss := _bp(_noise(1.8, 0.9, 0.1), 600.0, 4000.0)
	var notes := [523.0, 659.0, 784.0, 659.0, 587.0]
	var tune := _osc(1.8, func(t): return 0.0 if t < 0.7 else notes[clampi(int((t - 0.7) / 0.22), 0, notes.size() - 1)],
		func(t): return 0.0 if t < 0.7 else 0.35 * (0.7 + 0.3 * sin(TAU * 7.0 * t)))
	return _add(_bp(tune, 400.0, 2600.0), hiss, 0.35)


## A typewriter: a run of key strikes, then the bell at the end of the line.
static func _typewriter() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(1.3 * RATE))
	var at := 0.0
	for k in 8:
		out = _add(out, _shift(_add(_hp(_noise(0.03, 120.0, 0.2), 1500.0), _modal([380.0, 950.0], [60.0, 80.0], [0.4, 0.2], 0.06), 0.8), at), 0.9)
		at += _r.randf_range(0.07, 0.13)
	return _add(out, _shift(_modal([2650.0, 5300.0], [4.0, 7.0], [0.5, 0.15], 0.6), at + 0.08), 0.8)


## A kettle (or a teapot) coming to the boil: a breathy whistle swelling and rising.
static func _whistle() -> PackedFloat32Array:
	var w := _osc(1.5, func(t): return 1900.0 + 380.0 * clampf(t / 1.2, 0.0, 1.0) + 25.0 * sin(TAU * 9.0 * t),
		func(t): return 0.35 * clampf(t / 0.5, 0.0, 1.0) * clampf((1.5 - t) / 0.15, 0.0, 1.0))
	return _add(w, _bp(_noise(1.5, 0.3, 0.1), 1700.0, 2600.0), 0.25)


## Somebody talking through a helmet, heard from a few metres: syllables of a voice through vowel
## formants, muffled, the pitch wandering as speech does. (No words: just the sound of talk.)
static func _mumble() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(2.4 * RATE))
	var at := 0.05
	var vowels := [[700.0, 1150.0], [450.0, 1900.0], [500.0, 900.0], [350.0, 2200.0], [600.0, 1400.0]]
	while at < 2.2:
		var dur := _r.randf_range(0.09, 0.22)
		var f0 := _r.randf_range(105.0, 150.0)
		var fall := _r.randf_range(-15.0, 25.0)
		var v := _osc(dur, func(t): return f0 - fall * t / dur, func(t): return 0.6 * sin(PI * clampf(t / dur, 0.0, 1.0)), "saw")
		var vw: Array = vowels[_r.randi() % vowels.size()]
		var syl := _add(_bp(v, vw[0] * 0.8, vw[0] * 1.2), _bp(v, vw[1] * 0.85, vw[1] * 1.15), 0.6)
		out = _add(out, _shift(syl, at), 1.0)
		at += dur + (_r.randf_range(0.02, 0.07) if _r.randf() < 0.8 else _r.randf_range(0.18, 0.35))   # (now and then a pause)
	return _lp(out, 1600.0)


## A whoopee cushion: a low buzzy blat, wobbling, sputtering out at the end.
static func _fart() -> PackedFloat32Array:
	var dur := _r.randf_range(0.6, 1.0)
	var f0 := _r.randf_range(80.0, 120.0)
	var v := _osc(dur, func(t): return f0 * (1.0 + 0.25 * sin(TAU * 3.0 * t) - 0.3 * t / dur) * (1.0 + 0.08 * sin(TAU * 37.0 * t)),
		func(t): return 0.7 * clampf(t / 0.03, 0.0, 1.0) * (1.0 if t < dur * 0.75 else (0.6 if fmod(t, 0.05) < 0.025 else 0.1)), "saw")
	return _add(_bp(v, 70.0, 900.0), _lp(_noise(dur, 2.0, 0.6), 500.0), 0.15)


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
