# The line: the country the train runs through between stops.
#
# The train never moves. The line, the stop it's leaving and the stop it's making for all slide
# past it along -x: `s` is how far the train has come in line metres (x along the line, the train's
# own x = 0 at s = 0). The line is built in 48 m chunks a little way ahead of the train and freed a
# way behind it, each chunk from its own dice (seeded by the stop it belongs to, so a crew sees the
# same line), and every station sits in the same kind of valley:
#
#   ... tunnel ] approach (open line) [ station, ±100 m ] departure (open line) [ tunnel ...
#
# A trip (ride): pull out, run the open line, into the tunnel; once you're deep in it (the smoke in
# there hides both ends) the stop behind is freed and the next one is built (main._journey_build:
# that's where the frame stalls, in the dark); out of the tunnel into the morning, along the
# approach, past the signals, and brake to a stand at the platform. Then everything is moved back
# so the new stop sits at x = 0 again (no drifting far from the origin).
# The checkpoint has its own tunnels (checkpoint.gd): its bores lead straight into the line's.
extends Node3D

const A = preload("res://src/art.gd")
const B = preload("res://src/build.gd")
const P = preload("res://src/props.gd")
const CP = preload("res://src/checkpoint.gd")
const Data = preload("res://src/data.gd")
const Sfx = preload("res://src/sfx.gd")
const Merge = preload("res://src/merge.gd")

const CHUNK := 48.0
const AHEAD := 700.0      # built this far in front of the train
const BEHIND := 520.0     # kept this far behind it
const HALF := 100.0       # a station's own ground: ±100 m round it (level.gd)
const LEG := 260.0        # open line between a station's edge and a tunnel
const TUNNEL := 240.0
const CP_BORE := 202.0    # the checkpoint's bores end this far out (checkpoint.X_EDGE + 30)
const BORE_IN := 30.0     # a portal's own bore (checkpoint._portal)
const ZS := [0.0, 2.0, 4.0, 6.0, 8.0, 11.0, 14.0, 18.0, 22.0, 28.0, 36.0, 44.0, 52.0, 64.0, 80.0, 100.0, 124.0, 156.0, 196.0, 248.0, 320.0, 420.0, 560.0]
const SPEED := 24.0       # m/s cruising (about 85 km/h)
const ACCEL := 1.5        # m/s² pulling away
const BRAKE := 1.35       # m/s² stopping
const SWAP_IN := 70.0     # how far into the tunnel the stops are swapped
const RAIL := Color(0.7, 0.68, 0.65)
const SLEEPER := Color(0.55, 0.5, 0.45)

signal arrived

var main
var s := 0.0              # line metres the train has come (its nose... its x = 0, at line x = s)
var v := 0.0              # m/s, along the line
var dark := 0.0           # 0..1: how deep in a tunnel the camera is (main dims the sky and fills the bore with smoke)
var riding := false
var odo := 0.0            # line metres since the start of the run, at x = 0 (the kilometre posts)
var _segs: Array = []     # {kind: "open"/"tunnel"/"station", a, b, ...}, in order along the line
var _chunks := {}         # chunk index -> Node3D
var _grid := 0.0          # line x of chunk 0's start
var _dep: Node3D          # the stop we're leaving (slides away), and the one we're making for
var _arr: Node3D
var _dep_x := 0.0
var _arr_x := 0.0
var _lamps: Array = []    # [node, line x, on colour, after colour] signal lenses that drop to danger behind the train
var _bells: Array = []    # [line x, lamps [a, b], AudioStreamPlayer3D] level crossings
var _bell_t := 0.0
var _noise := FastNoiseLite.new()
var _hills := FastNoiseLite.new()
var _bank := FastNoiseLite.new()
var _roar: AudioStreamPlayer
var _rush: AudioStreamPlayer
var _horned := {}         # one-off horn calls made this trip
var _chunk_x := 0.0       # line x of the chunk being built


func _ready() -> void:
	_noise.seed = 4117
	_noise.frequency = 0.018
	_noise.fractal_octaves = 3
	_hills.seed = 911
	_hills.frequency = 0.0035
	_hills.fractal_octaves = 4
	_bank.seed = 3301
	_bank.frequency = 0.004
	_bank.fractal_octaves = 2
	for k in 2:   # wheels on rail (a deep roar, louder in a tunnel) and the air rushing past
		var p := AudioStreamPlayer.new()
		p.stream = Sfx.stream("rumble" if k == 0 else "wind")
		p.volume_db = -80.0
		p.bus = "World" if AudioServer.get_bus_index("World") >= 0 else "Master"
		add_child(p)
		if k == 0:
			_roar = p
		else:
			_rush = p


# --- the stops ----------------------------------------------------------------------------------------

## A stop has just been built where the train stands (start of the run, a saved run, a crewmate
## joining, the playground): lay the line round it, all at once.
func settle(level: Node3D) -> void:
	_clear()
	if level == null or level.info.get("theme", "") == "CHECKPOINT":
		return
	_dep = level
	_dep_x = 0.0
	var seed: int = main.level_seed
	var arctic: bool = level.info.get("biome", "") == "ARCTIC"
	_segs = [
		{"kind": "tunnel", "a": -HALF - LEG - TUNNEL, "b": -HALF - LEG, "entry": true, "exit": "portal", "arctic": arctic, "next_arctic": arctic, "seed": seed, "seed_in": 0, "seed_out": seed},
		_open(-HALF - LEG, -HALF, seed, arctic, level, 0.0, false, str(level.info.get("letter", ""))),
		{"kind": "station", "a": -HALF, "b": HALF, "home": level, "hx": 0.0, "arctic": arctic, "seed": seed},
		_open(HALF, HALF + LEG, seed + 1, arctic, level, 0.0, true),
		{"kind": "tunnel", "a": HALF + LEG, "b": HALF + LEG + TUNNEL, "entry": true, "exit": "", "arctic": arctic, "next_arctic": arctic, "seed": seed + 2, "seed_in": seed + 1, "seed_out": 0},
	]
	for k in range(_index(-BEHIND), _index(AHEAD) + 1):
		if _ready_chunk(k):
			_build_chunk(k)


## An open stretch: what lies along it is decided here (so it's the same whenever it's built).
## `leaving`: the stretch out of a station toward the tunnel (else the approach in from one).
func _open(a: float, b: float, seed: int, arctic: bool, home: Node3D, hx: float, leaving: bool, letter := "") -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = hash([seed, "open", leaving])
	var o := {"kind": "open", "a": a, "b": b, "seed": seed, "arctic": arctic, "home": home, "hx": hx, "leaving": leaving,
		"signals": [], "boards": [], "crossing": INF, "loop": Vector2.INF, "letter": letter}
	if leaving:
		o.signals.append([a + 26.0, "green"])                      # the starter: you may go
		o.boards.append([b - 150.0, "W"])                          # whistle for the tunnel
	else:
		o.signals.append([a + 70.0, "yellow"])                     # the distant: the next one's at stop...
		o.signals.append([b - 34.0, "green"])                      # ...the home signal, clear into the platform
		o.boards.append([b - 190.0, "W"])
		o.boards.append([b - 120.0, "STATION"])
		if r.randf() < 0.55:                                       # a freight waiting in the loop for us to pass
			o.loop = Vector2(a + 34.0, a + 34.0 + r.randf_range(170.0, 200.0))
	if o.loop == Vector2.INF and r.randf() < 0.6:                  # a road over the line
		o.crossing = snappedf(r.randf_range(a + 60.0, b - 70.0), 4.0)
	return o


