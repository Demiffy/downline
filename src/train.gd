# The train: a rusty road-switcher diesel + walkable crew car + flatcar (+ optional storage car).
# Floor is at y = 1.0 so station platforms line up with the doors; the platform side is +z.
# `speed` (m/s) drives wheels and exhaust. Static parts are merged into a few meshes (merge.gd).
extends Node3D

const A = preload("res://src/art.gd")
const B = preload("res://src/build.gd")
const Sfx = preload("res://src/sfx.gd")
const Merge = preload("res://src/merge.gd")

const F := 1.0  # floor height
const INSIDE := AABB(Vector3(-8.1, 0.6, -2.0), Vector3(16.2, 3.2, 4.0))
const STORAGE := AABB(Vector3(-20.5, 0.6, -2.0), Vector3(12.4, 3.2, 4.0))
const CAR_LEN := 12.4
const WALL_H := 2.7

const CREAM := Color(0.86, 0.8, 0.66)
const FRAME := Color(0.2, 0.19, 0.18)
const RAIL := Color(0.9, 0.72, 0.2)          # safety-yellow handrails
const SAGE := Color(0.62, 0.7, 0.6)              # the painted steel inside: railway sage

var speed := 0.0
var market_label: Label3D
var _hour_hand: Node3D
var _min_hand: Node3D
var _plate_at := Vector3.ZERO
var _plate_text: Node3D
var _place := ""
var _digits: Array = []        # DIGITAL_CLOCK: per digit, its 7 segment meshes
var _colons: Array[MeshInstance3D] = []
var _seg_on: StandardMaterial3D
var _seg_off: StandardMaterial3D
const SEGMENTS := {   # which of a b c d e f g are lit
	"0": "abcdef", "1": "bc", "2": "abged", "3": "abgcd", "4": "fgbc", "5": "afgcd",
	"6": "afgedc", "7": "abc", "8": "abcdefg", "9": "abcdfg", "-": "g", " ": "",
}
var screen_label: Label3D
var headlight: SpotLight3D
var _wheels: Array = []   # [pivot, radius]
var _rods: Array = []     # [rod, center_x, side]
var _angle := 0.0
var _steam: GPUParticles3D
var _steam_mat: ParticleProcessMaterial
var _chug: AudioStreamPlayer3D
var _gauges: Array = []    # [needle node, kind, current value 0..1]
var _rpm := 0.25
var _comp: AudioStreamPlayer3D   # air compressor: cuts in now and then, then blows down
var _comp_t := 20.0
var _comp_on := 0.0
var _rail := 0.0            # metres run (the rail joints)
const JOINT := 18.3          # rail length between joints
var _axles: Array[float] = []   # x of every axle (bogie() adds them)
var has_storage := false
var _door_leaves: Array = []   # [leaf node, how far it slides to shut]
var _doors_open := true
var _rear_lock: Node3D
var _flat: Node3D


func contains(pos: Vector3) -> bool:
	var l := to_local(pos)
	return INSIDE.has_point(l) or (has_storage and STORAGE.has_point(l))


## Anywhere you can stand on the train, loco walkways and flatcar included.
func on_board(pos: Vector3) -> bool:
	var l := to_local(pos)
	return l.x > rear_x() - 0.5 and l.x < 17.8 and absf(l.z) < 2.6 and l.y > 0.5 and l.y < 6.0


var _charge_lamps: Array[MeshInstance3D] = []
var _charge_needles: Array[Node3D] = []