## The trip to `dest` (main._travel awaits it). main._journey_build(dest, seed) is called in the
## tunnel, and returns the new stop.
func ride(dest: Dictionary, seed: int) -> void:
	var from_cp: bool = main.at_checkpoint
	var to_cp: bool = dest.theme == "CHECKPOINT"
	_dep = main.level
	_dep_x = 0.0
	_arr = null
	_horned.clear()
	var t: Dictionary
	if from_cp:
		_clear()
		_dep = main.level
		t = {"kind": "tunnel", "a": CP_BORE, "b": CP_BORE + TUNNEL, "entry": false, "exit": "", "arctic": false, "seed": seed, "seed_in": 0, "seed_out": 0}
		_segs.append(t)
		for n in get_tree().get_nodes_in_group("bore_plug"):   # (the checkpoint's bores lead on into ours)
			n.visible = false
	else:
		t = _segs.filter(func(g): return g.kind == "tunnel" and g.a > 0.0)[0]
	t.exit = "cp" if to_cp else "portal"
	t.next_arctic = dest.get("biome", "") == "ARCTIC"
	t.seed_out = seed
	_arr_x = t.b + CP_BORE if to_cp else t.b + LEG + HALF
	if not to_cp:
		_segs.append(_open(t.b, _arr_x - HALF, seed, t.next_arctic, null, _arr_x, false, str(dest.get("letter", ""))))
	riding = true
	v = 0.0
	var swapped := false
	var clock := 0.0
	var leaving_hours: float = main.hours
	var pace := Data.pace()
	_gates(_dep, false)   # (the stop's walls across the line would sweep everyone off the train)
	_sound(0.0)
	Sfx.play(main.train, "air_release", main.train.to_global(Vector3(10.0, 0.6, 0.0)), -8.0, 0.8)   # brakes off
	_slack()
	while true:
		var dt := minf(get_process_delta_time(), 0.05) / pace   # (a stalled frame doesn't jump the world on)
		clock += dt
		var left := _arr_x - s
		var target := minf(SPEED, sqrt(2.0 * BRAKE * maxf(left, 0.0)))
		target = minf(target, left * 0.9 + 0.12)    # (the last metres: ease to a stand, don't slam)
		var acc := ACCEL * clampf(clock / 2.5, 0.15, 1.0)   # the slack takes up, then it leans into it
		if target > v:
			v = minf(v + acc * dt, target)
		else:
			v = target
		s = minf(s + v * dt, _arr_x)
		_place()
		_events(t, to_cp)
		if not swapped and s >= t.a + (SWAP_IN if t.entry else SWAP_IN - BORE_IN):
			swapped = true
			main.hours = 6.85   # (the night goes by in the dark; we come out into the early morning)
			_arr = main._journey_build(dest, seed)
			_arr.position.x = _arr_x - s
			_gates(_arr, false)
			if _dep != null and is_instance_valid(_dep):
				_dep.queue_free()
			_dep = null
			for g in _segs:
				if g.kind == "open" and g.home == null:
					g.home = _arr
			if not to_cp:
				var arctic: bool = t.next_arctic
				_segs.append({"kind": "station", "a": _arr_x - HALF, "b": _arr_x + HALF, "home": _arr, "hx": _arr_x, "arctic": arctic, "seed": seed})
				_segs.append(_open(_arr_x + HALF, _arr_x + HALF + LEG, seed + 1, arctic, _arr, _arr_x, true))
				_segs.append({"kind": "tunnel", "a": _arr_x + HALF + LEG, "b": _arr_x + HALF + LEG + TUNNEL, "entry": true, "exit": "", "arctic": arctic, "next_arctic": arctic, "seed": seed + 2, "seed_in": seed + 1, "seed_out": 0})
			else:
				for n in get_tree().get_nodes_in_group("bore_plug"):
					n.visible = false
		if swapped and not to_cp:   # the sun comes up as we run in
			main.hours = lerpf(6.85, 8.0, clampf((s - t.b + 80.0) / (_arr_x - t.b + 80.0), 0.0, 1.0))
		elif not swapped:
			main.hours = leaving_hours
		main._arriving = swapped and s > _arr_x - HALF - 24.0
		_sound(dt)
		if s >= _arr_x - 0.02 or (v < 0.02 and left < 0.4):
			break
		await get_tree().process_frame
	v = 0.0
	s = _arr_x
	_place()
	_sound(0.0)
	riding = false
	_gates(_arr, true)
	_rebase(_arr_x)
	arrived.emit()


## A stop's invisible walls across the line (its ends: you're kept in, the train isn't), off or on.
func _gates(level: Node3D, on: bool) -> void:
	if level == null or not is_instance_valid(level):
		return
	for n in get_tree().get_nodes_in_group("across_line"):
		if level.is_ancestor_of(n):
			for c in n.get_children():
				if c is CollisionShape3D:
					c.set_deferred("disabled", not on)


## Nothing's built until it's known what it joins (a stop not built yet, a tunnel that doesn't
## know where it comes out).
func _ready_chunk(k: int) -> bool:
	var c0 := _grid + k * CHUNK
	var c1 := c0 + CHUNK
	if _segs.is_empty() or c0 >= float(_segs[-1].b) or c1 <= float(_segs[0].a):
		return false
	for g in _segs:
		if g.b <= c0 or g.a >= c1:
			continue
		if g.kind in ["open", "station"] and g.home == null:
			return false
		if g.kind == "tunnel" and g.exit == "" and c1 > (g.a + g.b) / 2.0 - 10.0:
			return false
	return c1 <= float(_segs[-1].b) + CHUNK


func _index(x: float) -> int:
	return int(floor((x - _grid) / CHUNK))


## Everything moves back by `by`: the stop we've arrived at is at x = 0 again.
func _rebase(by: float) -> void:
	s -= by
	odo += by
	_grid -= by
	for k in _chunks:
		_chunks[k].position.x -= by
	for g in _segs:
		g.a -= by
		g.b -= by
		if g.has("hx"):
			g.hx -= by
		for list in ["signals", "boards"]:
			if g.has(list):
				for f in g[list]:
					f[0] -= by
		if g.has("crossing"):
			g.crossing -= by
		if g.has("loop") and g.loop != Vector2.INF:
			g.loop -= Vector2(by, by)
	for l in _lamps:
		l[1] -= by
	for b in _bells:
		b[0] -= by
	_dep = _arr
	_dep_x = 0.0
	_arr = null
	_segs = _segs.filter(func(g): return g.b > -BEHIND - 50.0)
	_place()


func _clear() -> void:
	for k in _chunks:
		_chunks[k].queue_free()
	_chunks.clear()
	_segs.clear()
	_lamps.clear()
	_bells.clear()
	s = 0.0
	_grid = 0.0
	position.x = 0.0


## Every frame: the line and both stops where the train's got to; chunks made and dropped.
func _place() -> void:
	position.x = -s
	if _dep != null and is_instance_valid(_dep):
		_dep.position.x = _dep_x - s
	if _arr != null and is_instance_valid(_arr):
		_arr.position.x = _arr_x - s


func _process(delta: float) -> void:
	if _segs.is_empty():
		return
	# Chunks: one built a frame at most (they're cheap, but not free), the far ones behind dropped.
	var want := _index(s + AHEAD)
	for k in range(_index(s - 60.0), want + 1):
		if not _chunks.has(k) and _ready_chunk(k):
			_build_chunk(k)
			break
	for k in _chunks.keys():
		if _grid + (k + 1) * CHUNK < s - BEHIND:
			_chunks[k].queue_free()
			_chunks.erase(k)
	# How deep in a bore the camera is: 0 at the mouth, 1 some way in.
	var cam := get_viewport().get_camera_3d()
	var cx: float = (cam.global_position.x if cam else 0.0) + s
	var d := 0.0
	for g in _segs:
		if g.kind != "tunnel":
			continue
		var a0: float = g.a - (0.0 if g.entry else BORE_IN)   # (a checkpoint's own bore leads in)
		var b0: float = g.b + (BORE_IN if g.exit == "cp" else 0.0)
		if cx > a0 - 4.0 and cx < b0 + 4.0:
			var into: float = cx - a0
			var out: float = b0 - cx
			d = clampf(minf(into, out) / 34.0, 0.0, 1.0)
	if main != null and main.player != null and main.player.global_position.y < main.UNDERGROUND_Y:
		d = 0.0
	dark = move_toward(dark, d, delta * 3.0)
	# Signals drop to danger once the train's by; crossings ring and flash while it's near.
	for l in _lamps:
		if is_instance_valid(l[0]):
			var behind: bool = s > l[1] + 6.0
			l[0].material_override = A.mat("cream", l[3] if behind else l[2], 1.0, 4.0)
	_bell_t -= delta
	var t := Time.get_ticks_msec() / 1000.0
	for b in _bells:
		var near: bool = absf(b[0] - s) < 260.0 and b[0] > s - 40.0
		var lamps: Array = b[1]
		for i in lamps.size():
			if is_instance_valid(lamps[i]):
				lamps[i].visible = near and (int(t * 1.6) + i) % 2 == 0
		if near and _bell_t <= 0.0 and is_instance_valid(b[2]):
			b[2].play()
	if _bell_t <= 0.0:
		_bell_t = 0.62


# --- on the way -------------------------------------------------------------------------------------

## The engine's horn at the places it calls (whistle boards), brakes going on, the stop.
func _events(t: Dictionary, to_cp: bool) -> void:
	var tr = main.train
	var calls := [[t.a - 150.0 if t.entry else -INF, "tunnel"], [_arr_x - HALF - 190.0 if not to_cp else -INF, "station"]]
	for c in calls:
		if c[0] > -INF and s > c[0] and not _horned.has(c[1]):
			_horned[c[1]] = true
			Sfx.play(tr, "horn", tr.to_global(Vector3(16.5, 4.2, 0)), -12.0)
	var stopping: float = _arr_x - SPEED * SPEED / (2.0 * BRAKE)
	if s > stopping and not _horned.has("brake"):
		_horned["brake"] = true
		Sfx.play(tr, "air_release", tr.to_global(Vector3(-6.0, 0.6, 0.0)), -14.0, 0.7)
	if v < 4.5 and s > stopping and not _horned.has("squeal"):   # the shoes bite as it slows
		_horned["squeal"] = true
		for bx in [-11.0, -4.9, 4.9, 13.0]:
			Sfx.play(tr, "screech", tr.to_global(Vector3(bx, 0.5, 1.2)), -20.0, randf_range(0.55, 0.7))
	if v < 0.2 and s > _arr_x - 1.0 and not _horned.has("stand"):
		_horned["stand"] = true
		Sfx.play(tr, "air_release", tr.to_global(Vector3(10.0, 0.6, 0.0)), -6.0, 1.0)
		_slack(true)


## The couplings taking up (or running in): a clank down the train, car by car, and a nudge.
func _slack(stopping := false) -> void:
	var tr = main.train
	var xs := [14.0, 7.8, -6.2, -15.0] if not stopping else [-15.0, -6.2, 7.8, 14.0]
	for x in xs:
		if not is_inside_tree():
			return
		Sfx.play(tr, "clank", tr.to_global(Vector3(x, 0.9, 0)), -13.0, randf_range(0.6, 0.75))
		if main.player.in_train:
			main.player.shake(0.006)
		await get_tree().create_timer(0.18 * Data.pace(), false).timeout


## Wheels and wind: louder with speed, the roar much louder (and the wind gone) in a tunnel.
func _sound(_dt: float) -> void:
	var f := clampf(v / SPEED, 0.0, 1.0)
	var inside: bool = main.player.in_train
	var roar := lerpf(-46.0, -24.0, f) + dark * 10.0 - (5.0 if inside else 0.0)
	var rush := lerpf(-50.0, -20.0, f) - (14.0 if inside else 0.0) - dark * 18.0
	for pair in [[_roar, roar], [_rush, rush]]:
		var p: AudioStreamPlayer = pair[0]
		if f < 0.01:
			p.stop()
			continue
		if not p.playing:
			p.play(randf() * 3.0)
		p.volume_db = pair[1]
		p.pitch_scale = lerpf(0.7, 1.15, f)


# --- the ground -------------------------------------------------------------------------------------

## Height of the ground at line x, z: dunes, hills further off, the line on banks and in cuttings,
## mountains over the tunnels, and each station's own ground round it.
func height(x: float, z: float) -> float:
	var az := absf(z)
	var dune := _noise.get_noise_2d(x, z) * 3.0 + _noise.get_noise_2d(x * 3.7, z * 3.7) * 0.35
	var h := dune * smoothstep(8.5, 18.0, az)
	h += _hills.get_noise_2d(x, z) * 26.0 * smoothstep(70.0, 320.0, az)
	var bank := _bank.get_noise_1d(x)   # mostly level going; now and then a cutting, or a bank over a dip
	bank = (maxf(bank - 0.22, 0.0) - maxf(-bank - 0.22, 0.0)) * 22.0
	h += bank * smoothstep(5.0, 26.0, az) * smoothstep(0.0, 120.0, _clear_of_mountains(x))
	for g in _segs:
		if g.kind != "tunnel":
			continue
		var m := 1.0
		if g.entry:
			m *= smoothstep(g.a - 190.0, g.a + 8.0, x)
		if g.exit == "portal":
			m *= 1.0 - smoothstep(g.b - 8.0, g.b + 190.0, x)
		if m > 0.0:
			h += m * (46.0 + _hills.get_noise_2d(x * 2.0, z * 2.0) * 22.0) * smoothstep(9.0, 46.0, az)
	for g in _segs:
		if g.kind == "station" and g.home != null and is_instance_valid(g.home):
			var d := maxf(maxf(absf(x - g.hx) - HALF, az - HALF), 0.0)
			if d < 170.0:
				h = lerpf(g.home.ground_y(x - g.hx, z), h, smoothstep(6.0, 170.0, d))
	return h


## Metres from x to the nearest tunnel mouth (banks and cuttings fade out near them).
func _clear_of_mountains(x: float) -> float:
	var d := INF
	for g in _segs:
		if g.kind == "tunnel":
			d = minf(d, maxf(maxf(g.a - x, x - g.b), 0.0))
	return d


func _station_near(x: float, z: float, r: float) -> bool:
	for g in _segs:
		if g.kind == "station" and Vector2(x - g.hx, z).length() < r:
			return true
	return false


func _in_footprint(x: float, z: float) -> bool:
	for g in _segs:
		if g.kind == "station" and absf(x - g.hx) < HALF - 0.01 and absf(z) < HALF - 0.01:
			return true
	return false


func _seg_at(x: float) -> Dictionary:
	for g in _segs:
		if x >= g.a and x < g.b:
			return g
	return {}