## The charging board on the back wall, as the railways had them: a black slate panel in an oak frame
## with an ammeter and a voltmeter, a knife switch, a row of fuses and the Bureau's brass plate; a
## steel shelf under it with three cradles, a cell clamped in each on red and black leads, a pilot
## lamp over each that chases while it's live; the rectifier cabinet beside it humming on the floor,
## a crate of shells under the shelf. Hold E: every battery you carry is topped up (`on_use`, the
## player's recharge).
func add_charger(on_use: Callable) -> void:
	var root := Node3D.new()
	root.name = "Charger"
	add_child(root)
	var c := Vector3(1.45, F, -1.96)   # (the wall's face)
	var slate := Color(0.1, 0.11, 0.1)
	var oak := Color(0.5, 0.36, 0.24)
	var green := Color(0.3, 0.38, 0.32)
	var brass := Color(0.82, 0.66, 0.38)
	# The board: slate in an oak frame, on four brass standoffs.
	var bw := 1.7
	var bh := 0.92
	var by := 1.72
	A.box(root, Vector3(bw + 0.1, bh + 0.1, 0.035), c + Vector3(0, by, 0.03), "wood", oak, false, 0.5)
	A.box(root, Vector3(bw, bh, 0.03), c + Vector3(0, by, 0.05), "enamel", slate, false, 0.4)
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			A.cyl(root, 0.018, 0.02, c + Vector3(sx * (bw / 2.0 - 0.06), by + sy * (bh / 2.0 - 0.06), 0.07), "brass", brass, false, "z")
	A.box(root, Vector3(0.98, 0.09, 0.006), c + Vector3(0, by + 0.37, 0.068), "brass", brass, false, 0.3)
	var plate := B.label(root, "B.R.M.  CELL  CHARGING", c + Vector3(0, by + 0.37, 0.072), 22, Color(0.18, 0.12, 0.06), "plate", 0.0024)
	plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Two meters: brass rims, cream dials with a scale, black needles (the ammeter's swings when you charge).
	for m in [[-0.52, "AMPERES"], [-0.14, "VOLTS"]]:
		var mc := c + Vector3(m[0], by + 0.1, 0.07)
		A.cyl(root, 0.13, 0.05, mc, "brass", brass, false, "z")
		A.cyl(root, 0.112, 0.008, mc + Vector3(0, 0, 0.026), "cream", Color(0.92, 0.88, 0.76), false, "z")
		for k in 9:   # the scale: an arc of ticks over the top
			var a := lerpf(-1.0, 1.0, k / 8.0)
			A.box(root, Vector3(0.004, 0.018 if k % 2 == 0 else 0.01, 0.002), mc + Vector3(sin(a) * 0.085, cos(a) * 0.085 - 0.02, 0.031), "rubber", Color(0.1, 0.1, 0.1), false, 0.2, Vector3(0, 0, -a))
		var lab := B.label(root, m[1], mc + Vector3(0, -0.06, 0.032), 12, Color(0.2, 0.15, 0.1), "plate", 0.0022)
		lab.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var nd := Node3D.new()   # the needle on a pivot
		root.add_child(nd)
		nd.position = mc + Vector3(0, -0.02, 0.034)
		A.box(nd, Vector3(0.004, 0.09, 0.003), Vector3(0, 0.045, 0), "rubber", Color(0.08, 0.08, 0.08), false, 0.2)
		nd.rotation.z = 0.5
		Merge.live(nd)
		_charge_needles.append(nd)
		A.sphere(root, 0.008, mc + Vector3(0, -0.02, 0.036), "brass", brass)
	# The knife switch: a porcelain base, two copper blades shut into their jaws, a black handle.
	var ks := c + Vector3(0.3, by + 0.08, 0.07)
	A.box(root, Vector3(0.2, 0.3, 0.025), ks, "cream", Color(0.9, 0.88, 0.82), false, 0.3)
	for bx in [-0.045, 0.045]:
		A.box(root, Vector3(0.016, 0.04, 0.03), ks + Vector3(bx, 0.11, 0.02), "copper", Color.WHITE, false, 0.2)   # jaws
		A.box(root, Vector3(0.016, 0.04, 0.03), ks + Vector3(bx, -0.11, 0.02), "copper", Color.WHITE, false, 0.2)   # hinges
		A.box(root, Vector3(0.01, 0.24, 0.012), ks + Vector3(bx, 0.0, 0.04), "copper", Color.WHITE, false, 0.2)    # blades
	A.box(root, Vector3(0.12, 0.016, 0.016), ks + Vector3(0, 0.1, 0.05), "rubber", Color(0.06, 0.06, 0.06), false, 0.2)
	A.cyl(root, 0.014, 0.08, ks + Vector3(0, 0.1, 0.09), "rubber", Color(0.06, 0.06, 0.06), false, "z")
	# Fuses: a row of white carriers, and a selector knob.
	for k in 4:
		A.box(root, Vector3(0.05, 0.1, 0.03), c + Vector3(0.56 + k * 0.065, by + 0.16, 0.075), "cream", Color(0.88, 0.86, 0.8), false, 0.2)
	A.cyl(root, 0.035, 0.03, c + Vector3(0.66, by - 0.05, 0.08), "rubber", Color(0.08, 0.08, 0.08), false, "z")
	A.box(root, Vector3(0.006, 0.03, 0.004), c + Vector3(0.66, by - 0.035, 0.097), "cream", Color(0.9, 0.88, 0.8), false, 0.2)
	# The cells: three cradles on a steel shelf, a pilot lamp over each, leads down from the board.
	var sy := F + 1.02
	A.box(root, Vector3(bw, 0.035, 0.34), Vector3(c.x, sy, c.z + 0.18), "metal", green, true, 0.6)
	for sx in [-0.75, 0.75]:   # brackets
		A.seg(root, c + Vector3(sx, sy - F - 0.3, 0.02), c + Vector3(sx, sy - F - 0.02, 0.32), 0.012, 0.012, "metal", green.darkened(0.3))
	for i in 3:
		var x := -0.55 + i * 0.42
		var cell := c + Vector3(x, sy - F + 0.0175, 0.19)
		for side in [-1.0, 1.0]:   # the cradle's cheeks
			A.box(root, Vector3(0.012, 0.16, 0.2), cell + Vector3(side * 0.13, 0.08, 0), "metal", green.darkened(0.2), false, 0.3)
		A.box(root, Vector3(0.24, 0.012, 0.2), cell + Vector3(0, 0.006, 0), "rubber", Color(0.1, 0.1, 0.1), false, 0.3)
		A.box(root, Vector3(0.2, 0.22, 0.15), cell + Vector3(0, 0.12, 0), "plastic", Color(0.16, 0.14, 0.12), false, 0.3)   # the cell, ebonite
		A.box(root, Vector3(0.18, 0.02, 0.13), cell + Vector3(0, 0.235, 0), "plastic", Color(0.22, 0.2, 0.18), false, 0.3)
		for tx in [-0.05, 0.05]:   # terminals, and a lead to each
			A.cyl(root, 0.015, 0.03, cell + Vector3(tx, 0.255, 0), "brass", brass, false)
			var lead := Color(0.7, 0.12, 0.08) if tx < 0.0 else Color(0.08, 0.08, 0.08)
			A.seg(root, cell + Vector3(tx, 0.27, 0), c + Vector3(x + tx * 0.6, by - bh / 2.0 + 0.02, 0.06), 0.006, 0.006, "rubber", lead)
		var lamp_at := c + Vector3(x, by - bh / 2.0 + 0.12, 0.07)
		A.cyl(root, 0.028, 0.025, lamp_at, "brass", brass, false, "z")   # the bezel
		var lamp := A.sphere(root, 0.02, lamp_at + Vector3(0, 0, 0.018), "cream", Color(0.3, 1.0, 0.35), 4.0)
		Merge.live(lamp)
		_charge_lamps.append(lamp)
	# The rectifier: a green cabinet on the floor to the right, louvred, its own plate, a conduit up.
	var rc := c + Vector3(1.22, 0, 0.2)
	A.box(root, Vector3(0.62, 0.85, 0.38), rc + Vector3(0, 0.43, 0), "enamel", green, true, 0.6)
	A.box(root, Vector3(0.66, 0.05, 0.42), rc + Vector3(0, 0.88, 0), "metal", green.darkened(0.3), false, 0.5)
	for k in 6:
		A.box(root, Vector3(0.4, 0.02, 0.01), rc + Vector3(0, 0.22 + k * 0.08, 0.195), "rubber", Color(0.08, 0.08, 0.08), false, 0.2)
	A.box(root, Vector3(0.2, 0.07, 0.004), rc + Vector3(0, 0.76, 0.192), "brass", brass, false, 0.2)
	A.seg(root, rc + Vector3(-0.2, 0.9, -0.1), c + Vector3(bw / 2.0 - 0.05, by - 0.2, 0.03), 0.025, 0.025, "metal", Color(0.3, 0.3, 0.3))
	A.seg(root, c + Vector3(-bw / 2.0 + 0.1, by + bh / 2.0, 0.02), c + Vector3(-bw / 2.0 + 0.1, 2.28 - 0.02, 0.02), 0.022, 0.022, "metal", Color(0.4, 0.42, 0.4))   # up to the car's conduit
	# Shells: a crate under the shelf, a box or two on its end.
	A.box(root, Vector3(0.5, 0.3, 0.32), c + Vector3(-0.35, 0.15, 0.2), "wood", Color(0.55, 0.45, 0.3), true, 0.5)
	var st := B.label(root, "12 GA", c + Vector3(-0.35, 0.16, 0.365), 30, Color(0.15, 0.12, 0.1), "stencil", 0.004)
	st.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for k in 2:
		A.box(root, Vector3(0.14, 0.07, 0.1), c + Vector3(0.7, sy - F + 0.05 + k * 0.071, 0.2), "cardboard", Color(0.78, 0.28, 0.18), false, 0.3)
	Merge.bake(root, 8.0)
	var it := B.interactable(self, Vector3(bw, 1.3, 0.4), c + Vector3(0, 1.4, 0.2), Color(0, 0, 0, 0), "Recharge batteries", on_use, 1.0)
	it.shared = false   # your own kit


func _process_charger() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for i in _charge_lamps.size():   # lamps chase slowly: it's live
		_charge_lamps[i].visible = fmod(t * 1.2 - i * 0.33, 1.0) < 0.7
	for i in _charge_needles.size():   # the needles hunt a little round their reading
		_charge_needles[i].rotation.z = (0.35 if i == 0 else -0.2) + sin(t * (1.3 + i) + i) * 0.03


var _barrier: StaticBody3D

## An invisible wall round everything you can stand on, that only creatures run into: nothing
## follows you aboard.
func _mob_barrier() -> void:
	if _barrier:
		_barrier.queue_free()
	var x0 := rear_x() - 0.4
	var x1 := 17.9
	_barrier = B.mob_barrier(self, Vector3(x1 - x0, 6.0, 4.6), Vector3((x0 + x1) / 2.0, 3.0, 0))


## x of the very back of the train (where the delivery handcar parks).
func rear_x() -> float:
	return -15.6 - (CAR_LEN if has_storage else 0.0)


func build(open_terminal: Callable) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	_car()
	_interior(open_terminal, rng)
	_locomotive()
	_flatcar(rng)
	_chug = AudioStreamPlayer3D.new()
	_chug.stream = Sfx.stream("diesel_idle")
	_chug.bus = "World"
	_chug.unit_size = 10.0
	add_child(_chug)
	_chug.position = Vector3(11, 2, 0)
	_comp = AudioStreamPlayer3D.new()
	_comp.stream = Sfx.stream("compressor")
	_comp.bus = "World"
	_comp.unit_size = 5.0
	_comp.volume_db = -10.0
	add_child(_comp)
	_comp.position = Vector3(14.5, 0.8, 0.9)
	Merge.live(_rear_lock)   # removed when the storage car is bought
	Merge.live(_flat)        # slides back when the storage car is bought
	Merge.bake(self, 8.0)
	Merge.bake(_flat, 8.0)
	_mob_barrier()


func _process(delta: float) -> void:
	_angle -= speed * delta
	for w in _wheels:
		w[0].rotation.z = _angle / w[1]
	_steam.amount_ratio = clampf(0.25 + absf(speed) / 6.0, 0.0, 1.0)
	_steam_mat.gravity = Vector3(-speed * 2.0, 1.5, 0)
	# Diesel always idles; it revs with speed. Wheels clack over each rail joint (every 12 m).
	if not _chug.playing and is_inside_tree():
		_chug.play()
	_update_gauges(delta)
	_handcar_tick(delta)
	_process_charger()
	_chug.pitch_scale = lerpf(0.85, 1.9, clampf((_rpm - 0.22) / 0.73, 0.0, 1.0))
	_chug.volume_db = lerpf(-8.0, -1.0, clampf((_rpm - 0.22) / 0.73, 0.0, 1.0))
	# The air compressor cuts in every half minute or so, pumps up, then the governor blows down.
	_comp_t -= delta
	if _comp_t <= 0.0 and _comp_on <= 0.0 and is_inside_tree():
		_comp_on = randf_range(5.0, 8.0)
		_comp.play()
	if _comp_on > 0.0:
		_comp_on -= delta
		if _comp_on <= 0.0:
			_comp.stop()
			_comp_t = randf_range(25.0, 50.0)
			Sfx.play(self, "air_release", to_global(Vector3(14.5, 0.6, -0.9)), -6.0, randf_range(0.9, 1.1))
	# Rail joints every JOINT metres: each axle knocks over one in turn, front to back, so they come
	# in the rhythm of the trucks (two quick, a gap, two quick...).
	var was := _rail
	_rail += absf(speed) * delta
	if absf(speed) > 0.3:
		for ax: float in _axles:
			if floor((was + ax) / JOINT) != floor((_rail + ax) / JOINT):
				var f := clampf(absf(speed) / 24.0, 0.0, 1.0)
				Sfx.play(self, "rail_clack", to_global(Vector3(ax, 0.4, 0)), lerpf(-26.0, -10.0, sqrt(f)), lerpf(0.88, 1.06, f) * randf_range(0.97, 1.03))


# --- running gear (shared) -------------------------------------------------------

## Wheel on a live pivot (it spins): tyre, flange, dished centre, spokes so the motion reads.
func _wheel(pos: Vector3, radius: float, parent: Node = null) -> Node3D:
	var pivot := Node3D.new()
	(parent if parent else self).add_child(pivot)
	pivot.position = pos
	Merge.live(pivot)
	var s := signf(pos.z) if pos.z != 0.0 else 1.0
	A.cyl(pivot, radius, 0.1, Vector3.ZERO, "metal", Color(0.42, 0.4, 0.38), false, "z")
	A.cyl(pivot, radius + 0.035, 0.025, Vector3(0, 0, -s * 0.05), "metal", Color(0.3, 0.29, 0.28), false, "z")   # flange, rail side
	A.cyl(pivot, radius * 0.82, 0.12, Vector3.ZERO, "rust", Color(0.75, 0.7, 0.68), false, "z")
	A.cyl(pivot, radius * 0.22, 0.2, Vector3.ZERO, "metal", Color(0.3, 0.3, 0.3), false, "z")
	for a in [0.0, PI / 3, 2 * PI / 3]:
		var spoke := A.box(pivot, Vector3(radius * 1.6, 0.07, 0.13), Vector3.ZERO, "rust", Color(0.65, 0.6, 0.58), false, 1.0)
		spoke.rotation.z = a
	A.box(pivot, Vector3(radius * 0.5, radius * 0.25, 0.14), Vector3(radius * 0.45, 0, 0), "metal", Color(0.3, 0.3, 0.3), false)   # counterweight
	_wheels.append([pivot, radius])
	return pivot


## A sliding door leaf, built on its moving body round `c` (its middle): framed and panelled in the
## car's paint with mouldings standing proud, a tall drop-light of rain glass in a rubber gasket and a
## brass frame, a riveted kick plate, a brass grab bar and a T-key lock at the closing edge (`edge`:
## which way that is), a rubber seal down it, and the roller hangers along the top.
func _door_leaf(leafn: Node3D, c: Vector3, kind: String, lt: Color, edge: float) -> void:
	var w := 1.5
	var h := 2.28
	var t := 0.05
	var gw := 0.86          # the window
	var gh := 0.78
	var gy := 0.48          # its middle, over the leaf's
	var stile := (w - gw) / 2.0
	var top := h / 2.0 - (gy + gh / 2.0)
	var bot := h / 2.0 + (gy - gh / 2.0)
	A.box(leafn, Vector3(w, bot, t), c + Vector3(0, -h / 2.0 + bot / 2.0, 0), kind, lt, false, 1.0)   # below the glass
	A.box(leafn, Vector3(w, top, t), c + Vector3(0, h / 2.0 - top / 2.0, 0), kind, lt, false, 1.0)   # above it
	for sx in [-1.0, 1.0]:
		A.box(leafn, Vector3(stile, gh, t), c + Vector3(sx * (gw / 2.0 + stile / 2.0), gy, 0), kind, lt, false, 1.0)
	var face := t / 2.0 + 0.008
	var mold := lt.darkened(0.18)
	# Mouldings: round the edge of the leaf, and two fielded panels below the window.
	for sx in [-1.0, 1.0]:
		A.box(leafn, Vector3(0.05, h - 0.02, 0.016), c + Vector3(sx * (w / 2.0 - 0.035), 0, face), kind, mold, false, 1.0)
	A.box(leafn, Vector3(w - 0.04, 0.05, 0.016), c + Vector3(0, h / 2.0 - 0.035, face), kind, mold, false, 1.0)
	var py0 := -h / 2.0 + 0.32   # (over the kick plate)
	var py1 := gy - gh / 2.0 - 0.1
	for pk in 2:
		var pc := Vector3(0, lerpf(py0, py1, 0.25 if pk == 0 else 0.75), face)
		var ph := (py1 - py0) / 2.0 - 0.08
		for sy in [-1.0, 1.0]:
			A.box(leafn, Vector3(w - 0.24, 0.035, 0.014), c + pc + Vector3(0, sy * ph / 2.0, 0), kind, mold, false, 1.0)
		for sx in [-1.0, 1.0]:
			A.box(leafn, Vector3(0.035, ph, 0.014), c + pc + Vector3(sx * (w - 0.24) / 2.0, 0, 0), kind, mold, false, 1.0)
		A.box(leafn, Vector3(w - 0.36, ph - 0.12, 0.008), c + pc + Vector3(0, 0, -0.002), kind, lt.lightened(0.04), false, 1.0)   # the raised field
	# The window: rain glass in a black gasket, a brass frame round it, a bar across where it drops.
	var g := A.box(leafn, Vector3(gw, gh, 0.01), c + Vector3(0, gy, 0), "metal", Color.WHITE, false)
	g.material_override = A.rain_glass()
	for sx in [-1.0, 1.0]:
		A.box(leafn, Vector3(0.035, gh + 0.04, t + 0.012), c + Vector3(sx * (gw / 2.0 + 0.004), gy, 0), "rubber", Color(0.07, 0.07, 0.07), false)
		A.box(leafn, Vector3(gw + 0.04, 0.035, t + 0.012), c + Vector3(0, gy + sx * (gh / 2.0 + 0.004), 0), "rubber", Color(0.07, 0.07, 0.07), false)
		A.box(leafn, Vector3(0.03, gh + 0.1, 0.012), c + Vector3(sx * (gw / 2.0 + 0.04), gy, face + 0.004), "brass", Color(0.8, 0.66, 0.4), false, 0.3)
		A.box(leafn, Vector3(gw + 0.11, 0.03, 0.012), c + Vector3(0, gy + sx * (gh / 2.0 + 0.04), face + 0.004), "brass", Color(0.8, 0.66, 0.4), false, 0.3)
	A.box(leafn, Vector3(gw, 0.025, 0.02), c + Vector3(0, gy + gh * 0.18, 0.0), "brass", Color(0.8, 0.66, 0.4), false, 0.3)
	# The kick plate along the foot, riveted.
	A.box(leafn, Vector3(w - 0.06, 0.26, 0.012), c + Vector3(0, -h / 2.0 + 0.16, face), "riveted", Color(0.4, 0.4, 0.38), false, 0.5)
	# The closing edge: a rubber seal, a brass grab bar on two standoffs, a T-key lock.
	var ex := edge * (w / 2.0 - 0.005)
	A.box(leafn, Vector3(0.03, h - 0.04, t + 0.02), c + Vector3(ex, 0, 0), "rubber", Color(0.07, 0.07, 0.07), false)
	var hx := edge * (w / 2.0 - 0.13)
	A.cyl(leafn, 0.016, 0.62, c + Vector3(hx, 0.02, face + 0.07), "brass", Color(0.82, 0.68, 0.42))
	for sy in [-0.27, 0.27]:
		A.cyl(leafn, 0.012, 0.07, c + Vector3(hx, 0.02 + sy, face + 0.035), "brass", Color(0.82, 0.68, 0.42), false, "z")
	A.cyl(leafn, 0.03, 0.012, c + Vector3(hx, -0.42, face + 0.006), "brass", Color(0.82, 0.68, 0.42), false, "z")   # lock escutcheon
	A.box(leafn, Vector3(0.012, 0.03, 0.006), c + Vector3(hx, -0.42, face + 0.014), "rubber", Color(0.05, 0.05, 0.05), false)
	# Roller hangers along the top, up into the track.
	for r in 2:
		var rx := -0.5 + r * 1.0
		A.box(leafn, Vector3(0.12, 0.14, 0.03), c + Vector3(rx, h / 2.0 + 0.04, 0.0), "metal", FRAME, false, 0.4)
		A.cyl(leafn, 0.035, 0.03, c + Vector3(rx, h / 2.0 + 0.11, 0.0), "metal", Color(0.4, 0.4, 0.4), false, "z")


## A truck/bogie: cast side frames with spring nests, axle boxes, brake shoes, a bolster,
## `axles` axles `spacing` apart, wheels on the rails (z = +-0.78). Optional traction motors.
func _bogie(parent: Node, x: float, axles: int, spacing: float, radius := 0.45, motors := false) -> void:
	var half := (axles - 1) * spacing / 2.0
	var y := radius
	if parent == self or parent == _flat or (parent != null and parent.get_parent() == self):
		for k in axles:   # (the flatcar's are moved with it: see add_storage_car)
			_axles.append(x - half + k * spacing + (parent.position.x if parent != self else 0.0))
	for s in [-1, 1]:
		var z: float = s * 1.0
		A.box(parent, Vector3(half * 2 + 0.9, 0.18, 0.12), Vector3(x, y + 0.08, z), "metal", FRAME, false, 0.6)
		A.box(parent, Vector3(half * 2 + 0.5, 0.1, 0.12), Vector3(x, y - 0.12, z), "metal", FRAME, false, 0.6)
		for k in axles:
			var ax := x - half + k * spacing
			A.box(parent, Vector3(0.3, 0.34, 0.2), Vector3(ax, y, z), "metal", Color(0.28, 0.27, 0.26), false, 0.4)
			A.cyl(parent, 0.07, 0.05, Vector3(ax, y, z + s * 0.11), "metal", Color(0.5, 0.48, 0.45), false, "z")
			for b in [-1, 1]:   # brake shoes
				if (k == 0 and b < 0) or (k == axles - 1 and b > 0) or axles == 2:
					A.box(parent, Vector3(0.08, 0.3, 0.12), Vector3(ax + b * (radius + 0.06), y, s * 0.78), "metal", Color(0.25, 0.25, 0.25), false)
		for k in axles - 1:   # spring nests between axles
			var mx := x - half + (k + 0.5) * spacing
			for dz in [-0.08, 0.08]:
				A.cyl(parent, 0.06, 0.24, Vector3(mx + dz, y + 0.05, z), "metal", Color(0.55, 0.52, 0.48))
			for r in 4:
				A.ring(parent, 0.075, 0.055, Vector3(mx, y - 0.04 + r * 0.06, z), "metal", Color(0.6, 0.58, 0.55))
	A.box(parent, Vector3(0.45, 0.28, 2.0), Vector3(x, y + 0.12, 0), "metal", FRAME, false, 0.6)   # bolster
	for k in axles:
		var ax := x - half + k * spacing
		A.cyl(parent, 0.08, 1.7, Vector3(ax, y, 0), "metal", Color(0.3, 0.3, 0.3), false, "z")   # axle
		if motors:
			A.cyl(parent, 0.28, 0.9, Vector3(ax + 0.25, y + 0.02, 0), "metal", Color(0.22, 0.24, 0.26), false, "z")
		for s in [-1, 1]:
			_wheel(Vector3(ax, y, s * 0.78), radius, parent)


## Knuckle coupler pointing along `dir` (+1 / -1 in x), with an air hose and cut lever.
func _coupler(parent: Node, x: float, dir: float) -> void:
	A.box(parent, Vector3(0.5, 0.2, 0.25), Vector3(x, 0.75, 0), "metal", FRAME, false)
	A.box(parent, Vector3(0.22, 0.32, 0.32), Vector3(x + dir * 0.3, 0.75, 0), "metal", Color(0.3, 0.29, 0.28), false)
	A.box(parent, Vector3(0.12, 0.3, 0.12), Vector3(x + dir * 0.42, 0.75, 0.1), "metal", Color(0.3, 0.29, 0.28), false)
	A.seg(parent, Vector3(x, 0.62, 0.35), Vector3(x + dir * 0.35, 0.4, 0.3), 0.035, 0.035, "rubber")
	A.cyl(parent, 0.05, 0.12, Vector3(x + dir * 0.38, 0.38, 0.3), "brass", Color.WHITE, false, "x")
	A.seg(parent, Vector3(x, 0.95, -0.3), Vector3(x, 0.95, -1.2), 0.015, 0.015, "metal", Color(0.5, 0.5, 0.5))


## Hanging boarding steps with side plates.
func _steps(parent: Node, x: float, z: float, w := 0.6) -> void:
	var s := signf(z)
	for i in 2:
		A.box(parent, Vector3(w, 0.04, 0.28), Vector3(x, 0.62 - i * 0.3, z), "grate", Color.WHITE, false, 0.3)
	for e in [-1, 1]:
		A.box(parent, Vector3(0.04, 0.55, 0.3), Vector3(x + e * w / 2, 0.55, z), "metal", FRAME, false)
	A.box(parent, Vector3(w, 0.03, 0.03), Vector3(x, 0.32, z + s * 0.14), "metal", RAIL, false)


## Left-to-right spans of x0..x1 minus the given [centre, width] holes.
func _spans(x0: float, x1: float, holes: Array) -> Array:
	var cuts := [[x0, x0]]
	var hs := holes.duplicate()
	hs.sort_custom(func(a, b): return a[0] < b[0])
	for h in hs:
		cuts.append([h[0] - h[1] / 2.0, h[0] + h[1] / 2.0])
	cuts.append([x1, x1])
	var out := []
	for i in cuts.size() - 1:
		if cuts[i + 1][0] - cuts[i][1] > 0.05:
			out.append([cuts[i][1], cuts[i + 1][0]])
	return out


# --- passenger-style car body (crew car + storage car share this) -------------------

## Everything on the outside of a car shell between x0 and x1: ribs, belt rail, letterboard,
## window frames, side sill, door tracks with the door leaves slid open, roof, underframe.
func _car_dress(parent: Node, x0: float, x1: float, doors: Array, windows: Array, back_windows: Array, title: String, number: String, slide: Array, kind := "maroon", tint := Color.WHITE) -> void:
	var xc := (x0 + x1) / 2.0
	var len := x1 - x0
	for s in [-1, 1]:
		var z: float = s * 2.23
		var holes: Array = (doors + windows) if s > 0 else back_windows
		var door_spans: Array = doors if s > 0 else []
		var leaves: Array = slide if s > 0 else []
		# Ribs, skipping holes and parked door leaves.
		var blocked := holes + leaves.map(func(l): return [l, 1.6])
		var x := x0 + 0.5
		while x < x1 - 0.3:
			var clear := true
			for h in blocked:
				if absf(x - h[0]) < h[1] / 2.0 + 0.1:
					clear = false
			if clear:
				A.box(parent, Vector3(0.07, WALL_H - 0.1, 0.04), Vector3(x, F + WALL_H / 2.0, z), kind, tint.darkened(0.2), false, 1.0)
			x += 0.95
		# Belt rail and window-sill band (broken by doors), letterboard above everything.
		for sp in _spans(x0, x1, door_spans):
			var w: float = sp[1] - sp[0]
			var c: float = (sp[0] + sp[1]) / 2.0
			A.box(parent, Vector3(w, 0.08, 0.05), Vector3(c, F + 0.92, z + s * 0.01), "metal", FRAME, false, 1.0)
		A.box(parent, Vector3(len - 0.1, 0.32, 0.03), Vector3(xc, F + 2.5, z + s * 0.01), "cream", CREAM, false, 2.0)
		A.box(parent, Vector3(len, 0.05, 0.06), Vector3(xc, F + 2.34, z + s * 0.02), "metal", FRAME, false, 1.0)
		var t := B.label(parent, title, Vector3(xc, F + 2.5, z + s * 0.035), 46, Color(0.32, 0.12, 0.08), "plate", 0.0055)
		t.rotation.y = 0.0 if s > 0 else PI
		var n := B.label(parent, number, Vector3(x1 - 1.2 if s > 0 else x0 + 1.2, F + 0.62, z + s * 0.02), 60, CREAM, "stencil", 0.006)
		n.rotation.y = 0.0 if s > 0 else PI
		# Window frames.
		for h in holes:
			if h[2] <= 0.0:
				continue
			var wx: float = h[0]
			var ww: float = h[1]
			var y0: float = F + h[2]
			var y1: float = F + h[3]
			A.box(parent, Vector3(ww + 0.16, 0.08, 0.1), Vector3(wx, y0 - 0.02, z + s * 0.03), "metal", FRAME, false)
			A.box(parent, Vector3(ww + 0.12, 0.06, 0.06), Vector3(wx, y1 + 0.03, z + s * 0.02), "metal", FRAME, false)
			for e in [-1, 1]:
				A.box(parent, Vector3(0.06, y1 - y0, 0.06), Vector3(wx + e * (ww / 2 + 0.03), (y0 + y1) / 2, z + s * 0.02), "metal", FRAME, false)
			A.box(parent, Vector3(0.03, y1 - y0, 0.04), Vector3(wx, (y0 + y1) / 2, z + s * 0.0), "metal", FRAME, false)   # mullion
		# Side sill (skirt) under the floor line.
		A.box(parent, Vector3(len, 0.32, 0.06), Vector3(xc, F - 0.18, s * 2.18), "metal", FRAME, false, 1.0)
		for k in int(len / 1.2):
			A.box(parent, Vector3(0.04, 0.3, 0.07), Vector3(x0 + 0.6 + k * 1.2, F - 0.18, s * 2.19), "metal", Color(0.3, 0.29, 0.28), false)
	# Door track over each platform door, the leaf slid open beside it, a step below.
	for k in doors.size():
		var d: Array = doors[k]
		A.box(parent, Vector3(3.4, 0.08, 0.1), Vector3(d[0] + (slide[k] - d[0]) / 2.0, F + 2.32, 2.3), "metal", FRAME, false)
		for jx in [-0.79, 0.79]:   # the opening's jambs, and a drip rail over it
			A.box(parent, Vector3(0.07, 2.32, 0.05), Vector3(d[0] + jx, F + 1.16, 2.235), "metal", FRAME.lightened(0.1), false, 0.5)
		A.box(parent, Vector3(1.8, 0.04, 0.08), Vector3(d[0], F + 2.45, 2.26), "metal", FRAME, false, 0.5)
		# The sliding leaf: its own moving piece (it shuts when the train pulls out, see set_doors).
		var leafn := AnimatableBody3D.new()
		leafn.sync_to_physics = false
		leafn.collision_layer = 1
		leafn.collision_mask = 0
		parent.add_child(leafn)
		leafn.set_meta("live", true)
		var leaf := Vector3(slide[k], F + 1.15, 2.3)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(1.5, 2.28, 0.08)
		cs.shape = bs
		cs.position = leaf
		leafn.add_child(cs)
		_door_leaf(leafn, leaf, kind, tint.darkened(0.08), -signf(slide[k] - d[0]))
		_door_leaves.append([leafn, d[0] - slide[k]])
		_steps(parent, d[0], 2.38, 1.3)
	_roof(parent, x0, x1)
	# Underframe between the trucks: truss rods, air reservoirs, battery box, brake cylinder.
	for s in [-1, 1]:
		var z: float = s * 1.25
		A.seg(parent, Vector3(x0 + 2.4, 0.6, z), Vector3(xc - 1.4, 0.18, z), 0.025, 0.025, "metal", FRAME)
		A.seg(parent, Vector3(xc - 1.4, 0.18, z), Vector3(xc + 1.4, 0.18, z), 0.025, 0.025, "metal", FRAME)
		A.seg(parent, Vector3(xc + 1.4, 0.18, z), Vector3(x1 - 2.4, 0.6, z), 0.025, 0.025, "metal", FRAME)
		for qx in [xc - 1.4, xc + 1.4]:
			A.box(parent, Vector3(0.1, 0.36, 0.1), Vector3(qx, 0.36, z), "metal", FRAME, false)
	A.cyl(parent, 0.2, 1.6, Vector3(xc - 0.6, 0.38, 0.6), "metal", Color(0.35, 0.36, 0.38), false, "x")
	A.cyl(parent, 0.16, 1.2, Vector3(xc + 1.0, 0.4, -0.7), "metal", Color(0.35, 0.36, 0.38), false, "x")
	A.box(parent, Vector3(1.0, 0.4, 0.7), Vector3(xc + 0.6, 0.35, 0.75), "metal", Color(0.22, 0.24, 0.22), false, 0.6)
	A.box(parent, Vector3(0.8, 0.06, 0.5), Vector3(xc + 0.6, 0.57, 0.75), "metal", Color(0.3, 0.3, 0.3), false)
	A.cyl(parent, 0.15, 0.45, Vector3(xc - 2.0, 0.42, -0.4), "metal", FRAME, false, "x")
	A.seg(parent, Vector3(x0 + 1.0, 0.55, -0.9), Vector3(x1 - 1.0, 0.55, -0.9), 0.02, 0.02, "metal", Color(0.4, 0.4, 0.4))   # train line
	# Ends: corner posts, end ladder, marker lamps, coupler.
	for e in [[x0, -1.0], [x1, 1.0]]:
		var ex: float = e[0]
		var dir: float = e[1]
		for s in [-1, 1]:
			A.box(parent, Vector3(0.12, WALL_H + 0.1, 0.12), Vector3(ex, F + WALL_H / 2.0, s * 2.18), "metal", FRAME, false, 0.6)
		_coupler(parent, ex + dir * 0.2, dir)


## Clerestory-less barrel roof: eight curved strips, gutters, a plank running board, vents.
func _roof(parent: Node, x0: float, x1: float) -> void:
	var xc := (x0 + x1) / 2.0
	var len := x1 - x0 + 0.3
	var rise := 0.5
	var half := 2.3
	for i in 8:
		var a0 := PI * i / 8.0
		var a1 := PI * (i + 1) / 8.0
		var p0 := Vector2(cos(a0) * half, F + WALL_H + sin(a0) * rise)
		var p1 := Vector2(cos(a1) * half, F + WALL_H + sin(a1) * rise)
		var d := p1 - p0
		var strip := A.box(parent, Vector3(len, 0.06, d.length() + 0.02), Vector3(xc, (p0.y + p1.y) / 2.0, (p0.x + p1.x) / 2.0), "maroon", Color(0.55, 0.48, 0.46), false, 2.0)
		strip.rotation.x = atan2(-d.y, d.x)
	for s in [-1, 1]:
		A.box(parent, Vector3(len, 0.06, 0.08), Vector3(xc, F + WALL_H + 0.02, s * 2.32), "metal", FRAME, false)   # gutter
	for k in int(len / 1.9):   # seam straps over the curve
		var sx := x0 + 0.8 + k * 1.9
		for i in 8:
			var a0 := PI * i / 8.0
			var a1 := PI * (i + 1) / 8.0
			var p0 := Vector2(cos(a0) * half, F + WALL_H + sin(a0) * rise + 0.035)
			var p1 := Vector2(cos(a1) * half, F + WALL_H + sin(a1) * rise + 0.035)
			var d := p1 - p0
			var st := A.box(parent, Vector3(0.06, 0.03, d.length() + 0.02), Vector3(sx, (p0.y + p1.y) / 2.0, (p0.x + p1.x) / 2.0), "metal", Color(0.35, 0.33, 0.32), false)
			st.rotation.x = atan2(-d.y, d.x)
	A.box(parent, Vector3(len - 0.6, 0.04, 0.5), Vector3(xc, F + WALL_H + rise + 0.05, 0), "wood", Color(0.6, 0.55, 0.5), false, 0.6)   # running board
	for vx in [x0 + 2.5, xc, x1 - 2.5]:
		A.cyl(parent, 0.17, 0.7, Vector3(vx, F + WALL_H + rise + 0.18, 0.7), "metal", Color(0.5, 0.5, 0.5), false, "x")   # torpedo vent
		A.box(parent, Vector3(0.6, 0.08, 0.22), Vector3(vx, F + WALL_H + rise + 0.04, 0.7), "metal", FRAME, false)
	A.cyl(parent, 0.09, 0.4, Vector3(x1 - 1.0, F + WALL_H + rise + 0.2, -0.6), "rust", Color.WHITE)   # stove pipe
	A.cyl(parent, 0.14, 0.05, Vector3(x1 - 1.0, F + WALL_H + rise + 0.42, -0.6), "rust", Color.WHITE)


# --- crew car -------------------------------------------------------------------

func _car() -> void:
	var door_holes := [[-4.5, 1.5, 0.0, 2.3], [2.6, 1.5, 0.0, 2.3]]
	var side_windows := [[-6.6, 1.0, 1.0, 2.0], [-1.2, 1.0, 1.0, 2.0], [5.0, 1.1, 1.0, 2.0], [7.2, 0.9, 1.0, 2.0]]
	var back_windows := [[4.0, 1.1, 1.0, 2.0], [6.6, 1.0, 1.0, 2.0], [-6.0, 1.0, 1.0, 2.0]]
	# Exterior paint skin + interior red skin.
	A.wall(self, -8.2, 8.2, 2.18, WALL_H, 0.08, door_holes + side_windows, "maroon", Color.WHITE, true, F)
	A.wall(self, -8.2, 8.2, 2.06, WALL_H, 0.08, door_holes + side_windows, "enamel", SAGE, true, F, false, 1.0)
	A.wall(self, -8.2, 8.2, -2.18, WALL_H, 0.08, back_windows, "maroon", Color.WHITE, true, F)
	A.wall(self, -8.2, 8.2, -2.06, WALL_H, 0.08, back_windows, "enamel", SAGE, true, F, false, 1.0)
	A.wall(self, -2.2, 2.2, 8.2, WALL_H, 0.15, [[0.0, 1.6, 1.0, 2.0]], "maroon", Color.WHITE, false, F)
	A.wall(self, -2.2, 2.2, -8.2, WALL_H, 0.15, [[0.0, 1.2, 0.0, 2.3]], "maroon", Color.WHITE, false, F)
	_rear_lock = A.box(self, Vector3(0.1, 2.3, 1.2), Vector3(-8.15, F + 1.15, 0), "riveted", Color(0.6, 0.55, 0.5), true, 1.0)
	var lock_sign := B.label(_rear_lock, "STORAGE CAR\nNOT INSTALLED", Vector3(0.07, 0.3, 0), 28, Color(0.95, 0.8, 0.35), "stencil", 0.003)
	lock_sign.rotation.y = PI / 2
	# Varnished tongue-and-groove up to the waist, a brass rail along its top.
	A.wall(self, -8.1, 8.1, 2.0, 1.0, 0.03, door_holes, "panelling", Color.WHITE, true, F, false, 0.6)
	A.wall(self, -8.1, 8.1, -2.0, 1.0, 0.03, [], "panelling", Color.WHITE, true, F, false, 0.6)
	for seg in [[-8.1, -5.25], [-3.75, 1.85], [3.35, 8.1]]:
		A.box(self, Vector3(seg[1] - seg[0], 0.035, 0.05), Vector3((seg[0] + seg[1]) / 2.0, F + 1.0, 1.975), "wood", Color(0.5, 0.36, 0.26), false, 0.5)
	A.box(self, Vector3(16.2, 0.035, 0.05), Vector3(0, F + 1.0, -1.975), "wood", Color(0.5, 0.36, 0.26), false, 0.5)
	# The end walls inside, dressed the same.
	for e in [[8.11, [[0.0, 1.6, 1.0, 2.0]]], [-8.11, [[0.0, 1.2, 0.0, 2.3]]]]:
		A.wall(self, -2.0, 2.0, e[0], WALL_H, 0.03, e[1], "enamel", SAGE, false, F, false, 1.0)
		A.wall(self, -2.0, 2.0, e[0] - signf(e[0]) * 0.02, 1.0, 0.03, e[1], "panelling", Color.WHITE, false, F, false, 0.6)
	for w in side_windows + door_holes:
		if w[2] > 0.0:
			_glass(Vector3(w[0], F + (w[2] + w[3]) / 2.0, 2.12), Vector3(w[1], w[3] - w[2], 0.02))
	for w in back_windows:
		_glass(Vector3(w[0], F + (w[2] + w[3]) / 2.0, -2.12), Vector3(w[1], w[3] - w[2], 0.02))
	# Floor, chassis, ceiling ribs.
	A.box(self, Vector3(16.4, 0.12, 4.2), Vector3(0, F - 0.06, 0), "linoleum", Color.WHITE, true, 0.6)
	A.box(self, Vector3(15.2, 0.012, 0.95), Vector3(-0.3, F + 0.006, 0.15), "runner", Color.WHITE, false, 0.8)   # a rubber runner down the aisle
	A.box(self, Vector3(16.8, 0.35, 3.4), Vector3(0, 0.7, 0), "rust", Color(0.6, 0.6, 0.6), true)
	A.box(self, Vector3(16.4, 0.08, 4.4), Vector3(0, F + WALL_H + 0.04, 0), "metal", Color(0.5, 0.45, 0.42), true)
	_headliner()
	# Door frames + grab irons.
	for d in door_holes:
		for s in [-1, 1]:
			A.box(self, Vector3(0.08, 2.4, 0.06), Vector3(d[0] + s * 0.8, F + 1.2, 2.25), "metal", FRAME, false)
			A.cyl(self, 0.025, 1.2, Vector3(d[0] + s * 0.95, F + 1.0, 2.36), "metal", RAIL)
	_car_dress(self, -8.2, 8.2, door_holes, side_windows, back_windows, "BUREAU OF RECLAIMED MATERIALS", "BRM 207", [-2.95, 1.0])
	# End details: gangway diaphragm at the back, a ladder and red markers.
	for dz in [-0.75, 0.75]:
		A.box(self, Vector3(0.3, 2.4, 0.1), Vector3(-8.4, F + 1.2, dz), "rubber", Color.WHITE, false, 0.5)
	A.box(self, Vector3(0.3, 0.1, 1.6), Vector3(-8.4, F + 2.4, 0), "rubber", Color.WHITE, false, 0.5)
	for s in [-1, 1]:
		var lamp := Vector3(-8.32, F + 2.3, s * 1.9)
		A.box(self, Vector3(0.12, 0.2, 0.16), lamp, "metal", FRAME, false)
		A.glow(self, Vector3(0.02, 0.12, 0.1), lamp + Vector3(-0.07, 0, 0), Color(1, 0.12, 0.08), 3.0)
	for k in 8:
		A.box(self, Vector3(0.04, 0.04, 0.45), Vector3(-8.33, 0.55 + k * 0.35, -1.55), "metal", RAIL, false)
	for dz in [-1.33, -1.77]:
		A.box(self, Vector3(0.04, 3.0, 0.04), Vector3(-8.33, 1.7, dz), "metal", RAIL, false)
	_bogie(self, -4.9, 2, 1.3)
	_bogie(self, 4.9, 2, 1.3)


## The terminal desk (its own frame: top at 0.79, the sitter on +z): a steel office desk in grey-green
## enamel with an aluminium edge, a drawer pedestal, a green blotter, keyboards, a mug, papers, a lamp.
func _desk(desk: Node3D) -> void:
	var dk := Color(0.5, 0.56, 0.53)
	var alu := Color(0.72, 0.73, 0.74)
	A.box(desk, Vector3(2.2, 0.04, 0.85), Vector3(0, 0.77, 0), "enamel", dk, false, 0.5)
	for sz in [-1, 1]:
		A.box(desk, Vector3(2.22, 0.045, 0.015), Vector3(0, 0.77, sz * 0.43), "enamel", alu, false, 0.3)
	for sx in [-1, 1]:
		A.box(desk, Vector3(0.015, 0.045, 0.86), Vector3(sx * 1.105, 0.77, 0), "enamel", alu, false, 0.3)
	A.box(desk, Vector3(1.0, 0.004, 0.5), Vector3(-0.3, 0.792, 0.08), "canvas", Color(0.22, 0.32, 0.26), false, 0.4)   # blotter
	for sx in [-1, 1]:
		A.box(desk, Vector3(0.02, 0.006, 0.5), Vector3(-0.3 + sx * 0.5, 0.793, 0.08), "leather", Color.WHITE, false, 0.2)
	A.box(desk, Vector3(0.04, 0.75, 0.8), Vector3(-1.08, 0.375, 0), "enamel", dk, false, 0.5)   # end panel
	A.box(desk, Vector3(2.1, 0.45, 0.02), Vector3(0, 0.5, -0.4), "enamel", dk.darkened(0.08), false, 0.5)   # modesty panel
	A.box(desk, Vector3(0.52, 0.75, 0.8), Vector3(0.82, 0.375, 0), "enamel", dk, false, 0.5)   # drawer pedestal
	for k in 3:
		var y := 0.62 - k * 0.22
		A.box(desk, Vector3(0.48, 0.2, 0.012), Vector3(0.82, y, 0.405), "enamel", dk.lightened(0.04), false, 0.4)
		A.box(desk, Vector3(0.16, 0.022, 0.02), Vector3(0.82, y + 0.05, 0.42), "metal", alu, false, 0.2)   # pull
		A.box(desk, Vector3(0.06, 0.03, 0.004), Vector3(0.82, y - 0.02, 0.412), "paper", Color(0.9, 0.88, 0.8), false, 0.2)   # label slot
	A.box(desk, Vector3(2.16, 0.05, 0.78), Vector3(0, 0.025, 0), "rubber", Color.WHITE, false, 0.5)   # kick plate
	# A keyboard in front of each screen.
	for kx in [-0.35, 0.6]:
		A.box(desk, Vector3(0.44, 0.025, 0.16), Vector3(kx, 0.805, 0.24), "plastic", Color(0.72, 0.7, 0.64), false, 0.3)
		A.box(desk, Vector3(0.41, 0.012, 0.13), Vector3(kx, 0.823, 0.24), "keys", Color.WHITE, false, 0.12)
	# A mug with a spoon in it, a stack of forms, a clipboard, pencils.
	var mug := Vector3(0.18, 0.79, 0.12)
	A.cyl(desk, 0.042, 0.1, mug + Vector3(0, 0.05, 0), "enamel", Color(0.92, 0.92, 0.88), false)
	A.ring(desk, 0.032, 0.018, mug + Vector3(0.05, 0.05, 0), "enamel", Color(0.92, 0.92, 0.88), Vector3(0, 0, PI / 2))
	A.cyl(desk, 0.038, 0.004, mug + Vector3(0, 0.098, 0), "rust", Color(0.4, 0.25, 0.15), false)   # (coffee)
	A.seg(desk, mug + Vector3(0.01, 0.06, 0), mug + Vector3(0.03, 0.15, -0.01), 0.003, 0.003, "metal", alu)
	for i in 4:
		var f := A.box(desk, Vector3(0.21, 0.004, 0.29), Vector3(0.75, 0.794 + i * 0.005, 0.1), "paper", Color(0.92, 0.9, 0.82).darkened(i * 0.03), false, 0.2)
		f.rotation.y = 0.15 * (i - 1.5)
	A.box(desk, Vector3(0.23, 0.008, 0.32), Vector3(-0.95, 0.796, 0.18), "board", Color(0.6, 0.45, 0.3), false, 0.3)   # clipboard
	A.box(desk, Vector3(0.21, 0.003, 0.28), Vector3(-0.95, 0.801, 0.19), "paper", Color(0.92, 0.9, 0.82), false, 0.2)
	A.box(desk, Vector3(0.1, 0.012, 0.03), Vector3(-0.95, 0.805, 0.04), "metal", alu, false, 0.2)
	for k in 2:
		var pen := A.cyl(desk, 0.004, 0.17, Vector3(-0.62 + k * 0.03, 0.8, 0.3), "paint", Color(0.85, 0.75, 0.2) if k == 0 else Color(0.2, 0.3, 0.6), false, "x")
		pen.rotation.y = 0.3 + k * 0.2
	# An articulated lamp at the back corner, lit.
	var lb := Vector3(1.0, 0.79, -0.28)
	A.cyl(desk, 0.07, 0.025, lb + Vector3(0, 0.012, 0), "enamel", Color(0.2, 0.22, 0.2), false)
	A.seg(desk, lb + Vector3(0, 0.02, 0), lb + Vector3(-0.08, 0.36, 0.05), 0.008, 0.008, "metal", alu)
	A.seg(desk, lb + Vector3(-0.08, 0.36, 0.05), lb + Vector3(-0.32, 0.42, 0.15), 0.008, 0.008, "metal", alu)
	var shade := A.cyl(desk, 0.075, 0.12, lb + Vector3(-0.34, 0.38, 0.16), "enamel", Color(0.2, 0.22, 0.2), false)
	shade.rotation.z = 0.5
	A.sphere(desk, 0.025, lb + Vector3(-0.36, 0.34, 0.17), "cream", Color(1, 0.92, 0.75), 6.0)
	B.omni(desk, lb + Vector3(-0.38, 0.28, 0.2), Color(1, 0.88, 0.7), 0.6, 2.2)


## A swivel chair: five-star base on casters, a gas post, a padded seat and back.
func _chair(at: Vector3, yaw: float) -> void:
	var r := Node3D.new()
	add_child(r)
	r.position = at
	r.rotation.y = yaw
	for k in 5:
		var a := TAU * k / 5.0
		var tip := Vector3(cos(a) * 0.3, 0.06, sin(a) * 0.3)
		A.seg(r, Vector3(0, 0.08, 0), tip, 0.02, 0.016, "metal", Color(0.2, 0.2, 0.2))
		A.sphere(r, 0.03, tip + Vector3(0, -0.03, 0), "rubber", Color.WHITE)
	A.cyl(r, 0.025, 0.36, Vector3(0, 0.26, 0), "metal", Color(0.5, 0.5, 0.5))
	A.box(r, Vector3(0.46, 0.08, 0.44), Vector3(0, 0.47, 0), "leather", Color(0.75, 0.75, 0.75), false, 0.4)
	A.box(r, Vector3(0.44, 0.42, 0.06), Vector3(0, 0.78, 0.22), "leather", Color(0.75, 0.75, 0.75), false, 0.4)
	A.box(r, Vector3(0.05, 0.3, 0.03), Vector3(0, 0.6, 0.24), "metal", Color(0.3, 0.3, 0.3), false, 0.3)


## The ceiling inside: a cream headliner on brass ribs, flat down the middle and curving down to the
## walls; luggage racks over the windows; a conduit along the top of the back wall.
func _headliner() -> void:
	var top := F + WALL_H - 0.1
	var low := F + WALL_H - 0.42
	A.box(self, Vector3(16.3, 0.03, 2.4), Vector3(0, top, 0), "headliner", Color.WHITE, false, 1.0)
	for s in [-1, 1]:
		var slope := A.box(self, Vector3(16.3, 0.03, 0.9), Vector3(0, (top + low) / 2.0, s * 1.6), "headliner", Color(0.95, 0.95, 0.95), false, 1.0)
		slope.rotation.x = s * atan2(top - low, 0.8)
	for i in 9:   # brass ribs under it
		var x := -8.0 + i * 2.0
		A.box(self, Vector3(0.05, 0.03, 2.42), Vector3(x, top - 0.02, 0), "brass", Color(0.8, 0.66, 0.4), false, 0.5)
		for s in [-1, 1]:
			var r := A.box(self, Vector3(0.05, 0.03, 0.92), Vector3(x, (top + low) / 2.0 - 0.02, s * 1.6), "brass", Color(0.8, 0.66, 0.4), false, 0.5)
			r.rotation.x = s * atan2(top - low, 0.8)
	# Luggage racks over the windows: brass brackets carrying a row of rods.
	for seg in [[-7.6, -5.4], [-3.6, 1.7], [3.5, 7.7]]:
		var xc: float = (seg[0] + seg[1]) / 2.0
		var ln: float = seg[1] - seg[0]
		for k in 5:
			A.cyl(self, 0.008, ln, Vector3(xc, F + 2.05, 1.62 + k * 0.08), "brass", Color(0.8, 0.66, 0.4), false, "x")
		for bx in range(int(ceil(ln / 1.2)) + 1):
			var x: float = seg[0] + minf(bx * 1.2, ln)
			A.box(self, Vector3(0.03, 0.03, 0.4), Vector3(x, F + 2.05, 1.8), "brass", Color(0.8, 0.66, 0.4), false, 0.3)
			A.seg(self, Vector3(x, F + 2.05, 1.62), Vector3(x, F + 2.3, 1.98), 0.008, 0.008, "brass", Color(0.8, 0.66, 0.4))
	# Conduit along the top of the back wall, junction boxes on it.
	A.cyl(self, 0.022, 16.0, Vector3(0, F + 2.28, -1.93), "metal", Color(0.45, 0.47, 0.45), false, "x")
	for x in [-6.0, -1.0, 4.4]:
		A.box(self, Vector3(0.14, 0.12, 0.06), Vector3(x, F + 2.28, -1.94), "metal", Color(0.4, 0.42, 0.4), false, 0.3)


## Things on the walls: Bureau notices, heater grilles along the floor, an extinguisher, first aid.
func _fittings() -> void:
	var notices := [["SCRAP IS\nTOMORROW", Color(0.75, 0.2, 0.12)], ["REPORT\nANOMALIES", Color(0.2, 0.32, 0.45)], ["MIND THE GAP\nMIND THE DARK", Color(0.25, 0.38, 0.25)]]
	var at := [-2.7, 0.55, 3.9]
	for i in 3:
		var p := Vector3(at[i], F + 1.62, 1.965)
		A.box(self, Vector3(0.56, 0.74, 0.02), p, "wood", Color(0.5, 0.35, 0.22), false, 0.4)   # frame
		A.box(self, Vector3(0.5, 0.68, 0.006), p + Vector3(0, 0, -0.012), "paper", Color(0.92, 0.88, 0.76), false, 0.3)
		A.box(self, Vector3(0.44, 0.22, 0.004), p + Vector3(0, 0.17, -0.016), "cream", notices[i][1], false, 0.3)
		var l := B.label(self, notices[i][0], p + Vector3(0, -0.12, -0.017), 26, Color(0.15, 0.13, 0.11), "stencil", 0.0026)
		l.rotation.y = PI
		var brm := B.label(self, "B.R.M.", p + Vector3(0, 0.17, -0.019), 22, Color(0.95, 0.92, 0.85), "stencil", 0.003)
		brm.rotation.y = PI
	for x in [-6.4, -2.0, 1.0, 4.4]:   # heater grilles at the foot of the walls
		for sd in ([1.0, -1.0] if x > -3.0 else [1.0]):
			A.box(self, Vector3(1.0, 0.18, 0.04), Vector3(x, F + 0.14, sd * 1.96), "grille", Color(0.55, 0.55, 0.52), false, 0.3)
	A.cyl(self, 0.07, 0.42, Vector3(1.6, F + 0.42, 1.9), "paint", Color(1.4, 0.4, 0.3), false)   # extinguisher on its bracket
	A.cyl(self, 0.03, 0.08, Vector3(1.6, F + 0.67, 1.9), "metal", Color(0.2, 0.2, 0.2), false)
	A.box(self, Vector3(0.12, 0.04, 0.06), Vector3(1.6, F + 0.5, 1.98), "metal", Color(0.3, 0.3, 0.3), false)
	var aid := Vector3(-0.3, F + 1.55, -1.95)   # first aid box (clear of the charging board)
	A.box(self, Vector3(0.42, 0.34, 0.12), aid, "cream", Color(0.9, 0.9, 0.86), false, 0.4)
	A.box(self, Vector3(0.22, 0.06, 0.005), aid + Vector3(0, 0, 0.062), "cream", Color(0.8, 0.12, 0.1), false, 0.2)
	A.box(self, Vector3(0.06, 0.22, 0.005), aid + Vector3(0, 0, 0.062), "cream", Color(0.8, 0.12, 0.1), false, 0.2)


## Glowing monospace text for the train's displays.
func _mono_label(px: int, pixel: float, c: Color) -> Label3D:
	var l := Label3D.new()
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Menlo", "Consolas", "DejaVu Sans Mono", "monospace"])
	f.font_weight = 600
	l.font = f
	f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	f.hinting = TextServer.HINTING_NONE
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	l.font_size = px / 3          # rendered small, shown big: fat CRT pixels
	l.pixel_size = pixel * 3.0
	l.modulate = c
	l.outline_size = 0
	l.shaded = false
	l.double_sided = false
	return l


## A clock hand on a live pivot (kept out of the mesh merge so it can turn).
func _hand(at: Vector3, length: float, width: float) -> Node3D:
	var pivot := Node3D.new()
	add_child(pivot)
	pivot.position = at
	Merge.live(pivot)
	A.box(pivot, Vector3(width, length, 0.004), Vector3(0, length * 0.42, 0), "metal", Color(0.06, 0.05, 0.05), false, 0.2)
	A.box(pivot, Vector3(width * 0.8, length * 0.22, 0.004), Vector3(0, -length * 0.12, 0), "metal", Color(0.06, 0.05, 0.05), false, 0.2)
	return pivot


func set_clock(hours: float, place: String) -> void:
	if not _digits.is_empty():
		_show_digital(hours, place == "CHECKPOINT")
	var h := fmod(hours, 12.0)
	_hour_hand.rotation.z = -TAU * h / 12.0
	_min_hand.rotation.z = -TAU * fmod(hours, 1.0)
	if place != _place:
		_place = place
		if is_instance_valid(_plate_text):
			_plate_text.queue_free()
		_plate_text = B.label(self, place, _plate_at + Vector3(0, -0.005, 0.018), 48, Color(0.2, 0.16, 0.12), "plate", 0.0015)
		_plate_text.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _glass(pos: Vector3, size: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = A.rain_glass()
	add_child(mi)
	mi.position = pos


# --- interior -------------------------------------------------------------------------

func _interior(open_terminal: Callable, rng: RandomNumberGenerator) -> void:
	# Terminal desk against the back wall, front section.
	var desk := StaticBody3D.new()
	add_child(desk)
	desk.position = Vector3(6.5, F, -1.55)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(2.2, 0.8, 0.85)
	cs.shape = sh
	cs.position.y = 0.4
	desk.add_child(cs)
	_desk(desk)
	var mon := Node3D.new()
	desk.add_child(mon)
	mon.position = Vector3(-0.35, 0.81, -0.05)
	mon.rotation.y = PI
	A.crt(mon, Vector3.ZERO, true, Color(0.09, 0.04, 0.012))   # dark phosphor; the text glows on it
	screen_label = _mono_label(30, 0.00052, Color(1, 0.68, 0.28))
	add_child(screen_label)
	screen_label.position = Vector3(6.15 - 0.17, F + 1.06 + 0.13, -1.343)   # top-left of the screen
	screen_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	screen_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	screen_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	screen_label.width = 220.0
	B.interactable(self, Vector3(0.44, 0.33, 0.03), Vector3(6.15, F + 1.06, -1.33), Color(0, 0, 0, 0), "Use terminal", open_terminal).shared = false   # your own screen
	var mon2 := Node3D.new()
	desk.add_child(mon2)
	mon2.position = Vector3(0.6, 0.81, -0.05)
	mon2.rotation.y = PI
	A.crt(mon2, Vector3.ZERO, true, Color(0.25, 0.12, 0.04))
	market_label = _mono_label(30, 0.00085, Color(1, 0.65, 0.25))
	add_child(market_label)
	market_label.position = Vector3(7.1, F + 1.06, -1.32)
	# Clock, chalkboard, charger, control panel, horn lever.
	# Old railway clock on a wall bracket: brass bezel, yellowed enamel dial, black hands that move.
	var ck := Vector3(7.62, F + 1.9, -1.96)   # (under the conduit and the headliner's curve, beside the window, over the monitors)
	A.box(self, Vector3(0.08, 0.06, 0.12), ck + Vector3(0, 0.24, -0.02), "metal", Color(0.25, 0.24, 0.22), false)
	A.cyl(self, 0.215, 0.08, ck + Vector3(0, 0, 0.03), "brass", Color(0.8, 0.7, 0.55), false, "z")
	A.ring(self, 0.215, 0.19, ck + Vector3(0, 0, 0.075), "brass", Color.WHITE, Vector3(PI / 2, 0, 0))
	A.cyl(self, 0.19, 0.01, ck + Vector3(0, 0, 0.072), "paper", Color(0.9, 0.85, 0.7), false, "z")
	for k in 60:
		var a := TAU * k / 60.0
		var big := k % 5 == 0
		A.box(self, Vector3(0.012 if big else 0.005, 0.035 if big else 0.014, 0.004), ck + Vector3(sin(a) * 0.165, cos(a) * 0.165, 0.079), "metal", Color(0.08, 0.07, 0.06), false, 0.2, Vector3(0, 0, -a))
	var maker := B.label(self, "B.R.M.", ck + Vector3(0, 0.07, 0.08), 24, Color(0.2, 0.12, 0.08), "plate", 0.0018)
	maker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hour_hand = _hand(ck + Vector3(0, 0, 0.083), 0.1, 0.016)
	_min_hand = _hand(ck + Vector3(0, 0, 0.087), 0.15, 0.01)
	A.sphere(self, 0.014, ck + Vector3(0, 0, 0.09), "brass")
	var cover = A.cyl(self, 0.19, 0.005, ck + Vector3(0, 0, 0.095), "metal", Color.WHITE, false, "z")
	cover.material_override = A.glass()
	# Enamel station plate on hooks beside it; the name is repainted at every stop.
	_plate_at = Vector3(5.3, F + 1.95, -1.955)
	for hx in [-0.3, 0.3]:
		A.seg(self, _plate_at + Vector3(hx, 0.3, -0.02), _plate_at + Vector3(hx * 0.8, 0.12, 0.0), 0.006, 0.006, "metal", Color(0.3, 0.3, 0.3))
	A.box(self, Vector3(0.9, 0.24, 0.025), _plate_at, "cream", Color(0.24, 0.34, 0.28), false, 0.5)
	A.box(self, Vector3(0.84, 0.18, 0.004), _plate_at + Vector3(0, 0, 0.014), "cream", Color(0.86, 0.82, 0.68), false, 0.5)
	for bx in [-0.42, 0.42]:
		A.sphere(self, 0.01, _plate_at + Vector3(bx, 0, 0.016), "metal", Color(0.7, 0.7, 0.68))
	A.box(self, Vector3(1.9, 1.15, 0.05), Vector3(3.6, F + 1.6, -1.99), "wood", Color.WHITE, false, 1.0)
	A.box(self, Vector3(1.75, 1.0, 0.02), Vector3(3.6, F + 1.6, -1.96), "board", Color.WHITE, false)
	var chalk := B.label(self, "BUREAU OF RECLAIMED MATERIALS\n\n- store scrap in the cargo end\n- train leaves at 24:00 sharp\n- do NOT look at the mannequins\n\nquota is quota.", Vector3(3.6, F + 1.6, -1.94), 40, Color(0.9, 0.92, 0.85), "chalk", 0.0022)
	_control_desk()
	_fittings()
	_chair(Vector3(6.3, F, -0.45), 0.25)
	A.locker(self, Vector3(7.65, F, -0.6), PI / 2)
	# Lighting: caged ceiling lamps, one hanging lamp in the cargo end.
	for x in [-5.0, 0.5, 5.5]:
		A.cyl(self, 0.16, 0.05, Vector3(x, F + 2.58, 0), "brass", Color(0.8, 0.66, 0.4), false)   # ceiling rose
		A.sphere(self, 0.12, Vector3(x, F + 2.45, 0), "cream", Color(1, 0.92, 0.78), 5.0)
		for a in 4:
			var bar := A.box(self, Vector3(0.02, 0.25, 0.02), Vector3(x, F + 2.45, 0) + Vector3(0.14, 0, 0).rotated(Vector3.UP, a * PI / 2), "metal", Color(0.3, 0.3, 0.3), false)
			bar.rotation.y = a * PI / 2
		B.omni(self, Vector3(x, F + 2.2, 0), Color(1, 0.88, 0.74), 1.0, 7.5)
	# Cargo end: shelving, crates, barrel, bench.
	for x in [-6.6, -4.2, -1.8]:
		A.shelf_unit(self, Vector3(x, F, -1.72), 0.0, rng, 2.25, 2.2, 0.5)
	var scrap_sign := B.label(self, "STORE SCRAP HERE", Vector3(-4.2, F + 2.45, -1.97), 40, Color(0.95, 0.9, 0.75), "stencil", 0.004)
	A.crate(self, Vector3(-7.5, F, 1.5), 0.75, rng)
	A.crate(self, Vector3(-7.45, F + 0.75, 1.5), 0.5, rng, false)
	A.barrel(self, Vector3(-7.5, F, 0.55), rng)
	A.box(self, Vector3(1.8, 0.45, 0.45), Vector3(-0.8, F + 0.225, 1.72), "wood", Color.WHITE, true, 1.0)


## The engineer's desk at the front of the crew car (it faces -x, into the car): an instrument panel
## with live gauges (engine RPM, speed, brake pipe, load amps, fuel, oil), warning lamps, a throttle
## quadrant and the horn valve.
func _control_desk() -> void:
	var body := Color(0.4, 0.45, 0.43)
	var face := Color(0.13, 0.14, 0.14)
	var chrome := Color(0.78, 0.79, 0.8)
	var plate := Color(0.88, 0.85, 0.74)
	var z0 := -0.25
	var z1 := 1.45
	var zc := (z0 + z1) / 2.0
	var wz := z1 - z0
	# The console: a painted cabinet standing clear of the front wall, its top a desk sloping up
	# toward the window (front edge x 7.6 at waist height, back edge x 8.05 a little higher).
	var front := 7.6
	var back := 8.05
	var y0 := F + 0.85
	var y1 := F + 1.18
	A.box(self, Vector3(back - front, 0.85, wz), Vector3((front + back) / 2.0, F + 0.425, zc), "enamel", body, true, 0.6)
	A.box(self, Vector3(back - front + 0.01, 0.07, wz + 0.01), Vector3((front + back) / 2.0, F + 0.035, zc), "rubber", Color.WHITE, false, 0.4)   # kick plate
	for zs in [z0 - 0.015, z1 + 0.015]:   # side cheeks, following the slope
		var ch := A.prism(self, Vector3(back - front, y1 - y0, 0.03), Vector3((front + back) / 2.0, (y0 + y1) / 2.0, zs), "enamel", body)
		(ch.mesh as PrismMesh).left_to_right = 1.0
	A.box(self, Vector3(0.03, y1 - y0, wz + 0.06), Vector3(back - 0.015, (y0 + y1) / 2.0, zc), "enamel", body, false, 0.6)   # back
	# The sloped instrument face.
	var panel := Node3D.new()
	add_child(panel)
	var d := Vector2(back - front, y1 - y0)
	panel.position = Vector3((front + back) / 2.0, (y0 + y1) / 2.0 + 0.012, zc)
	panel.rotation.z = atan2(-d.x, d.y)   # local x into the face, local y up the slope
	var slope := d.length()
	A.box(panel, Vector3(0.025, slope + 0.03, wz + 0.04), Vector3(0.0, 0, 0), "enamel", face, false, 0.4)
	A.box(panel, Vector3(0.03, slope + 0.05, 0.03), Vector3(0.004, 0, z0 - zc - 0.01), "enamel", chrome, false, 0.3)   # chrome trim, the sides
	A.box(panel, Vector3(0.03, slope + 0.05, 0.03), Vector3(0.004, 0, z1 - zc + 0.01), "enamel", chrome, false, 0.3)
	A.box(panel, Vector3(0.035, 0.03, wz + 0.08), Vector3(0.004, -slope / 2.0 - 0.01, 0), "enamel", chrome, false, 0.3)   # and the front edge
	var kinds := [["RPM", "x100"], ["SPEED", "km/h"], ["BRAKE", "psi"], ["LOAD", "A"], ["FUEL", ""], ["OIL", "bar"]]
	for i in kinds.size():
		var big := i < 3
		var rad := 0.085 if big else 0.062
		var c := Vector3(-0.013, 0.1 if big else -0.13, -0.55 + (i % 3) * 0.55)
		A.cyl(panel, rad + 0.016, 0.02, c, "enamel", chrome, false, "x")   # chrome bezel
		A.cyl(panel, rad + 0.004, 0.022, c + Vector3(-0.002, 0, 0), "rubber", Color.WHITE, false, "x")
		A.cyl(panel, rad, 0.006, c + Vector3(-0.012, 0, 0), "cream", Color(1.15, 1.12, 1.02), false, "x")   # dial
		for k in 9:   # ticks over a 270 degree sweep, the last two red
			var a := deg_to_rad(-135.0 + k * 33.75)
			var t := A.box(panel, Vector3(0.004, rad * (0.22 if k % 2 == 0 else 0.12), 0.006), c + Vector3(-0.016, cos(a) * rad * 0.8, -sin(a) * rad * 0.8),
				"metal", Color(0.75, 0.1, 0.06) if k >= 7 else Color(0.08, 0.08, 0.08), false, 0.2)
			t.rotation.x = a
		var needle := Node3D.new()
		panel.add_child(needle)
		needle.position = c + Vector3(-0.02, 0, 0)
		needle.set_meta("live", true)
		A.box(needle, Vector3(0.004, rad * 0.85, 0.006), Vector3(0, rad * 0.33, 0), "paint", Color(1.2, 0.3, 0.2), false)
		A.cyl(needle, 0.01, 0.01, Vector3(-0.003, 0, 0), "metal", Color(0.12, 0.12, 0.12), false, "x")
		_gauges.append([needle, kinds[i][0], 0.0])
		var glass = A.cyl(panel, rad, 0.004, c + Vector3(-0.026, 0, 0), "metal", Color.WHITE, false, "x")
		glass.material_override = A.glass()
		var cap := B.label(panel, kinds[i][0] + ("  " + kinds[i][1] if kinds[i][1] != "" else ""), c + Vector3(-0.014, -rad - 0.032, 0), 16, plate, "plate", 0.0028)
		cap.rotation = Vector3(0, -PI / 2, 0)
	# Warning lamps across the top, between the gauges.
	for k in 4:
		var lc: Color = [Color(1, 0.75, 0.2), Color(1, 0.75, 0.2), Color(1, 0.2, 0.15), Color(1, 0.2, 0.15)][k]
		var lp := Vector3(-0.013, 0.24, -0.825 + 0.55 * k)
		if k > 0:
			lp.z = -0.275 + 0.55 * (k - 1)
		if k == 3:
			lp.z = 0.79
		A.cyl(panel, 0.021, 0.012, lp, "enamel", chrome, false, "x")
		A.cyl(panel, 0.015, 0.018, lp + Vector3(-0.006, 0, 0), "cream", lc, false, "x").material_override = A.mat("cream", lc.darkened(0.45), 1.0, 0.5 if k != 1 else 2.5)
	# Switches along the front of the cabinet, each over its plate.
	var names := ["LIGHTS", "HEAT", "FANS", "RADIO", "WIPER"]
	for k in names.size():
		var sp := Vector3(front - 0.005, F + 0.74, -0.05 + k * 0.3)
		A.box(self, Vector3(0.012, 0.06, 0.04), sp, "enamel", chrome, false, 0.2)
		var lever := A.seg(self, sp + Vector3(-0.006, 0, 0), sp + Vector3(-0.045, 0.018 if k % 2 == 0 else -0.018, 0), 0.004, 0.003, "enamel", chrome)
		lever.set_meta("live", true)
		B.label(self, names[k], sp + Vector3(-0.002, -0.06, 0), 13, plate, "plate", 0.003).rotation.y = -PI / 2
	B.label(self, "BRM  CONTROL STAND  7", Vector3(front - 0.004, F + 0.5, zc), 18, plate, "plate", 0.0032).rotation.y = -PI / 2
	# The lever stand beside it: throttle, brake, horn, each on its own quadrant.
	var lz0 := 1.5
	var lz1 := 1.88
	var lzc := (lz0 + lz1) / 2.0
	A.box(self, Vector3(0.42, 0.95, lz1 - lz0), Vector3(7.85, F + 0.475, lzc), "enamel", body, true, 0.6)
	A.box(self, Vector3(0.44, 0.03, lz1 - lz0 + 0.02), Vector3(7.85, F + 0.965, lzc), "enamel", face, false, 0.3)
	var levers := [["THROTTLE", Color(0.12, 0.12, 0.12), 0.03], ["BRAKE", Color(0.12, 0.12, 0.12), 0.034], ["HORN", Color(0.75, 0.08, 0.05), 0.04]]
	for k in 3:
		var lz := lz0 + 0.07 + k * 0.12
		var pv := Vector3(7.8, F + 0.985, lz)
		A.box(self, Vector3(0.24, 0.012, 0.05), pv + Vector3(0.0, -0.004, 0), "enamel", Color(0.2, 0.2, 0.2), false, 0.2)   # its slot
		for n in 5:   # notches
			A.box(self, Vector3(0.006, 0.004, 0.05), pv + Vector3(-0.09 + n * 0.045, 0.004, 0), "paint", Color(0.95, 0.92, 0.85), false, 0.2)
		var tip := pv + Vector3(-0.07, 0.2, 0)
		A.seg(self, pv, tip, 0.01, 0.009, "enamel", chrome)
		A.sphere(self, levers[k][2], tip, "plastic", levers[k][1])
		var lab := B.label(self, levers[k][0], Vector3(7.639, F + 0.88, lz), 11, plate, "plate", 0.0026)
		lab.rotation.y = -PI / 2
		if k == 2:
			B.interactable(self, Vector3(0.14, 0.28, 0.1), pv + Vector3(-0.04, 0.12, 0), Color(0, 0, 0, 0), "Sound the horn",
				func(): Sfx.play(self, "horn", Vector3(16.5, 4.2, 0), -6.0), 0.0, 0.0)
	# The radio handset on its hook at the end of the console, coiled cord hanging.
	var rh := Vector3(front - 0.03, F + 0.5, z0 + 0.08)
	A.box(self, Vector3(0.05, 0.14, 0.1), rh + Vector3(0.02, 0.1, 0), "enamel", face, false, 0.3)
	A.box(self, Vector3(0.04, 0.2, 0.06), rh + Vector3(-0.015, 0.05, 0), "plastic", Color(0.12, 0.12, 0.12), false, 0.3)
	for k in 7:
		A.ring(self, 0.012, 0.008, rh + Vector3(-0.02, -0.07 - k * 0.022, 0.0), "rubber", Color.WHITE)


## Needles follow the engine: RPM leads the speed, brake pipe and oil wobble, everything shivers at idle.
func _update_gauges(delta: float) -> void:
	var v := absf(speed)
	_rpm = lerpf(_rpm, clampf(0.22 + v / 9.0, 0.22, 0.95), minf(1.0, delta * 1.5))
	var t := Time.get_ticks_msec() / 1000.0
	for g in _gauges:
		var want := 0.0
		match g[1]:
			"RPM": want = _rpm + sin(t * 23.0) * 0.006
			"SPEED": want = clampf(v / 14.0, 0.0, 1.0)
			"BRAKE": want = 0.66 + sin(t * 0.7) * 0.01 - (0.15 if _comp_on > 0.0 else 0.0) * 0.0
			"LOAD": want = clampf((_rpm - 0.22) * 1.3, 0.0, 1.0) + sin(t * 9.0) * 0.004
			"FUEL": want = 0.58
			"OIL": want = 0.35 + _rpm * 0.4 + sin(t * 13.0) * 0.004
		g[2] = lerpf(g[2], want, minf(1.0, delta * 4.0))
		g[0].rotation.x = deg_to_rad(-135.0 + g[2] * 270.0)


# --- locomotive -----------------------------------------------------------------------------
# Road-switcher layout: long hood behind the cab (radiators + fans at the back end, exhaust stack,
# dynamic-brake blister), the cab, a short nose with headlights, walkways with yellow handrails
# all round, three-axle trucks with traction motors, a fuel tank slung between them, a V plow.

func _locomotive() -> void:
	var body := Color(0.82, 0.52, 0.18)   # for trim tints
	var maroon := Color(0.55, 0.42, 0.4)
	var x0 := 8.35
	var x1 := 17.25
	var xc := (x0 + x1) / 2.0
	# Frame, deck plate, sill with hazard edge.
	A.box(self, Vector3(x1 - x0, 0.35, 3.0), Vector3(xc, 0.75, 0), "metal", FRAME, true, 1.0)
	A.box(self, Vector3(x1 - x0, 0.08, 3.1), Vector3(xc, F - 0.04, 0), "riveted", Color(0.45, 0.43, 0.4), true, 1.0)
	for s in [-1, 1]:
		A.box(self, Vector3(x1 - x0, 0.3, 0.06), Vector3(xc, 0.82, s * 1.55), "maroon", Color.WHITE, false, 1.5)
		A.box(self, Vector3(x1 - x0, 0.08, 0.065), Vector3(xc, 0.62, s * 1.56), "hazard", Color.WHITE, false, 0.5)
		var num := B.label(self, "B.R.M.", Vector3(11.0, 0.84, s * 1.59), 60, CREAM, "stencil", 0.006)
		num.rotation.y = 0.0 if s > 0 else PI
	A.box(self, Vector3(0.3, 0.12, 2.4), Vector3(8.2, F - 0.06, 0), "riveted", Color(0.4, 0.4, 0.4), false)   # bridge plate to the car
	# --- long hood ---
	var h0 := 8.75
	var h1 := 13.55
	var hc := (h0 + h1) / 2.0
	var hl := h1 - h0
	A.box(self, Vector3(hl, 2.05, 1.9), Vector3(hc, F + 1.03, 0), "loco", Color.WHITE, true, 2.0)
	A.box(self, Vector3(hl - 0.04, 0.22, 1.5), Vector3(hc, F + 2.17, 0), "loco", Color.WHITE, false, 2.0)
	for s in [-1, 1]:
		A.cyl(self, 0.22, hl - 0.04, Vector3(hc, F + 2.05, s * 0.73), "loco", Color.WHITE, false, "x")
		var z: float = s * 0.955
		# Access doors: panel seams, louvres, latches.
		for k in 5:
			var dx := h0 + 0.5 + k * 0.95
			A.box(self, Vector3(0.03, 1.75, 0.02), Vector3(dx, F + 1.0, z), "metal", FRAME, false)
			if k < 4:
				A.box(self, Vector3(0.08, 0.05, 0.04), Vector3(dx + 0.85, F + 1.25, z + s * 0.01), "metal", Color(0.75, 0.75, 0.72), false)
				A.box(self, Vector3(0.06, 0.04, 0.03), Vector3(dx + 0.12, F + 1.65, z), "metal", FRAME, false)
				A.box(self, Vector3(0.06, 0.04, 0.03), Vector3(dx + 0.12, F + 0.35, z), "metal", FRAME, false)
		A.box(self, Vector3(hl, 0.03, 0.02), Vector3(hc, F + 1.9, z), "metal", FRAME, false)
		# Radiator intakes at the back end, air filter louvres up front.
		A.box(self, Vector3(1.6, 1.15, 0.03), Vector3(h0 + 0.95, F + 1.25, z + s * 0.005), "grille", Color.WHITE, false, 0.3)
		A.box(self, Vector3(1.7, 1.25, 0.02), Vector3(h0 + 0.95, F + 1.25, z), "metal", FRAME, false)
		for k in 6:
			A.box(self, Vector3(0.7, 0.04, 0.05), Vector3(h1 - 0.7, F + 0.6 + k * 0.15, z + s * 0.02), "metal", body.darkened(0.3), false, 0.3, Vector3(0.5 * s, 0, 0))
		var tag := B.label(self, "BRM 07", Vector3(hc + 0.4, F + 1.45, z + s * 0.02), 90, Color(0.3, 0.08, 0.06), "stencil", 0.007)
		tag.rotation.y = 0.0 if s > 0 else PI
		var warn := B.label(self, "DANGER  600V", Vector3(h0 + 2.6, F + 0.35, z + s * 0.02), 30, Color(0.1, 0.08, 0.06), "stencil", 0.005)
		warn.rotation.y = 0.0 if s > 0 else PI
	# Roof: two big radiator fans in a grille deck, the exhaust stack, the dynamic brake blister.
	A.box(self, Vector3(2.0, 0.12, 1.55), Vector3(h0 + 1.05, F + 2.33, 0), "metal", body.darkened(0.2), false)
	for fx in [h0 + 0.55, h0 + 1.55]:
		A.cyl(self, 0.44, 0.06, Vector3(fx, F + 2.41, 0), "grille", Color.WHITE)
		A.ring(self, 0.46, 0.4, Vector3(fx, F + 2.42, 0), "metal", FRAME)
		var fan := Node3D.new()
		add_child(fan)
		fan.position = Vector3(fx, F + 2.37, 0)
		for k in 4:
			A.box(fan, Vector3(0.8, 0.02, 0.13), Vector3.ZERO, "metal", Color(0.25, 0.25, 0.25), false, 0.3, Vector3(0.25, k * PI / 4, 0))
		A.spin(fan, "y", 0.6 + fx * 0.01)
	A.box(self, Vector3(1.5, 0.35, 1.3), Vector3(h0 + 3.1, F + 2.42, 0), "loco", Color.WHITE.darkened(0.08), false, 1.5)
	for s in [-1, 1]:
		A.box(self, Vector3(1.2, 0.22, 0.02), Vector3(h0 + 3.1, F + 2.42, s * 0.66), "grille", Color.WHITE, false, 0.2)
	A.box(self, Vector3(0.6, 0.12, 0.4), Vector3(11.6, F + 2.33, 0), "metal", FRAME, false)
	A.cyl(self, 0.16, 0.5, Vector3(11.6, F + 2.6, 0), "rust", Color(0.55, 0.5, 0.48))   # exhaust stack
	A.cyl(self, 0.19, 0.06, Vector3(11.6, F + 2.86, 0), "rust", Color(0.35, 0.3, 0.28))
	A.cyl(self, 0.09, 0.2, Vector3(12.9, F + 2.37, 0.35), "metal", Color(0.6, 0.6, 0.6))   # sand filler
	A.sphere(self, 0.13, Vector3(12.9, F + 2.35, -0.4), "brass", Color.WHITE, 0.0, 0.8)   # bell
	for lx in [h0 + 0.2, h1 - 0.2]:
		A.ring(self, 0.06, 0.035, Vector3(lx, F + 2.32, 0), "metal", FRAME, Vector3(PI / 2, 0, 0))   # lift rings
	# --- cab ---
	var c0 := 13.6
	var c1 := 15.95
	var ccx := (c0 + c1) / 2.0
	var ch := 2.75
	A.box(self, Vector3(c1 - c0, ch, 2.7), Vector3(ccx, F + ch / 2, 0), "loco", Color.WHITE, true, 2.0)
	A.box(self, Vector3(c1 - c0 + 0.02, 0.3, 2.73), Vector3(ccx, F + 0.15, 0), "maroon", Color.WHITE, false, 1.5)   # (proud of the cab: no shared faces)
	var roof := A.box(self, Vector3(c1 - c0 + 0.3, 0.12, 2.95), Vector3(ccx, F + ch + 0.06, 0), "maroon", Color.WHITE, false, 1.5)
	for s in [-1, 1]:
		A.cyl(self, 0.08, c1 - c0 + 0.3, Vector3(ccx, F + ch + 0.02, s * 1.42), "maroon", Color.WHITE, false, "x")
		var z: float = s * 1.355
		# Two side windows (one slid half open), framed, with an armrest and grab irons.
		for k in 2:
			var wx := c0 + 0.6 + k * 1.05
			A.box(self, Vector3(0.82, 0.72, 0.02), Vector3(wx, F + 2.0, z + s * 0.005), "metal", Color(0.06, 0.07, 0.08), false)
			var g = A.box(self, Vector3(0.78, 0.68, 0.01), Vector3(wx + (0.2 if k == 1 else 0.0), F + 2.0, z + s * 0.02), "metal", Color.WHITE, false)
			g.material_override = A.rain_glass()
			for e in [-1, 1]:
				A.box(self, Vector3(0.05, 0.8, 0.05), Vector3(wx + e * 0.43, F + 2.0, z + s * 0.02), "metal", FRAME, false)
			A.box(self, Vector3(0.9, 0.05, 0.06), Vector3(wx, F + 1.6, z + s * 0.03), "metal", FRAME, false)
			A.box(self, Vector3(0.9, 0.05, 0.06), Vector3(wx, F + 2.4, z + s * 0.03), "metal", FRAME, false)
		A.box(self, Vector3(0.8, 0.07, 0.12), Vector3(c0 + 0.6, F + 1.62, z + s * 0.07), "metal", FRAME, false)   # armrest
		for gx in [c0 + 0.08, c1 - 0.08]:
			A.seg(self, Vector3(gx, F + 0.4, z + s * 0.06), Vector3(gx, F + 1.9, z + s * 0.06), 0.022, 0.022, "metal", RAIL)
		A.box(self, Vector3(0.5, 0.3, 0.02), Vector3(c0 + 1.15, F + 1.05, z + s * 0.005), "metal", FRAME, false)
		var cab_num := B.label(self, "07", Vector3(c0 + 1.15, F + 1.05, z + s * 0.02), 80, Color(0.3, 0.08, 0.06), "stencil", 0.0045)
		cab_num.rotation.y = 0.0 if s > 0 else PI
		A.box(self, Vector3(0.12, 0.2, 0.15), Vector3(c1 + 0.05, F + ch - 0.25, s * 1.2), "metal", FRAME, false)   # class lights
		A.glow(self, Vector3(0.02, 0.1, 0.1), Vector3(c1 + 0.12, F + ch - 0.25, s * 1.2), Color(0.95, 0.95, 0.85), 2.0)
	# Front and rear windows, sun visors, wipers, number board.
	for e in [[c1, 1.0], [c0, -1.0]]:
		var ex: float = e[0] + e[1] * 0.005
		for wz in [-0.62, 0.62]:
			A.box(self, Vector3(0.02, 0.7, 0.95), Vector3(ex, F + 2.05, wz), "metal", Color(0.06, 0.07, 0.08), false)
			var g = A.box(self, Vector3(0.01, 0.66, 0.9), Vector3(ex + e[1] * 0.01, F + 2.05, wz), "metal", Color.WHITE, false)
			g.material_override = A.rain_glass()
			A.box(self, Vector3(0.05, 0.78, 1.03), Vector3(ex + e[1] * 0.015, F + 2.05, wz), "metal", FRAME, false).scale = Vector3(1, 1, 1)
			if e[1] > 0.0:
				A.box(self, Vector3(0.3, 0.03, 0.9), Vector3(ex + 0.15, F + 2.45, wz), "metal", FRAME, false, 1.0, Vector3(0, 0, -0.2))
				A.seg(self, Vector3(ex + 0.03, F + 1.72, wz), Vector3(ex + 0.03, F + 2.25, wz + 0.3), 0.012, 0.012, "metal", Color(0.1, 0.1, 0.1))
	A.box(self, Vector3(0.05, 0.22, 0.7), Vector3(c1 + 0.03, F + ch - 0.2, 0), "metal", Color(0.05, 0.05, 0.05), false)
	A.glow(self, Vector3(0.02, 0.18, 0.66), Vector3(c1 + 0.06, F + ch - 0.2, 0), Color(0.95, 0.9, 0.75), 1.2)
	var nb := B.display(self, "07", Vector3(c1 + 0.075, F + ch - 0.2, 0), 64, Color(0.1, 0.08, 0.06))
	nb.rotation.y = PI / 2
	nb.pixel_size = 0.0028
	# Roof gear: three-chime horn, antenna, amber beacon.
	for k in 3:
		A.seg(self, Vector3(ccx - 0.2 + k * 0.18, F + ch + 0.12, -0.6), Vector3(ccx - 0.2 + k * 0.18 + (0.25 if k == 1 else -0.25), F + ch + 0.22, -0.6), 0.03, 0.09, "metal", Color(0.65, 0.65, 0.62))
	A.seg(self, Vector3(ccx + 0.4, F + ch + 0.12, 0.5), Vector3(ccx + 0.4, F + ch + 0.9, 0.5), 0.012, 0.006, "metal", Color(0.3, 0.3, 0.3))
	var beacon := MeshInstance3D.new()
	var bm := SphereMesh.new()
	bm.radius = 0.1
	bm.height = 0.2
	bm.is_hemisphere = true
	beacon.mesh = bm
	add_child(beacon)
	beacon.position = Vector3(ccx - 0.4, F + ch + 0.12, 0.3)
	Merge.live(beacon)
	var tw := beacon.create_tween().set_loops()
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(1, 0.6, 0.1)
	bmat.emission_enabled = true
	bmat.emission = Color(1, 0.55, 0.1)
	beacon.material_override = bmat
	tw.tween_property(bmat, "emission_energy_multiplier", 5.0, 0.5)
	tw.tween_property(bmat, "emission_energy_multiplier", 0.2, 0.5)
	# --- short nose with twin headlights ---
	var n0 := c1
	var n1 := 16.85
	A.box(self, Vector3(n1 - n0, 1.3, 1.7), Vector3((n0 + n1) / 2, F + 0.65, 0), "loco", Color.WHITE, true, 2.0)
	var nose_top := A.box(self, Vector3(n1 - n0 + 0.05, 0.08, 1.7), Vector3((n0 + n1) / 2 + 0.03, F + 1.36, 0), "loco", Color.WHITE.darkened(0.1), false, 2.0)
	nose_top.rotation.z = -0.12
	for s in [-1, 1]:
		A.box(self, Vector3(n1 - n0 - 0.02, 1.28, 0.02), Vector3((n0 + n1) / 2, F + 0.64, s * 0.861), "metal", FRAME, false)
	A.box(self, Vector3(0.05, 1.0, 0.6), Vector3(n1 + 0.02, F + 0.6, 0), "metal", body.darkened(0.15), false)   # nose door
	A.box(self, Vector3(0.06, 0.06, 0.15), Vector3(n1 + 0.05, F + 0.6, 0.2), "metal", Color(0.75, 0.75, 0.72), false)
	for hz in [-0.55, 0.55]:
		A.cyl(self, 0.15, 0.12, Vector3(n1 + 0.04, F + 1.05, hz), "metal", FRAME, false, "x")
		A.glow(self, Vector3(0.03, 0.2, 0.2), Vector3(n1 + 0.1, F + 1.05, hz), Color(1, 0.88, 0.6), 6.0)
		A.box(self, Vector3(0.15, 0.04, 0.32), Vector3(n1 + 0.1, F + 1.2, hz), "metal", FRAME, false)
	headlight = SpotLight3D.new()
	headlight.light_color = Color(1, 0.85, 0.6)
	headlight.light_energy = 5.0
	headlight.spot_range = 60.0
	headlight.spot_angle = 18.0
	headlight.light_volumetric_fog_energy = 2.0
	add_child(headlight)
	headlight.position = Vector3(n1 + 0.2, F + 1.05, 0)
	headlight.rotation = Vector3(-0.05, -PI / 2, 0)
	# --- walkway handrails (yellow), end railings, steps at every corner ---
	for s in [-1, 1]:
		var z: float = s * 1.45
		var posts := [8.55, 9.7, 10.85, 12.0, 13.15, 14.0, 15.95, 16.9, 17.15]
		for px in posts:
			if px > c0 and px < c1:
				continue
			A.seg(self, Vector3(px, F, z), Vector3(px, F + 1.0, z), 0.022, 0.022, "metal", RAIL)
		for seg in [[8.55, 13.6], [15.95, 17.15]]:
			for y in [1.0, 0.55]:
				A.seg(self, Vector3(seg[0], F + y, z), Vector3(seg[1], F + y, z), 0.02, 0.02, "metal", RAIL)
		A.box(self, Vector3(0.3, 0.02, 0.06), Vector3(13.4, F + 0.02, z), "hazard", Color.WHITE, false)
		_steps(self, 8.7, s * 1.62, 0.6)
		_steps(self, 16.95, s * 1.62, 0.6)
		A.seg(self, Vector3(8.4, F, s * 1.45), Vector3(8.4, F + 1.0, s * 1.45), 0.02, 0.02, "metal", RAIL)
	for y in [1.0, 0.55]:   # front rail across the pilot
		A.seg(self, Vector3(17.15, F + y, -1.45), Vector3(17.15, F + y, 1.45), 0.02, 0.02, "metal", RAIL)
	# --- pilot: end sill with chevrons, anticlimber, a proper V plow, ditch lights, hoses ---
	A.box(self, Vector3(0.3, 0.6, 3.0), Vector3(x1 + 0.05, 0.72, 0), "loco", Color.WHITE, true, 1.0)   # end sill
	A.box(self, Vector3(0.012, 0.46, 2.84), Vector3(x1 + 0.206, 0.72, 0), "hazard", Color.WHITE, false, 0.6)   # chevron plate
	A.box(self, Vector3(0.16, 0.1, 2.5), Vector3(x1 + 0.28, F - 0.08, 0), "metal", FRAME, false)   # anticlimber
	for k in 4:
		A.box(self, Vector3(0.02, 0.03, 2.5), Vector3(x1 + 0.365, F - 0.12 + k * 0.025, 0), "metal", FRAME.lightened(0.1), false)
	var tip := Vector3(x1 + 0.95, 0.36, 0)
	for s in [-1, 1]:
		var wing := Vector3(x1 + 0.24, 0.36, s * 1.42)
		var run := wing - tip
		var blade := A.box(self, Vector3(run.length(), 0.5, 0.06), (tip + wing) / 2.0, "plow", Color(0.92, 0.85, 0.78), false, 1.0)
		blade.rotation = Vector3(0, atan2(-run.z, run.x), 0)
		var cap := A.box(self, Vector3(run.length(), 0.05, 0.12), (tip + wing) / 2.0 + Vector3(0, 0.27, 0), "metal", FRAME, false)
		cap.rotation = blade.rotation
		var edge := A.box(self, Vector3(run.length(), 0.06, 0.1), (tip + wing) / 2.0 + Vector3(0, -0.26, 0), "metal", Color(0.32, 0.31, 0.3), false)
		edge.rotation = blade.rotation   # wear edge just over the rail heads
		for t in [0.35, 0.75]:   # struts back to the sill
			var on := tip.lerp(wing, t) + Vector3(-0.04, 0.05, 0)
			A.seg(self, on, Vector3(x1 + 0.2, 0.6, on.z * 0.85), 0.03, 0.03, "metal", FRAME)
		# Ditch light on a bracket at the corner: round housing, glowing lens, visor.
		var dl := Vector3(x1 + 0.32, F + 0.28, s * 1.22)
		A.box(self, Vector3(0.2, 0.05, 0.12), dl + Vector3(-0.1, -0.12, 0), "metal", FRAME, false)
		A.cyl(self, 0.1, 0.18, dl, "metal", FRAME, false, "x")
		A.cyl(self, 0.085, 0.02, dl + Vector3(0.095, 0, 0), "cream", Color(1, 0.92, 0.7), false, "x").material_override = A.mat("cream", Color(1, 0.92, 0.7), 1.0, 4.0)
		A.box(self, Vector3(0.12, 0.02, 0.22), dl + Vector3(0.1, 0.11, 0), "metal", FRAME, false, 1.0, Vector3(0, 0, -0.25))
		# Air and MU hoses looping down to their glad hands.
		A.seg(self, Vector3(x1 + 0.22, 0.6, s * 0.45), Vector3(x1 + 0.42, 0.3, s * 0.5), 0.03, 0.03, "rubber")
		A.box(self, Vector3(0.1, 0.06, 0.08), Vector3(x1 + 0.45, 0.28, s * 0.5), "brass", Color.WHITE, false)
	A.box(self, Vector3(0.14, 0.5, 0.12), tip + Vector3(-0.04, 0, 0), "metal", FRAME, false)   # nose of the plow
	A.box(self, Vector3(0.05, 0.3, 0.3), Vector3(x1 + 0.215, 0.95, 0.9), "metal", FRAME, false)   # number plate on the sill
	B.label(self, "07", Vector3(x1 + 0.243, 0.95, 0.9), 60, CREAM, "stencil", 0.004).rotation.y = PI / 2
	_coupler(self, x1 + 0.1, 1.0)
	_coupler(self, x0 - 0.05, -1.0)
	# --- fuel tank, air reservoirs, trucks ---
	A.box(self, Vector3(3.0, 0.5, 2.1), Vector3(12.55, 0.4, 0), "metal", Color(0.28, 0.28, 0.3), false, 1.0)
	for s in [-1, 1]:
		A.cyl(self, 0.28, 3.0, Vector3(12.55, 0.32, s * 0.78), "metal", Color(0.28, 0.28, 0.3), false, "x")
		A.cyl(self, 0.16, 2.6, Vector3(12.55, 0.45, s * 1.3), "metal", Color(0.4, 0.4, 0.42), false, "x")
	A.cyl(self, 0.1, 0.05, Vector3(12.0, 0.45, 1.06), "paper", Color(0.9, 0.9, 0.85), false, "z")
	A.ring(self, 0.11, 0.09, Vector3(12.0, 0.45, 1.08), "metal", Color(0.6, 0.6, 0.6), Vector3(PI / 2, 0, 0))
	A.cyl(self, 0.08, 0.12, Vector3(13.2, 0.62, 1.1), "metal", Color(0.75, 0.15, 0.1), false, "z")
	var fuel := B.label(self, "FUEL", Vector3(12.6, 0.4, 1.06), 40, CREAM, "stencil", 0.005)
	_bogie(self, 9.75, 3, 1.05, 0.45, true)
	_bogie(self, 15.6, 3, 1.05, 0.45, true)
	# Exhaust.
	_steam = GPUParticles3D.new()
	_steam.amount = 90
	_steam.lifetime = 3.5
	_steam.local_coords = false
	_steam.visibility_aabb = AABB(Vector3(-40, -5, -10), Vector3(60, 25, 20))
	_steam_mat = ParticleProcessMaterial.new()
	_steam_mat.direction = Vector3(0, 1, 0)
	_steam_mat.spread = 12.0
	_steam_mat.initial_velocity_min = 2.0
	_steam_mat.initial_velocity_max = 3.5
	_steam_mat.scale_min = 0.6
	_steam_mat.scale_max = 1.2
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.4))
	grow.add_point(Vector2(1, 2.5))
	var gt := CurveTexture.new()
	gt.curve = grow
	_steam_mat.scale_curve = gt
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.5))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	var ft := GradientTexture1D.new()
	ft.gradient = fade
	_steam_mat.color_ramp = ft
	_steam.process_material = _steam_mat
	var quad := QuadMesh.new()
	quad.size = Vector2(1.2, 1.2)
	var sm := StandardMaterial3D.new()
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.vertex_color_use_as_albedo = true
	sm.albedo_color = Color(0.3, 0.28, 0.27)
	var puff := GradientTexture2D.new()   # round, soft-edged puffs (not squares)
	var pg := Gradient.new()
	pg.set_color(0, Color(1, 1, 1, 0.9))
	pg.set_color(1, Color(1, 1, 1, 0.0))
	puff.gradient = pg
	puff.fill = GradientTexture2D.FILL_RADIAL
	puff.fill_from = Vector2(0.5, 0.5)
	puff.fill_to = Vector2(0.5, 0.0)
	sm.albedo_texture = puff
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	quad.material = sm
	_steam.draw_pass_1 = quad
	add_child(_steam)
	_steam.position = Vector3(11.6, F + 2.9, 0)