func _arctic_at(x: float) -> bool:
	var g := _seg_at(x)
	if g.is_empty():
		return false
	if g.kind == "tunnel":
		return g.arctic if x < (g.a + g.b) / 2.0 else g.get("next_arctic", g.arctic)
	return g.arctic


# --- building a chunk ---------------------------------------------------------------------------------

func _build_chunk(k: int) -> void:
	var c0 := _grid + k * CHUNK
	var c1 := c0 + CHUNK
	var ch := Node3D.new()
	ch.name = "Line%d" % k
	add_child(ch)
	ch.position.x = c0
	_chunks[k] = ch
	_chunk_x = c0
	var r := RandomNumberGenerator.new()
	var g0 := _seg_at(c0 + 1.0)
	r.seed = hash([g0.get("seed", 0), int(round(odo + c0))])
	_terrain(ch, c0, c1)
	for g in _segs:
		if g.b <= c0 or g.a >= c1:
			continue
		A.snow_cover = g.arctic
		match g.kind:
			"open": _open_chunk(ch, g, maxf(c0, g.a), minf(c1, g.b), c0, r)
			"tunnel": _tunnel_chunk(ch, g, maxf(c0, g.a), minf(c1, g.b), c0, r)
			"station": _station_wings(ch, g, c0, c1, r)
	A.snow_cover = false
	Merge.bake(ch, CHUNK, false, 1400.0)


## The ground of a chunk: a height field from the track out to the horizon, rows closer together
## near the track; sand or snow on the flat, bare rock where it's steep. Nothing under a station's
## own ground or over a tunnel's bore. Solid near the line (you can step off onto it).
func _terrain(ch: Node3D, c0: float, c1: float) -> void:
	var arctic := _arctic_at((c0 + c1) / 2.0)
	var ground := SurfaceTool.new()
	var solid := SurfaceTool.new()
	for st in [ground, solid]:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var zs: Array[float] = []
	for z in ZS:
		zs.append(z)
		if z > 0.0:
			zs.push_front(-z)
	var xs: Array[float] = []
	var x := c0
	while x <= c1 + 0.01:
		xs.append(x)
		x += 4.0
	var hs := []   # heights on the grid, and the ground's normal there
	var ns := []
	for xi in xs:
		var row := PackedFloat32Array()
		var nrow := PackedVector3Array()
		for z in zs:
			row.append(height(xi, z))
			nrow.append(_normal(xi, z))
		hs.append(row)
		ns.append(nrow)
	var n_tris := 0
	var n_solid := 0
	for i in xs.size() - 1:
		for j in zs.size() - 1:
			var xa: float = xs[i]
			var xb: float = xs[i + 1]
			var za: float = zs[j]
			var zb: float = zs[j + 1]
			var mx := (xa + xb) / 2.0
			var mz := (za + zb) / 2.0
			if _in_footprint(mx, mz) or _over_bore(mx, mz):
				continue
			var p := [Vector3(xa - c0, hs[i][j], za), Vector3(xb - c0, hs[i + 1][j], za), Vector3(xb - c0, hs[i + 1][j + 1], zb), Vector3(xa - c0, hs[i][j + 1], zb)]
			var pn := [ns[i][j], ns[i + 1][j], ns[i + 1][j + 1], ns[i][j + 1]]
			for tri in [[0, 1, 2], [0, 2, 3]]:
				n_tris += 1
				for q in tri:
					ground.set_normal(pn[q])
					ground.add_vertex(p[q])
				if absf(mz) < 60.0:
					n_solid += 1
					for q in tri:
						solid.add_vertex(p[q])
	if n_tris > 0:
		var mi := MeshInstance3D.new()
		mi.mesh = ground.commit()
		mi.material_override = _ground_mat(arctic)
		# The texture lines up with the nearest station's ground (its own mesh is mapped from its centre).
		var hx := 0.0
		var best := INF
		for g in _segs:
			if g.kind == "station" and absf(g.hx - c0) < best:
				best = absf(g.hx - c0)
				hx = g.hx
		mi.set_instance_shader_parameter("shift", fposmod(c0 - hx, 12.0))
		Merge.live(mi)   # (its own mesh already: one draw)
		ch.add_child(mi)
	if n_solid > 0:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		cs.shape = solid.commit().create_trimesh_shape()
		body.add_child(cs)
		ch.add_child(body)


## The line's ground: sand (or snow) on the level, giving way to bare rock where it steepens, the
## edge broken up pixel by pixel. Mapped like art.gd's materials (triplanar, 3 m tiles, nearest).
static var _mats := {}
const GROUND := """shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
uniform sampler2D soft : source_color, filter_nearest_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock : source_color, filter_nearest_mipmap_anisotropic, repeat_enable;
uniform vec3 rock_tint = vec3(1.0);
instance uniform float shift = 0.0;
varying vec3 p;
varying vec3 n;
void vertex() {
	p = VERTEX + vec3(shift, 0.0, 0.0);
	n = NORMAL;
}
vec3 tri(sampler2D t, vec3 q, vec3 w) {
	q *= vec3(1.0, -1.0, 1.0);
	return texture(t, q.xy).rgb * w.z + texture(t, q.xz).rgb * w.y + texture(t, q.zy * vec2(-1.0, 1.0)).rgb * w.x;
}
float hash(vec2 c) { return fract(sin(dot(c, vec2(127.1, 311.7))) * 43758.5453); }
void fragment() {
	vec3 w = abs(n);
	w /= dot(w, vec3(1.0));
	vec3 a = tri(soft, p / 3.0, w);
	vec3 b = tri(rock, p / 6.0, w) * rock_tint;
	float slope = 1.0 - n.y;
	float dither = hash(floor(p.xz * 64.0 / 3.0)) * 0.08 + hash(floor(p.xz / 2.0)) * 0.05;
	float k = step(0.14 - dither, slope);
	ALBEDO = mix(a, b, k);
	ROUGHNESS = 0.92;
}
"""


static func _ground_mat(arctic: bool) -> ShaderMaterial:
	if not _mats.has(arctic):
		var m := ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = GROUND
		m.shader = sh
		m.set_shader_parameter("soft", A.texture("snow" if arctic else "sand"))
		m.set_shader_parameter("rock", A.texture("stone" if arctic else "mesa"))
		m.set_shader_parameter("rock_tint", Color(0.72, 0.74, 0.8) if arctic else Color(0.74, 0.56, 0.44))
		_mats[arctic] = m
	return _mats[arctic]


func _normal(x: float, z: float) -> Vector3:
	var e := 1.5
	return Vector3(height(x - e, z) - height(x + e, z), 2.0 * e, height(x, z - e) - height(x, z + e)).normalized()


func _over_bore(x: float, z: float) -> bool:
	if absf(z) > 14.0:
		return false
	for g in _segs:
		if g.kind == "tunnel" and x > g.a - 2.0 and x < g.b + 2.0:
			return true
	return false


## The track on its ballast, as a station's (rails 0.12 high, sleepers every 2 m on the odd metre).
func _track(ch: Node3D, xa: float, xb: float, c0: float) -> void:
	var ln := xb - xa
	if ln < 0.05:
		return
	var mid := (xa + xb) / 2.0 - c0
	A.box(ch, Vector3(ln, 0.1, 3.0), Vector3(mid, -0.02, 0), "gravel", Color(0.66, 0.62, 0.58), true, 1.5)
	for sd in [-1.0, 1.0]:   # the shoulders, sloping off into the ground
		A.box(ch, Vector3(ln, 0.06, 0.9), Vector3(mid, -0.05, sd * 1.82), "gravel", Color(0.6, 0.56, 0.52), false, 1.5, Vector3(-sd * 0.12, 0, 0))
	for z in [-0.75, 0.75]:
		A.box(ch, Vector3(ln, 0.12, 0.1), Vector3(mid, 0.06, z), "metal", RAIL, false)
	var x := ceilf((xa - 1.0) / 2.0) * 2.0 + 1.0
	while x < xb:
		A.box(ch, Vector3(0.25, 0.08, 2.4), Vector3(x - c0, 0.02, 0), "wood", SLEEPER, false, 1.0)
		x += 2.0


# --- open line ------------------------------------------------------------------------------------------

func _open_chunk(ch: Node3D, g: Dictionary, xa: float, xb: float, c0: float, r: RandomNumberGenerator) -> void:
	_track(ch, xa, xb, c0)
	# Telegraph poles on from the station's last (level.gd: every 18 m to ±90, at z = -5), every 36 m.
	var hx: float = g.hx
	var dir := 1.0 if g.leaving else -1.0
	var k := 1
	while true:
		var px := hx + dir * (90.0 + 36.0 * k)
		if (dir > 0.0 and px > g.b - 24.0) or (dir < 0.0 and px < g.a + 24.0):
			break
		if px >= xa and px < xb:
			var at := Vector3(px - c0, 0.0, -5.0)
			A.telephone_pole(ch, at)
			var back := px - dir * 36.0   # to the one nearer the station
			for zz in [-0.7, 0.7]:
				_wire(ch, Vector3(px - c0, 6.5, -5.0 + zz), Vector3(back - c0, 6.5, -5.0 + zz))
		k += 1
	for f in g.signals:
		if f[0] >= xa and f[0] < xb:
			_signal(ch, f[0], c0, f[1])
	for f in g.boards:
		if f[0] >= xa and f[0] < xb:
			_board(ch, f[0], c0, f[1], g)
	var km := ceilf((odo + xa) / 200.0) * 200.0 - odo   # kilometre posts every 200 m
	while km < xb:
		if not _station_near(km, 0.0, HALF + 10.0):
			_milepost(ch, km, c0)
		km += 200.0
	if g.crossing >= xa and g.crossing < xb:
		_crossing(ch, g.crossing, c0, r, g.arctic)
	if g.loop != Vector2.INF and g.loop.x >= xa and g.loop.x < xb:
		_loop(ch, g.loop, c0, r, g.arctic)
	_scenery(ch, g, xa, xb, c0, r)


## Things along the line: near it (dead trees, rocks, wrecks, sheds, fences), further off (big rocks,
## houses, a water tower or windmill, pumpjacks), on the skyline (spires, mesas). Kept off the line,
## clear of the stations (their own things are there) and out of the cuttings into the tunnels.
func _scenery(ch: Node3D, g: Dictionary, xa: float, xb: float, c0: float, r: RandomNumberGenerator) -> void:
	var arctic: bool = g.arctic
	var rock := Color(0.85, 0.85, 0.95) if arctic else Color.WHITE
	var span := (xb - xa) / CHUNK
	var spots := func(n: float, z0: float, z1: float, keep: float) -> Array:
		var out := []
		var count := int(n * span) + (1 if r.randf() < fmod(n * span, 1.0) else 0)
		for i in count:
			var x := r.randf_range(xa, xb)
			var z := r.randf_range(z0, z1) * (1.0 if r.randf() < 0.5 else -1.0)
			if _station_near(x, z, keep) or (_clear_of_mountains(x) < 60.0 and absf(z) < 90.0):
				continue
			if absf(x - g.crossing) < 14.0 and absf(z) < 160.0:
				continue
			if g.loop != Vector2.INF and x > g.loop.x - 30.0 and x < g.loop.y + 30.0 and z > 0.0 and z < 18.0:
				continue
			out.append(Vector3(x - c0, height(x, z), z))
		return out
	# Near.
	for p in spots.call(1.2 if not arctic else 0.4, 13.0, 40.0, HALF + 16.0):
		A.dead_tree(ch, p - Vector3(0, 0.2, 0), r)
	for p in spots.call(2.4, 12.0, 45.0, HALF + 16.0):
		var sz := r.randf_range(0.8, 3.2)
		P.boulder(ch, p + Vector3(0, sz * 0.2, 0), Vector3(sz, sz * r.randf_range(0.45, 0.8), sz * r.randf_range(0.7, 1.2)), r, rock, false)
	for p in spots.call(0.16, 16.0, 60.0, HALF + 30.0):
		P.car_wreck(ch, p, r.randf() * TAU, r)
	for p in spots.call(0.16, 16.0, 70.0, HALF + 30.0):
		P.ruin_wall(ch, p, r.randf() * TAU, r)
	for p in spots.call(0.08, 22.0, 70.0, HALF + 40.0):
		P.tin_shed(ch, p, r.randf() * TAU, r)
	for p in spots.call(0.1, 20.0, 60.0, HALF + 40.0):
		P.scrap_heap(ch, p, r)
	if r.randf() < 0.18 * span:   # a fence along the line, sagging and broken
		var x := r.randf_range(xa, xb)
		var z := r.randf_range(11.0, 16.0) * (1.0 if r.randf() < 0.5 else -1.0)
		if not _station_near(x, z, HALF + 10.0) and _clear_of_mountains(x) > 80.0:
			var a := Vector3(x - c0, 0, z)
			P.fence(ch, a, a + Vector3(r.randf_range(14.0, 30.0), 0, r.randf_range(-1.0, 1.0)), r, func(fx, fz): return height(fx + c0, fz))
	if arctic:   # stands of spruce, and snow thrown up by the plough along the line
		for c in spots.call(0.8, 24.0, 150.0, HALF + 30.0):
			for t in r.randi_range(4, 9):
				var q: Vector3 = c + Vector3(r.randf_range(-9, 9), 0, r.randf_range(-9, 9))
				if absf(q.z) < 14.0:
					continue
				q.y = height(q.x + c0, q.z) - 0.2
				A.pine(ch, q, r)
		var x := ceilf(xa / 9.0) * 9.0
		while x < xb:
			for sd in [-1.0, 1.0]:
				_drift(ch, Vector3(x - c0 + r.randf_range(-2, 2), 0, sd * r.randf_range(2.7, 3.2)), r.randf_range(2.5, 4.0), 0.5, r)
			x += 9.0
		for p in spots.call(1.2, 14.0, 60.0, HALF + 16.0):
			_drift(ch, p, r.randf_range(2.0, 5.5), 0.0, r)
	# Further off.
	for p in spots.call(1.4, 45.0, 150.0, HALF + 60.0):
		var sz := r.randf_range(2.5, 7.0)
		P.boulder(ch, p + Vector3(0, sz * 0.15, 0), Vector3(sz, sz * r.randf_range(0.4, 0.75), sz * r.randf_range(0.7, 1.2)), r, rock.darkened(0.05), false)
	for p in spots.call(0.12, 40.0, 120.0, HALF + 60.0):
		A.wood_house(ch, p, r.randf() * TAU, r)
	for p in spots.call(0.05, 30.0, 90.0, HALF + 60.0):
		P.water_tower(ch, p)
	for p in spots.call(0.07, 40.0, 140.0, HALF + 60.0):
		P.windmill(ch, p, r)
	for p in spots.call(0.05, 40.0, 140.0, HALF + 60.0):
		P.pumpjack(ch, p, r.randf() * TAU)
	if not arctic:
		for p in spots.call(1.0, 45.0, 140.0, HALF + 60.0):
			A.dead_tree(ch, p - Vector3(0, 0.2, 0), r)
	# The skyline.
	for p in spots.call(0.45, 90.0, 260.0, HALF + 140.0):
		if r.randf() < 0.22:
			P.rock_arch(ch, p - Vector3(0, 1.0, 0), r.randf() * TAU, r, rock.darkened(0.15))
		else:
			P.rock_spire(ch, p - Vector3(0, 1.0, 0), r, rock.darkened(0.1))
	for p in spots.call(0.55, 260.0, 520.0, HALF + 200.0):
		P.mesa(ch, p - Vector3(0, 2.0, 0), r, rock.darkened(0.2))