# --- flatcar -------------------------------------------------------------------------------

func _flatcar(rng: RandomNumberGenerator) -> void:
	_flat = Node3D.new()
	add_child(_flat)
	var x0 := -15.5
	var x1 := -8.7
	var xc := (x0 + x1) / 2.0
	var len := x1 - x0
	# Plank deck on a fishbelly frame, stake pockets along the sides.
	for k in 14:
		A.box(_flat, Vector3(len, 0.08, 0.19), Vector3(xc, 1.01, -1.3 + k * 0.2), "wood", Color.WHITE.darkened(rng.randf() * 0.25), k == 0, 1.0)
	A.box(_flat, Vector3(len, 0.08, 2.8), Vector3(xc, 0.97, 0), "wood", Color(0.5, 0.45, 0.4), true, 1.5)
	A.box(_flat, Vector3(len + 0.2, 0.3, 2.3), Vector3(xc, 0.75, 0), "metal", FRAME, false, 1.0)
	for s in [-1, 1]:
		A.box(_flat, Vector3(len, 0.22, 0.1), Vector3(xc, 0.86, s * 1.42), "rust", Color(0.75, 0.7, 0.68), false, 1.0)
		A.box(_flat, Vector3(3.0, 0.3, 0.1), Vector3(xc, 0.6, s * 1.35), "rust", Color(0.7, 0.65, 0.62), false, 1.0)
		for e in [-1, 1]:
			var taper := A.box(_flat, Vector3(1.1, 0.12, 0.1), Vector3(xc + e * 2.0, 0.66, s * 1.35), "rust", Color(0.7, 0.65, 0.62), false, 1.0)
			taper.rotation.z = e * 0.28
		for k in 6:
			var px := x0 + 0.5 + k * (len - 1.0) / 5.0
			A.box(_flat, Vector3(0.12, 0.18, 0.1), Vector3(px, 0.85, s * 1.5), "metal", FRAME, false)
			if k % 2 == 0 and not (s < 0 and k == 0):
				A.box(_flat, Vector3(0.09, 1.1, 0.09), Vector3(px, 1.4, s * 1.48), "wood", Color(0.6, 0.5, 0.42), false, 0.5)
		var tag := B.label(_flat, "BRM 4413", Vector3(xc + 2.2, 0.86, s * 1.48), 40, CREAM, "stencil", 0.006)
		tag.rotation.y = 0.0 if s > 0 else PI
	# Load: crates under ratchet straps, barrels, and a big tarp-covered lump roped down.
	A.crate(_flat, Vector3(-9.8, 1.05, 0.65), 1.0, rng)
	A.crate(_flat, Vector3(-10.9, 1.05, 0.55), 0.8, rng)
	A.crate(_flat, Vector3(-10.0, 2.05, 0.6), 0.6, rng, false)
	for sx in [-9.8, -10.9]:
		A.box(_flat, Vector3(0.06, 0.02, 2.6), Vector3(sx, 2.07 if sx > -10.0 else 1.87, 0), "canvas", Color(0.85, 0.65, 0.15), false, 0.3)
		for s in [-1, 1]:
			A.box(_flat, Vector3(0.06, 1.0, 0.02), Vector3(sx, 1.55, s * 1.3), "canvas", Color(0.85, 0.65, 0.15), false, 0.3)
	A.barrel(_flat, Vector3(-9.9, 1.05, -0.8), rng)
	A.barrel(_flat, Vector3(-10.6, 1.05, -0.9), rng)
	var tarp := A.sphere(_flat, 1.0, Vector3(-13.2, 1.2, 0), "canvas", Color(0.45, 0.5, 0.38), 0.0, 1.0)
	tarp.scale = Vector3(1.8, 0.85, 1.25)
	A.box(_flat, Vector3(3.4, 0.3, 2.5), Vector3(-13.2, 1.18, 0), "canvas", Color(0.42, 0.47, 0.36), false, 0.6)
	for rx in [-14.4, -13.6, -12.8, -12.0]:   # ropes over the tarp, following its curve
		var prev := Vector3(rx, 1.06, 1.32)
		for k in range(1, 9):
			var a := PI * k / 8.0
			var pt := Vector3(rx, 1.2 + sin(a) * 0.88, cos(a) * 1.3)
			A.seg(_flat, prev, pt, 0.018, 0.018, "canvas", Color(0.75, 0.68, 0.5))
			prev = pt
	A.box(_flat, Vector3(3.4, 1.4, 2.4), Vector3(-13.2, 1.7, 0), "canvas", Color.WHITE, true).visible = false   # its collision
	# Brake wheel on a staff at the back end, end sills, couplers, trucks.
	A.seg(_flat, Vector3(x0 + 0.2, 0.9, 1.0), Vector3(x0 + 0.2, 1.9, 1.0), 0.03, 0.03, "metal", FRAME)
	A.ring(_flat, 0.25, 0.22, Vector3(x0 + 0.24, 1.95, 1.0), "metal", Color(0.4, 0.4, 0.4), Vector3(0, 0, PI / 2))
	for k in 3:
		A.box(_flat, Vector3(0.03, 0.46, 0.03), Vector3(x0 + 0.24, 1.95, 1.0), "metal", Color(0.4, 0.4, 0.4), false, 1.0, Vector3(k * PI / 3, 0, 0))
	for e in [x0, x1]:
		A.box(_flat, Vector3(0.15, 0.35, 2.8), Vector3(e, 0.82, 0), "metal", FRAME, false)
		A.box(_flat, Vector3(0.16, 0.08, 2.8), Vector3(e, 0.62, 0), "hazard", Color.WHITE, false, 0.5)
	_coupler(_flat, x0 - 0.1, -1.0)
	_coupler(_flat, x1 + 0.05, 1.0)
	_bogie(_flat, -10.0, 2, 1.3)
	_bogie(_flat, -14.2, 2, 1.3)