## Beside a station: its ground is its own, but out past ±100 m (z) the line's goes on to the
## horizon, with the far skyline on it.
func _station_wings(ch: Node3D, g: Dictionary, c0: float, c1: float, r: RandomNumberGenerator) -> void:
	var rock := Color(0.85, 0.85, 0.95) if g.arctic else Color.WHITE
	for i in int(0.55 * (c1 - c0) / CHUNK + r.randf()):
		var x := r.randf_range(maxf(c0, g.a), minf(c1, g.b))
		var z := r.randf_range(260.0, 520.0) * (1.0 if r.randf() < 0.5 else -1.0)
		P.mesa(ch, Vector3(x - c0, height(x, z) - 2.0, z), r, rock.darkened(0.2))


func _drift(ch: Node3D, p: Vector3, size: float, h: float, r: RandomNumberGenerator) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radial_segments = 10
	sm.rings = 4
	sm.is_hemisphere = true
	sm.radius = 0.5
	sm.height = 0.5
	mi.mesh = sm
	mi.material_override = A.mat("snow", Color.WHITE, 3.0)
	ch.add_child(mi)
	var along := h > 0.0
	mi.position = Vector3(p.x, (0.0 if along else p.y) - 0.05, p.z)
	mi.scale = Vector3(size, h if along else size * r.randf_range(0.2, 0.35), 1.1 if along else size * r.randf_range(0.5, 1.0))
	mi.rotation.y = 0.0 if along else r.randf() * TAU


func _wire(ch: Node3D, a: Vector3, b: Vector3) -> void:
	var mid := (a + b) / 2.0 + Vector3(0, -0.8, 0)
	for sg in [[a, mid], [mid, b]]:
		var p0: Vector3 = sg[0]
		var p1: Vector3 = sg[1]
		var w := B.box(ch, Vector3(0.025, 0.025, p0.distance_to(p1)), (p0 + p1) / 2.0, Color(0.08, 0.07, 0.07), false)
		w.basis = Basis.looking_at(p1 - p0, Vector3.UP)


## A searchlight signal on the left of the line (z < 0): a lattice-less steel mast on a concrete
## base, a ladder, a black target with a hood over the lens. The lens drops to red behind the train.
func _signal(ch: Node3D, x: float, c0: float, aspect: String) -> void:
	var at := Vector3(x - c0, 0, -3.3)
	var steel := Color(0.3, 0.31, 0.3)
	A.box(ch, Vector3(0.9, 0.5, 0.9), at + Vector3(0, 0.15, 0), "concrete", Color(0.7, 0.68, 0.64), false, 1.0)
	A.cyl(ch, 0.11, 5.6, at + Vector3(0, 3.0, 0), "metal", steel, false)
	for y in range(1, 11):   # ladder rungs up the back
		A.box(ch, Vector3(0.04, 0.03, 0.36), at + Vector3(0.22, y * 0.48, 0), "metal", steel, false, 0.4)
	for zz in [-0.18, 0.18]:
		A.box(ch, Vector3(0.04, 4.9, 0.04), at + Vector3(0.22, 2.75, zz), "metal", steel, false, 0.4)
	A.box(ch, Vector3(0.12, 0.12, 0.3), at + Vector3(0.0, 5.3, 0.15), "metal", steel, false, 0.4)   # the head's bracket
	A.cyl(ch, 0.5, 0.06, at + Vector3(-0.12, 5.3, 0.35), "rubber", Color(0.06, 0.06, 0.06), false, "x")   # the target
	var stripe := A.ring(ch, 0.5, 0.44, at + Vector3(-0.16, 5.3, 0.35), "cream", Color(0.9, 0.88, 0.8), Vector3(0, 0, PI / 2.0))
	stripe.scale = Vector3(1, 0.4, 1)
	A.box(ch, Vector3(0.3, 0.03, 0.34), at + Vector3(-0.3, 5.5, 0.35), "metal", Color(0.08, 0.08, 0.08), false, 0.3)   # hood
	var on := {"green": Color(0.3, 1.0, 0.45), "yellow": Color(1.0, 0.75, 0.15), "red": Color(1.0, 0.12, 0.08)}
	var lens := A.sphere(ch, 0.11, at + Vector3(-0.17, 5.3, 0.35), "cream", on[aspect], 4.0)
	Merge.live(lens)
	_lamps.append([lens, x, on[aspect], on.red])
	var glow := OmniLight3D.new()   # just enough to tint the target round it
	glow.light_color = on[aspect]
	glow.light_energy = 0.4
	glow.omni_range = 1.4
	glow.shadow_enabled = false
	ch.add_child(glow)
	glow.position = at + Vector3(-0.45, 5.3, 0.35)


## Lineside boards on posts: W (whistle) or the station's name ahead. Facing the train (-x).
func _board(ch: Node3D, x: float, c0: float, what: String, g: Dictionary) -> void:
	var at := Vector3(x - c0, 0, -3.4)
	if what == "W":
		A.box(ch, Vector3(0.1, 2.2, 0.1), at + Vector3(0, 1.1, 0), "wood", Color(0.7, 0.68, 0.64), false, 0.6)
		A.box(ch, Vector3(0.05, 0.6, 0.5), at + Vector3(0, 2.2, 0), "metal", Color(0.85, 0.83, 0.78), false, 0.5)
		B.label(ch, "W", at + Vector3(-0.03, 2.2, 0), 60, Color(0.1, 0.1, 0.1), "plate", 0.008).rotation.y = -PI / 2.0
		return
	var name: String = "STATION %s" % g.letter
	for zz in [-0.9, 0.9]:
		A.box(ch, Vector3(0.12, 2.8, 0.12), at + Vector3(0, 1.4, zz), "wood", Color(0.55, 0.5, 0.45), false, 0.6)
	A.box(ch, Vector3(0.06, 0.75, 2.3), at + Vector3(0, 2.55, 0), "metal", Color(0.15, 0.2, 0.3), false, 0.5)
	A.box(ch, Vector3(0.04, 0.82, 2.38), at + Vector3(0.02, 2.55, 0), "metal", Color(0.85, 0.83, 0.78), false, 0.5)
	B.label(ch, name, at + Vector3(-0.04, 2.6, 0), 46, Color(0.92, 0.9, 0.84), "plate", 0.008).rotation.y = -PI / 2.0
	B.label(ch, "%d M" % int(g.b - x), at + Vector3(-0.04, 2.32, 0), 30, Color(0.92, 0.9, 0.84), "plate", 0.006).rotation.y = -PI / 2.0


func _milepost(ch: Node3D, x: float, c0: float) -> void:
	var at := Vector3(x - c0, 0, -2.9)
	A.box(ch, Vector3(0.14, 1.1, 0.3), at + Vector3(0, 0.55, 0), "concrete", Color(0.88, 0.86, 0.8), false, 0.5)
	B.label(ch, "%.1f" % ((odo + x) / 1000.0), at + Vector3(-0.075, 0.85, 0), 30, Color(0.12, 0.12, 0.12), "stencil", 0.006).rotation.y = -PI / 2.0


## A dirt road over the line: timber laid between and beside the rails, crossbucks with red lamps
## that flash and a bell that rings while the train's near, a wreck left waiting at it.
func _crossing(ch: Node3D, x: float, c0: float, r: RandomNumberGenerator, arctic: bool) -> void:
	var lx := x - c0
	var z := -150.0
	var road := Color(0.85, 0.8, 0.75) if not arctic else Color(0.95, 0.95, 1.0)
	while z < 150.0:
		var z1 := z + 6.0
		if absf(z) > 2.0 or absf(z1) > 2.0:
			var ya := height(x, z)
			var yb := height(x, z1)
			var seg := A.box(ch, Vector3(6.0, 0.08, 6.25), Vector3(lx, (ya + yb) / 2.0 + 0.04, (z + z1) / 2.0), "dirt" if not arctic else "snow", road, false, 3.0)
			seg.rotation.x = -atan2(yb - ya, 6.0)
		z = z1
	for zz in [-1.15, 0.0, 1.15]:   # the timbers
		A.box(ch, Vector3(5.6, 0.1, 0.5 if absf(zz) > 0.1 else 1.2), Vector3(lx, 0.07, zz), "wood", Color(0.5, 0.45, 0.4), false, 1.0)
	var lamps := []
	for sd in [-1.0, 1.0]:
		var at := Vector3(lx - sd * 4.2, 0, sd * 4.6)
		A.cyl(ch, 0.07, 3.6, at + Vector3(0, 1.8, 0), "metal", Color(0.85, 0.85, 0.82), false)
		for k in [-1.0, 1.0]:   # the crossbuck: two white boards crossed
			var arm := A.box(ch, Vector3(0.04, 0.22, 1.5), at + Vector3(-sd * 0.08, 3.3, 0), "metal", Color(0.92, 0.9, 0.85), false, 0.5)
			arm.rotation.x = k * 0.78
		A.box(ch, Vector3(0.06, 0.2, 1.2), at + Vector3(0, 2.55, 0), "metal", Color(0.1, 0.1, 0.1), false, 0.5)   # the lamp bar
		for k in [-1.0, 1.0]:
			A.cyl(ch, 0.16, 0.12, at + Vector3(-sd * 0.1, 2.55, k * 0.45), "rubber", Color(0.08, 0.08, 0.08), false, "x")   # hood
			var lamp := A.sphere(ch, 0.1, at + Vector3(-sd * 0.16, 2.55, k * 0.45), "cream", Color(1.0, 0.15, 0.08), 6.0)
			lamp.visible = false
			Merge.live(lamp)
			lamps.append(lamp)
		B.label(ch, "RAILROAD\nCROSSING", at + Vector3(-sd * 0.11, 3.3, 0), 18, Color(0.12, 0.12, 0.12), "plate", 0.006).rotation.y = -sd * PI / 2.0
	var bell := AudioStreamPlayer3D.new()
	bell.stream = Sfx.stream("ding")
	bell.volume_db = -14.0
	bell.unit_size = 8.0
	bell.max_distance = 180.0
	bell.bus = "World" if AudioServer.get_bus_index("World") >= 0 else "Master"
	ch.add_child(bell)
	bell.position = Vector3(lx, 3.0, -4.6)
	_bells.append([x, lamps, bell])
	var wz := -r.randf_range(10.0, 14.0) if r.randf() < 0.5 else r.randf_range(10.0, 14.0)
	P.car_wreck(ch, Vector3(lx + r.randf_range(-1.0, 1.0), height(x, wz), wz), PI / 2.0 + r.randf_range(-0.2, 0.2), r)


## A passing loop on the right of the line with a freight standing in it, engine ticking over,
## headlight dimmed, waiting for us to go by.
func _loop(ch: Node3D, lp: Vector2, c0: float, r: RandomNumberGenerator, arctic: bool) -> void:
	var z := 4.8
	var run := 26.0   # the turnouts
	CP._track(ch, z, lp.x + run - c0, lp.y - run - c0)
	CP._track_seg(ch, Vector2(lp.x - c0, 1.7), Vector2(lp.x + run - c0, z))
	CP._track_seg(ch, Vector2(lp.y - run - c0, z), Vector2(lp.y - c0, 1.7))
	var eng := Node3D.new()
	ch.add_child(eng)
	var ex := lp.y - run - 10.0
	eng.position = Vector3(ex - c0, CP.RAIL_TOP, z)
	eng.rotation.y = PI   # facing back down the line, at us
	var ec := [Color(0.25, 0.3, 0.4), Color(0.55, 0.2, 0.12), Color(0.3, 0.32, 0.28), Color(0.62, 0.5, 0.18)][r.randi() % 4] as Color
	CP.loco(eng, 13.0, ec, "BRM %d" % r.randi_range(200, 899))
	var hl := SpotLight3D.new()
	hl.light_color = Color(1.0, 0.9, 0.7)
	hl.light_energy = 2.5
	hl.spot_range = 50.0
	hl.spot_angle = 16.0
	hl.light_volumetric_fog_energy = 1.5
	eng.add_child(hl)
	hl.position = Vector3(6.4, 2.4, 0)
	hl.rotation.y = -PI / 2.0
	var idle := AudioStreamPlayer3D.new()
	idle.stream = Sfx.stream("diesel_idle")
	idle.volume_db = -4.0
	idle.unit_size = 9.0
	idle.max_distance = 160.0
	idle.bus = "World" if AudioServer.get_bus_index("World") >= 0 else "Master"
	eng.add_child(idle)
	idle.autoplay = true
	var x := ex - 12.0
	while x > lp.x + run + 6.0:
		var at := Vector3(x - c0, CP.RAIL_TOP, z)
		match r.randi() % 4:
			0: P.boxcar(ch, at, 0.0, r)
			1: CP._tank_car(ch, at, r)
			2: CP._hopper(ch, at, r)
			3: CP._flatcar(ch, at, r)
		x -= 10.8


# --- tunnels ---------------------------------------------------------------------------------------------