# --- upgrades / deliveries -----------------------------------------------------------

## STORAGE_CAR upgrade: a second walk-in car behind the crew car; the flatcar moves back.
func add_storage_car() -> void:
	if has_storage:
		return
	has_storage = true
	_rear_lock.queue_free()
	_flat.position.x -= CAR_LEN
	for i in _axles.size():   # (the flatcar's wheels went back with it)
		if _axles[i] < -8.3:
			_axles[i] -= CAR_LEN
	var x0 := -8.3 - CAR_LEN
	var x1 := -8.3
	var xc := (x0 + x1) / 2.0
	var root := Node3D.new()
	add_child(root)
	var paint := Color(0.78, 0.6, 0.48)
	var door := [[xc + 2.0, 1.5, 0.0, 2.3]]
	var wins := [[xc - 3.5, 1.0, 1.0, 2.0], [xc + 4.5, 1.0, 1.0, 2.0]]
	A.wall(root, x0, x1, 2.18, WALL_H, 0.08, door + wins, "corrugated", paint, true, F, true, 1.2)
	A.wall(root, x0, x1, 2.06, WALL_H, 0.08, door + wins, "enamel", SAGE, true, F, false, 1.0)
	A.wall(root, x0, x1, -2.18, WALL_H, 0.08, [], "corrugated", paint, true, F, true, 1.2)
	A.wall(root, x0, x1, -2.06, WALL_H, 0.08, [], "enamel", SAGE, true, F, false, 1.0)
	A.wall(root, -2.2, 2.2, x0, WALL_H, 0.15, [], "corrugated", paint, false, F, true, 1.2)
	A.wall(root, -2.2, 2.2, x1 + 0.05, WALL_H, 0.15, [[0.0, 1.2, 0.0, 2.3]], "corrugated", paint, false, F, true, 1.2)
	for w in wins:
		_glass_at(root, Vector3(w[0], F + 1.5, 2.12), Vector3(w[1], 1.0, 0.02))
	A.box(root, Vector3(CAR_LEN, 0.12, 4.2), Vector3(xc, F - 0.06, 0), "wood", Color(0.85, 0.8, 0.75), true, 1.5)
	A.box(root, Vector3(CAR_LEN + 0.4, 0.35, 3.4), Vector3(xc, 0.7, 0), "rust", Color(0.6, 0.6, 0.6), true)
	A.box(root, Vector3(CAR_LEN, 0.08, 4.4), Vector3(xc, F + 2.74, 0), "metal", Color(0.5, 0.45, 0.42), true)
	for i in 6:   # roof beams, painted like the crew car's
		A.box(root, Vector3(0.1, 0.12, 4.1), Vector3(x0 + 0.5 + i * 2.2, F + WALL_H - 0.06, 0), "metal", Color(0.36, 0.42, 0.36), false, 1.0)
	# Inside dressed like the crew car: varnished boards to the waist under a brass rail, the ends in
	# the same sage.
	A.wall(root, x0 + 0.1, x1 - 0.1, 2.0, 1.0, 0.03, door, "panelling", Color.WHITE, true, F, false, 0.6)
	A.wall(root, x0 + 0.1, x1 - 0.1, -2.0, 1.0, 0.03, [], "panelling", Color.WHITE, true, F, false, 0.6)
	var dl: float = door[0][0] - 0.75
	var dr: float = door[0][0] + 0.75
	for sg in [[x0 + 0.1, dl], [dr, x1 - 0.1]]:
		A.box(root, Vector3(sg[1] - sg[0], 0.035, 0.05), Vector3((sg[0] + sg[1]) / 2.0, F + 1.0, 1.975), "wood", Color(0.5, 0.36, 0.26), false, 0.5)
	A.box(root, Vector3(x1 - x0 - 0.2, 0.035, 0.05), Vector3(xc, F + 1.0, -1.975), "wood", Color(0.5, 0.36, 0.26), false, 0.5)
	for e in [[x0 + 0.1, []], [x1 - 0.06, [[0.0, 1.2, 0.0, 2.3]]]]:
		A.wall(root, -2.0, 2.0, e[0], WALL_H - 0.1, 0.03, e[1], "enamel", SAGE, false, F, false, 1.0)
		A.wall(root, -2.0, 2.0, e[0] + (0.02 if e[0] < xc else -0.02), 1.0, 0.03, e[1], "panelling", Color.WHITE, false, F, false, 0.6)
	_car_dress(root, x0, x1, door, wins, [], "RECLAIMED MATERIALS  -  STORAGE", "BRM 311", [xc + 0.4], "corrugated", paint)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	# Inside: racks along the back wall, tie-down rails, a cargo net, pallets, work lamps.
	for i in 4:
		A.shelf_unit(root, Vector3(x0 + 1.6 + i * 2.6, F, -1.72), 0.0, rng, 2.4, 2.3, 0.5)
	for y in [F + 0.4, F + 1.4]:
		A.box(root, Vector3(CAR_LEN - 0.6, 0.06, 0.04), Vector3(xc, y, 2.0), "metal", Color(0.55, 0.55, 0.52), false)
	for k in 5:
		A.ring(root, 0.05, 0.03, Vector3(x0 + 1.0 + k * 2.6, F + 0.4, 1.97), "metal", Color(0.6, 0.6, 0.6), Vector3(PI / 2, 0, 0))
	for k in 6:   # cargo net across the end
		A.box(root, Vector3(0.02, 2.0, 0.02), Vector3(x0 + 0.35, F + 1.1, -1.5 + k * 0.6), "canvas", Color(0.7, 0.6, 0.35), false, 0.2)
		A.box(root, Vector3(0.02, 0.02, 3.2), Vector3(x0 + 0.35, F + 0.2 + k * 0.38, 0), "canvas", Color(0.7, 0.6, 0.35), false, 0.2)
	A.pallet(root, Vector3(xc - 1.5, F, 0.9))
	A.pallet(root, Vector3(xc + 4.0, F, 0.9))
	var cargo_sign := B.label(root, "CARGO", Vector3(xc, F + 2.45, -1.97), 48, Color(0.95, 0.9, 0.75), "stencil", 0.005)
	for x in [xc - 3.0, xc + 3.0]:   # caged lamps, as in the crew car
		A.cyl(root, 0.16, 0.05, Vector3(x, F + 2.58, 0), "brass", Color(0.8, 0.66, 0.4), false)
		A.sphere(root, 0.12, Vector3(x, F + 2.45, 0), "cream", Color(1, 0.92, 0.78), 5.0)
		for a in 4:
			var bar := A.box(root, Vector3(0.02, 0.25, 0.02), Vector3(x, F + 2.45, 0) + Vector3(0.14, 0, 0).rotated(Vector3.UP, a * PI / 2), "metal", Color(0.3, 0.3, 0.3), false)
			bar.rotation.y = a * PI / 2
		B.omni(root, Vector3(x, F + 2.2, 0), Color(1, 0.88, 0.74), 1.0, 7.5)
	for d in door:
		for sgn in [-1, 1]:
			A.box(root, Vector3(0.08, 2.4, 0.06), Vector3(d[0] + sgn * 0.8, F + 1.2, 2.25), "metal", FRAME, false)
			A.cyl(root, 0.025, 1.2, Vector3(d[0] + sgn * 0.95, F + 1.0, 2.36), "metal", RAIL)
	_bogie(root, x0 + 2.4, 2, 1.3)
	_bogie(root, x1 - 2.4, 2, 1.3)
	Merge.bake(root, 8.0)
	_mob_barrier()   # (the wall round the train grows with it)