## A tunnel through a ridge: a portal set in rock at a mouth (checkpoint._portal, its own bore 30 m
## deep), the ridge either side as crags stepping back into the mountain (the ground rises over the
## top: height()), and between the portals a lined bore: walls and a vault of concrete blocks, ribs
## every 4 m, refuge niches picked out in white, a cable run on brackets, a caged lamp now and then.
func _tunnel_chunk(ch: Node3D, g: Dictionary, xa: float, xb: float, c0: float, r: RandomNumberGenerator) -> void:
	var rock := Color(0.85, 0.85, 0.95) if g.arctic else Color(0.95, 0.9, 0.85)
	var bore_a: float = g.a + (BORE_IN if g.entry else 0.0)
	var bore_b: float = g.b - (BORE_IN if g.exit == "portal" else 0.0)
	_track(ch, xa, xb, c0)
	A.box(ch, Vector3(xb - xa, 0.4, 9.4), Vector3((xa + xb) / 2.0 - c0, -0.25, 0), "gravel", Color(0.4, 0.38, 0.36), true, 2.0)   # the floor
	if g.entry and g.a >= xa and g.a < xb:
		A.snow_cover = g.arctic
		var pr := RandomNumberGenerator.new()   # (the mouth belongs to the station it's seen from: the same for anyone)
		pr.seed = hash([g.seed_in, "mouth"])
		CP._portal(ch, Vector3(g.a - c0, 0, 0), 1.0, pr, rock, false)
		_ridge(ch, g.a - c0, -1.0, pr, rock)
	if g.exit == "portal" and g.b > xa and g.b <= xb:
		A.snow_cover = g.get("next_arctic", g.arctic)
		var rk := Color(0.85, 0.85, 0.95) if A.snow_cover else Color(0.95, 0.9, 0.85)
		var pr := RandomNumberGenerator.new()
		pr.seed = hash([g.seed_out, "mouth"])
		CP._portal(ch, Vector3(g.b - c0, 0, 0), -1.0, pr, rk, false)
		_ridge(ch, g.b - c0, 1.0, pr, rk)
	A.snow_cover = false
	var ba := maxf(xa, bore_a)
	var bb := minf(xb, bore_b)
	if bb <= ba:
		return
	var c := Color(0.66, 0.63, 0.58).darkened(0.62)
	var ln := bb - ba
	var mid := (ba + bb) / 2.0 - c0
	var aw := CP.ARCH_W
	var sp := CP.SPRING
	for sd in [-1.0, 1.0]:
		A.box(ch, Vector3(ln, sp, 0.6), Vector3(mid, sp / 2.0, sd * (aw + 0.3)), "concrete", c, false, 2.0)
		A.box(ch, Vector3(ln, 0.25, 0.5), Vector3(mid, 0.12, sd * (aw - 0.15)), "concrete", c.darkened(0.2), false, 1.0)   # cess walk edge
	for i in 12:
		var a := PI * (i + 0.5) / 12.0
		var vb := A.box(ch, Vector3(ln, 0.6, 1.35), Vector3(mid, sp + sin(a) * (aw + 0.3), cos(a) * (aw + 0.3)), "concrete", c.darkened(0.06 * (i % 2)), false, 2.0)
		vb.rotation.x = -(a - PI / 2.0)
	# Soot down the middle of the vault, where the exhausts hit it.
	var soot := A.box(ch, Vector3(ln, 0.05, 2.6), Vector3(mid, sp + aw - 0.02, 0), "concrete", Color(0.05, 0.05, 0.05), false, 2.0)
	soot.rotation.x = 0.0
	var x := ceilf(ba / 4.0) * 4.0
	while x < bb:   # ribs
		for sd in [-1.0, 1.0]:
			A.box(ch, Vector3(0.35, sp, 0.25), Vector3(x - c0, sp / 2.0, sd * (aw - 0.1)), "concrete", c.darkened(0.15), false, 1.0)
		for i in 10:
			var a := PI * (i + 0.5) / 10.0
			var rb := A.box(ch, Vector3(0.35, 0.25, 1.45), Vector3(x - c0, sp + sin(a) * (aw - 0.1), cos(a) * (aw - 0.1)), "concrete", c.darkened(0.15), false, 1.0)
			rb.rotation.x = -(a - PI / 2.0)
		# The cable run: two cables on a bracket.
		A.box(ch, Vector3(0.06, 0.3, 0.2), Vector3(x - c0, 2.3, -(aw - 0.32)), "metal", Color(0.25, 0.25, 0.25), false, 0.4)
		x += 4.0
	for zz in [0.0, 0.07]:
		A.box(ch, Vector3(ln, 0.045, 0.045), Vector3(mid, 2.32 - zz * 2.0, -(aw - 0.38 - zz)), "rubber", Color(0.08, 0.08, 0.08), false, 1.0)
	# Refuge niches, every 20 m, alternating sides: a dark recess picked out in white paint.
	x = ceilf(ba / 20.0) * 20.0
	while x < bb:
		var sd := 1.0 if int(x / 20.0) % 2 == 0 else -1.0
		A.box(ch, Vector3(1.5, 2.1, 0.05), Vector3(x - c0, 1.15, sd * (aw - 0.02)), "rubber", Color(0.02, 0.02, 0.02), false, 1.0)
		for f in [[Vector3(1.75, 0.12, 0.04), Vector3(0, 2.26, 0)], [Vector3(0.12, 2.2, 0.04), Vector3(-0.82, 1.15, 0)], [Vector3(0.12, 2.2, 0.04), Vector3(0.82, 1.15, 0)]]:
			A.box(ch, f[0], Vector3(x - c0, 0, sd * (aw - 0.05)) + f[1], "cream", Color(0.8, 0.78, 0.72), false, 0.5)
		x += 20.0
	# A caged lamp every 36 m, high on the wall; some of them dead.
	x = ceilf(ba / 36.0) * 36.0 + 10.0
	while x < bb:
		var sd := -1.0 if int(x / 36.0) % 2 == 0 else 1.0
		var at := Vector3(x - c0, 3.6, sd * (aw - 0.15))
		if r.randf() < 0.8:
			var l := A.wall_lamp(ch, at, Vector3(0, 0, -sd), Color(1.0, 0.72, 0.4), 1.4, false)
			l.omni_range = 9.0
			l.light_volumetric_fog_energy = 2.0
		else:
			A.box(ch, Vector3(0.3, 0.2, 0.15), at, "metal", Color(0.2, 0.2, 0.2), false, 0.4)
		x += 36.0


## Rock either side of a portal, stepping back and up into the mountain: the ground does the rest.
## `toward`: which way the open line lies from the mouth (-1: it's in front at -x).
func _ridge(ch: Node3D, lx: float, toward: float, r: RandomNumberGenerator, rock: Color) -> void:
	for sd in [-1.0, 1.0]:
		var z := 24.0
		while z < 120.0:
			var w := r.randf_range(14.0, 22.0)
			var back := r.randf_range(4.0, 14.0) + (z - 24.0) * 0.25
			var h := r.randf_range(18.0, 34.0) + (z - 24.0) * 0.2
			var foot := Vector3(lx - toward * back, -2.0, sd * (z + w / 2.0))
			CP._crag(ch, foot, w, r.randf_range(14.0, 22.0), h, PI / 2.0, r, rock.darkened(r.randf() * 0.16))
			if r.randf() < 0.6:
				P.boulder(ch, foot + Vector3(toward * r.randf_range(8.0, 14.0), 0.5, r.randf_range(-4, 4)), Vector3(r.randf_range(3, 6), r.randf_range(1.5, 3.5), r.randf_range(3, 6)), r, rock.darkened(0.1), false)
			z += w * r.randf_range(0.6, 0.8)
	for k in r.randi_range(22, 30):   # outcrops of rock up the mountain, standing out of the ground
		var zz := r.randf_range(26.0, 300.0) * (1.0 if r.randf() < 0.5 else -1.0)
		var xx := lx - toward * r.randf_range(-20.0, 190.0)
		var gy := height(xx + _chunk_x, zz)
		var w := r.randf_range(10.0, 28.0)
		CP._crag(ch, Vector3(xx, gy - 7.0, zz), w, w * r.randf_range(0.6, 1.0), r.randf_range(12.0, 28.0), r.randf() * PI, r, rock.darkened(r.randf() * 0.2))
	for k in r.randi_range(3, 5):   # talus spilled down in front
		var zz := r.randf_range(14.0, 40.0) * (1.0 if r.randf() < 0.5 else -1.0)
		P.boulder(ch, Vector3(lx + toward * r.randf_range(4.0, 16.0), 0.3, zz), Vector3(r.randf_range(2, 5), r.randf_range(1.2, 2.6), r.randf_range(2, 5)), r, rock.darkened(0.12), false)