func _glass_at(parent: Node, pos: Vector3, size: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = A.rain_glass()
	parent.add_child(mi)
	mi.position = pos


## The pump handcar that brings shop orders: a plank deck on two steel sills, four spoked wheels, an
## A-frame with a walking beam and T-handles, a connecting rod down to a crank on the front axle (so
## the beam rocks as fast as the wheels turn), a strapped Bureau crate and a lamp on a post.
## Returns it; the caller slides position.x and _handcar_tick animates it from how far it moved.
func make_handcar() -> Node3D:
	var car := Node3D.new()
	add_child(car)
	var rust := Color(0.55, 0.42, 0.34)
	for z in [-0.62, 0.62]:   # sills
		A.box(car, Vector3(2.7, 0.16, 0.12), Vector3(0, 0.56, z), "rust", rust, false, 1.0)
	for x in [-1.3, 1.3]:   # end beams with buffers
		A.box(car, Vector3(0.14, 0.2, 1.42), Vector3(x, 0.56, 0), "rust", rust, false, 1.0)
		for z in [-0.45, 0.45]:
			A.cyl(car, 0.06, 0.12, Vector3(x * 1.06, 0.56, z), "metal", Color(0.3, 0.3, 0.3), false, "x")
	for i in 7:   # deck planks, a finger's gap between
		A.box(car, Vector3(0.34, 0.05, 1.5), Vector3(-1.08 + i * 0.36, 0.665, 0), "wood", Color(0.78, 0.7, 0.6), true, 1.0)
	var wheels := []
	for x in [-0.8, 0.8]:
		A.cyl(car, 0.04, 1.62, Vector3(x, 0.3, 0), "metal", Color(0.3, 0.3, 0.3), false, "z")   # axle
		for z in [-0.75, 0.75]:
			wheels.append(_wheel(Vector3(x, 0.3, z), 0.28, car))
			_wheels.pop_back()   # (they turn as the handcar rolls, not with the train)
			A.box(car, Vector3(0.16, 0.14, 0.08), Vector3(x, 0.42, z * 0.88), "metal", Color(0.28, 0.27, 0.26), false, 0.5)   # axle box
	# The crank on the front axle, inside the frame.
	var crank := Node3D.new()
	car.add_child(crank)
	crank.position = Vector3(0.8, 0.3, 0.2)
	Merge.live(crank)
	A.box(crank, Vector3(0.24, 0.07, 0.05), Vector3(0.09, 0, 0), "metal", Color(0.45, 0.45, 0.45), false, 0.5)
	A.cyl(crank, 0.03, 0.08, Vector3(0.18, 0, 0), "metal", Color(0.6, 0.6, 0.6), false, "z")   # crank pin
	# A-frame and the walking beam.
	for z in [-0.18, 0.18]:
		for s in [-1, 1]:
			A.seg(car, Vector3(s * 0.45, 0.69, z), Vector3(0, 1.55, z), 0.035, 0.03, "metal", Color(0.4, 0.38, 0.36))
	A.cyl(car, 0.05, 0.5, Vector3(0, 1.55, 0), "metal", Color(0.3, 0.3, 0.3), false, "z")   # pivot pin
	var beam := Node3D.new()
	car.add_child(beam)
	beam.position = Vector3(0, 1.58, 0)
	Merge.live(beam)
	A.box(beam, Vector3(2.0, 0.1, 0.09), Vector3.ZERO, "wood", Color(0.62, 0.5, 0.4), false, 1.0)
	for x in [-1.0, 1.0]:   # T-handles, worn smooth
		A.cyl(beam, 0.035, 0.95, Vector3(x, 0.02, 0), "wood", Color(0.5, 0.4, 0.32), false, "z")
		A.box(beam, Vector3(0.1, 0.14, 0.12), Vector3(x * 0.96, 0, 0), "metal", Color(0.35, 0.35, 0.35), false, 0.5)
	var rod := MeshInstance3D.new()   # the connecting rod: re-aimed every frame
	var rm := CylinderMesh.new()
	rm.top_radius = 0.022
	rm.bottom_radius = 0.022
	rm.height = 1.0
	rm.radial_segments = 8
	rod.mesh = rm
	rod.material_override = A.mat("metal", Color(0.5, 0.5, 0.5), 0.5)
	car.add_child(rod)
	Merge.live(rod)
	# Cargo: a Bureau crate strapped down at the back, a lamp on a post at the front.
	A.box(car, Vector3(0.8, 0.55, 0.9), Vector3(-0.78, 0.97, 0), "wood", Color(0.85, 0.72, 0.55), false, 0.8)
	for x in [-0.98, -0.58]:
		A.box(car, Vector3(0.05, 0.57, 0.92), Vector3(x, 0.97, 0), "canvas", Color(0.55, 0.5, 0.35), false, 0.5)   # straps
	var stamp := B.label(car, "B.R.M.", Vector3(-0.78, 1.0, 0.452), 40, Color(0.12, 0.1, 0.08), "stencil", 0.004)
	stamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	A.cyl(car, 0.025, 1.0, Vector3(1.18, 1.17, 0.62), "metal", Color(0.35, 0.35, 0.35))
	A.box(car, Vector3(0.12, 0.16, 0.12), Vector3(1.18, 1.75, 0.62), "metal", Color(0.25, 0.25, 0.25), false, 0.3)
	A.sphere(car, 0.05, Vector3(1.18, 1.75, 0.62), "cream", Color(1, 0.75, 0.4), 5.0)
	B.omni(car, Vector3(1.18, 1.8, 0.62), Color(1, 0.75, 0.4), 0.8, 6.0)
	car.set_meta("hc", {"wheels": wheels, "beam": beam, "rod": rod, "crank": crank, "x": car.position.x, "angle": 0.0, "creak": 0.0})
	_handcar = car
	_handcar_tick(0.0)
	return car


var _handcar: Node3D

## The handcar's wheels turn with how far it rolled; the crank turns with them and the rod rocks the beam.
func _handcar_tick(delta: float) -> void:
	if _handcar == null or not is_instance_valid(_handcar):
		return
	var hc: Dictionary = _handcar.get_meta("hc")
	var dx: float = _handcar.position.x - hc.x
	hc.x = _handcar.position.x
	if absf(dx) > 3.0:
		dx = 0.0   # (put back at the start of its run, not rolled there)
	hc.angle -= dx / 0.28
	for w in hc.wheels:
		w.rotation.z = hc.angle
	var crank: Node3D = hc.crank
	crank.rotation.z = hc.angle
	var pin: Vector3 = crank.position + Vector3(0.18, 0, 0).rotated(Vector3.BACK, hc.angle)
	# The beam end the rod hangs from rises and falls with the pin (beam arm 0.8 m from the pivot).
	var beam: Node3D = hc.beam
	var tilt := clampf(asin(clampf((pin.y - 0.3) / 0.8, -1.0, 1.0)) * 1.4, -0.42, 0.42)
	beam.rotation.z = tilt
	var top: Vector3 = beam.position + Vector3(0.8, 0, 0).rotated(Vector3.BACK, tilt) + Vector3(0, -0.05, 0.2)
	var rod: MeshInstance3D = hc.rod
	rod.transform = Transform3D(Basis(Quaternion(Vector3.UP, (top - pin).normalized())) * Basis.from_scale(Vector3(1, top.distance_to(pin), 1)), (top + pin) / 2.0)
	if delta > 0.0 and absf(dx) > 0.0005:   # the pump creaks at each end of its stroke
		hc.creak += absf(dx) / 0.28
		if hc.creak > PI:
			hc.creak = 0.0
			Sfx.play(_handcar, "creak", _handcar.global_position + Vector3(0, 1.5, 0), -10.0, randf_range(1.2, 1.5))


# --- DIGITAL_CLOCK upgrade -------------------------------------------------------------------

## A surplus segment display bolted above the front window: big HH:MM on top, a smaller
## countdown to the 24:00 departure under it. Chunky block segments, unlit ones ghost faintly.
## Upgrades you can see aboard: INFIRMARY (a cot and a med cabinet), WEATHERVANE (on the roof).
func show_upgrade(u: String) -> void:
	if has_node("Up_" + u):
		return
	var n := Node3D.new()
	n.name = "Up_" + u
	add_child(n)
	match u:
		"INFIRMARY": _infirmary(n)
		"WEATHERVANE": _weathervane(n)


## A folding steel cot with a thin mattress, a grey blanket and a pillow along the right wall, and
## a white wall cabinet with a red cross over it, a drip stand at its head.
func _infirmary(n: Node3D) -> void:
	var at := Vector3(4.6, F, 1.62)   # (between the side door at 2.6 and the desk end)
	var steel := Color(0.6, 0.62, 0.6)
	for x in [-0.85, 0.85]:
		for z in [-0.3, 0.3]:
			A.box(n, Vector3(0.04, 0.42, 0.04), at + Vector3(x, 0.21, z), "metal", steel, false)
	A.box(n, Vector3(1.85, 0.05, 0.7), at + Vector3(0, 0.42, 0), "metal", steel, true, 0.5)
	A.box(n, Vector3(1.8, 0.08, 0.64), at + Vector3(0, 0.49, 0), "canvas", Color(0.72, 0.74, 0.66), false, 0.8)   # mattress
	A.box(n, Vector3(1.1, 0.03, 0.66), at + Vector3(0.3, 0.545, 0), "canvas", Color(0.45, 0.48, 0.5), false, 0.6)   # blanket
	A.sphere(n, 0.2, at + Vector3(-0.68, 0.575, 0), "canvas", Color(0.92, 0.92, 0.88), 0.0, 0.3).scale = Vector3(0.9, 0.3, 1.25)   # pillow
	for x in [-0.9, 0.9]:   # the mattress rolled over at its ends
		A.cyl(n, 0.04, 0.64, at + Vector3(x, 0.49, 0), "canvas", Color(0.72, 0.74, 0.66), false, "z")
	var cab := at + Vector3(1.32, 0, 0.02)   # a low steel med cabinet at the cot's foot, under the window line
	A.box(n, Vector3(0.5, 0.8, 0.42), cab + Vector3(0, 0.4, 0), "metal", Color(0.92, 0.92, 0.9), true, 0.5)
	A.box(n, Vector3(0.01, 0.7, 0.4), cab + Vector3(-0.255, 0.4, 0), "metal", Color(0.4, 0.4, 0.4), false)   # door seam
	A.box(n, Vector3(0.006, 0.06, 0.2), cab + Vector3(-0.256, 0.55, 0), "plastic", Color(0.85, 0.1, 0.08), false)
	A.box(n, Vector3(0.006, 0.2, 0.06), cab + Vector3(-0.257, 0.55, 0), "plastic", Color(0.85, 0.1, 0.08), false)
	A.box(n, Vector3(0.14, 0.1, 0.1), cab + Vector3(0.05, 0.85, -0.05), "cardboard", Color(0.9, 0.88, 0.8), false)   # dressings on top
	A.seg(n, at + Vector3(-0.95, 0, -0.45), at + Vector3(-0.95, 1.7, -0.45), 0.015, 0.015, "metal", steel)   # drip stand
	A.box(n, Vector3(0.1, 0.16, 0.04), at + Vector3(-0.95, 1.62, -0.38), "plastic", Color(0.85, 0.9, 0.95), false)
	var l := B.label(n, "INFIRMARY", cab + Vector3(-0.258, 0.25, 0), 22, Color(0.85, 0.1, 0.08), "stencil", 0.004)
	l.rotation.y = -PI / 2


## A weathervane on the crew car's roof: a mast, the compass arms with N/E/S/W, and the arrow,
## which turns into the wind.
func _weathervane(n: Node3D) -> void:
	var top := Vector3(0.6, F + WALL_H + 0.45, 0)   # (the roof crown)
	var iron := Color(0.15, 0.15, 0.15)
	A.seg(n, top, top + Vector3(0, 1.1, 0), 0.025, 0.018, "metal", iron)
	for k in 4:
		var d := Vector3(0.3, 0, 0).rotated(Vector3.UP, k * PI / 2.0)
		A.seg(n, top + Vector3(0, 0.7, 0), top + Vector3(0, 0.7, 0) + d, 0.008, 0.008, "metal", iron)
		var l := B.label(n, ["E", "N", "W", "S"][k], top + Vector3(0, 0.7, 0) + d * 1.12, 40, Color(0.2, 0.2, 0.2), "stencil", 0.004)
		l.rotation.y = k * PI / 2.0 + PI / 2.0
	var arrow := Node3D.new()
	n.add_child(arrow)
	arrow.position = top + Vector3(0, 1.0, 0)
	arrow.set_meta("live", true)
	A.seg(arrow, Vector3(-0.35, 0, 0), Vector3(0.35, 0, 0), 0.008, 0.008, "metal", iron)
	A.box(arrow, Vector3(0.1, 0.1, 0.01), Vector3(0.38, 0, 0), "metal", iron, false, 0.5, Vector3(0, 0, PI / 4))   # head
	A.box(arrow, Vector3(0.2, 0.16, 0.008), Vector3(-0.32, 0.0, 0), "metal", Color(0.75, 0.3, 0.15), false)   # tail fin (a rooster's red)
	A.sphere(n, 0.03, top + Vector3(0, 1.1, 0), "brass", Color(0.8, 0.65, 0.3))
	var tw := arrow.create_tween().set_loops()
	tw.tween_property(arrow, "rotation:y", 0.5, 3.5).set_trans(Tween.TRANS_SINE)
	tw.tween_property(arrow, "rotation:y", -0.35, 4.0).set_trans(Tween.TRANS_SINE)


## Shut (pulling out) or open (arrived) every platform door: the leaves roll along their tracks
## with a rumble and bang home.
func set_doors(open: bool) -> void:
	if _doors_open == open:
		return
	_doors_open = open
	for d in _door_leaves:
		var leafn: Node3D = d[0]
		if not is_instance_valid(leafn):
			continue
		var tw := leafn.create_tween()
		tw.tween_property(leafn, "position:x", 0.0 if open else float(d[1]), 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		var at: Vector3 = leafn.global_position + Vector3(0, 2.0, 2.3)
		Sfx.play(self, "slide", leafn.to_global(Vector3(0, 0, 0)), -6.0, randf_range(0.85, 1.0))
		tw.tween_callback(func(): Sfx.play(self, "clunk", leafn.global_position, -4.0, 1.1 if open else 0.9))


func add_digital_clock() -> void:
	if not _digits.is_empty():
		return
	_seg_on = StandardMaterial3D.new()
	_seg_on.albedo_color = Color(1, 0.35, 0.12)
	_seg_on.emission_enabled = true
	_seg_on.emission = Color(1, 0.32, 0.1)
	_seg_on.emission_energy_multiplier = 3.5
	_seg_off = StandardMaterial3D.new()
	_seg_off.albedo_color = Color(0.16, 0.05, 0.03)
	_seg_off.emission_enabled = true
	_seg_off.emission = Color(0.4, 0.08, 0.03)
	_seg_off.emission_energy_multiplier = 0.15
	var dc := Node3D.new()
	add_child(dc)
	dc.position = Vector3(8.06, F + 2.34, 0)
	dc.rotation.y = -PI / 2   # faces back down the car
	var steel := Color(0.36, 0.37, 0.35)
	A.box(dc, Vector3(1.04, 0.52, 0.1), Vector3(0, 0, -0.03), "metal", steel, false, 0.4)
	A.box(dc, Vector3(0.94, 0.42, 0.02), Vector3(0, 0, 0.025), "metal", Color(0.05, 0.03, 0.025), false)
	A.box(dc, Vector3(1.04, 0.04, 0.12), Vector3(0, 0.25, -0.02), "metal", steel.darkened(0.25), false)
	for bx in [-0.49, 0.49]:
		for by in [-0.23, 0.23]:
			A.sphere(dc, 0.014, Vector3(bx, by, 0.025), "metal", Color(0.62, 0.62, 0.6))
		A.box(dc, Vector3(0.05, 0.05, 0.1), Vector3(bx * 0.8, 0.3, -0.08), "metal", Color(0.22, 0.22, 0.22), false)
	for k in 6:   # vent slots on top
		A.box(dc, Vector3(0.08, 0.005, 0.05), Vector3(-0.3 + k * 0.12, 0.262, -0.02), "metal", Color(0.05, 0.05, 0.05), false)
	A.seg(dc, Vector3(0.45, -0.26, -0.05), Vector3(0.5, -0.45, -0.12), 0.012, 0.012, "rubber")   # power lead
	var tag := B.label(dc, "DEPARTS IN", Vector3(-0.2, -0.15, 0.037), 40, Color(0.75, 0.6, 0.45), "stencil", 0.0014)
	tag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var plate := B.label(dc, "RAILNET TIMEKEEPER  MK II", Vector3(0, -0.235, 0.037), 40, Color(0.6, 0.55, 0.5), "plate", 0.0008)
	plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Big row: H H : M M
	for x in [-0.33, -0.18, 0.06, 0.21]:
		_digits.append(_digit(dc, Vector3(x, 0.07, 0.04), 0.1, 0.2, 0.024))
	_colons.append(_dot(dc, Vector3(-0.06, 0.11, 0.04), 0.026))
	_colons.append(_dot(dc, Vector3(-0.06, 0.03, 0.04), 0.026))
	# Small row: H H : M M countdown.
	for x in [0.06, 0.13, 0.23, 0.3]:
		_digits.append(_digit(dc, Vector3(x, -0.15, 0.04), 0.048, 0.09, 0.012))
	_colons.append(_dot(dc, Vector3(0.18, -0.13, 0.04), 0.012))
	_colons.append(_dot(dc, Vector3(0.18, -0.17, 0.04), 0.012))
	var glow := OmniLight3D.new()
	glow.light_color = Color(1, 0.3, 0.1)
	glow.light_energy = 0.35
	glow.omni_range = 1.6
	dc.add_child(glow)
	glow.position = Vector3(0, 0, 0.3)
	Sfx.play(self, "scan", dc.global_position, -6.0, 1.3)


func _digit(parent: Node3D, at: Vector3, w: float, h: float, t: float) -> Array:
	var segs := []
	var spots := {
		"a": [Vector3(0, h / 2, 0), Vector3(w - t, t, t)], "d": [Vector3(0, -h / 2, 0), Vector3(w - t, t, t)],
		"g": [Vector3(0, 0, 0), Vector3(w - t, t, t)],
		"b": [Vector3(w / 2, h / 4, 0), Vector3(t, h / 2 - t, t)], "c": [Vector3(w / 2, -h / 4, 0), Vector3(t, h / 2 - t, t)],
		"e": [Vector3(-w / 2, -h / 4, 0), Vector3(t, h / 2 - t, t)], "f": [Vector3(-w / 2, h / 4, 0), Vector3(t, h / 2 - t, t)],
	}
	for k in "abcdefg":
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = spots[k][1]
		mi.mesh = bm
		mi.material_override = _seg_off
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
		mi.position = at + spots[k][0]
		segs.append(mi)
	return segs


func _dot(parent: Node3D, at: Vector3, s: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(s, s, s)
	mi.mesh = bm
	mi.material_override = _seg_on
	parent.add_child(mi)
	mi.position = at
	return mi


func _show_digital(hours: float, at_checkpoint: bool) -> void:
	var now := "%02d%02d" % [int(hours) % 24, int(fmod(hours, 1.0) * 60.0)]
	var left := maxf(0.0, (25.0 if get_parent().has_upgrade("OVERTIME_PERMIT") else 24.0) - hours)
	var count := "----" if at_checkpoint else "%02d%02d" % [int(left), int(fmod(left, 1.0) * 60.0)]
	var text := now + count
	for i in _digits.size():
		var lit: String = SEGMENTS.get(text[i], "")
		for k in 7:
			_digits[i][k].material_override = _seg_on if "abcdefg"[k] in lit else _seg_off
	var blink := fmod(Time.get_ticks_msec() / 1000.0, 1.0) < 0.5
	for c in _colons:
		c.material_override = _seg_on if blink else _seg_off
	_seg_on.emission_energy_multiplier = 3.5 if not (not at_checkpoint and left < 1.0 and blink) else 6.0   # flares in the last hour
