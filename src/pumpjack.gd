# The moving half of a pumpjack (props.gd builds the frame round it). One crank angle drives the lot,
# so nothing comes apart: the crank turns, the pitman arms join the crank pins to the beam's tail,
# the beam's angle is solved from that linkage, the horsehead's face is an arc about the saddle so the
# bridle hangs straight over the well, and the polished rod rides up and down the stuffing box.
extends Node3D

const A = preload("res://src/art.gd")

const SADDLE := Vector3(0.6, 4.6, 0)
const TAIL := 2.65          # saddle to the equaliser
const FACE := 3.75          # saddle to the horsehead face (and the well)
const CRANK := Vector3(-2.05, 1.3, 0)
const THROW := 0.55
const BRIDLE := 1.0
const PERIOD := 3.4         # seconds per stroke

var _theta := 0.0
var _len := 0.0             # pitman length, fixed by the rest position
var _beam: Node3D
var _crank: Node3D
var _pitmen: Array[Node3D] = []
var _hanger: Node3D         # bridle + carrier bar + polished rod


func build(paint: Color) -> void:
	var dark := Color(0.25, 0.25, 0.25)
	_len = (SADDLE + Vector3(-TAIL, 0, 0)).distance_to(CRANK)
	# Walking beam, horsehead, equaliser.
	_beam = Node3D.new()
	add_child(_beam)
	_beam.position = SADDLE
	A.box(_beam, Vector3(6.0, 0.42, 0.28), Vector3(0.45, 0.2, 0), "rust", paint, false, 1.0)
	A.box(_beam, Vector3(6.0, 0.06, 0.4), Vector3(0.45, 0.42, 0), "rust", paint.darkened(0.15), false, 1.0)
	A.box(_beam, Vector3(6.0, 0.06, 0.4), Vector3(0.45, -0.02, 0), "rust", paint.darkened(0.15), false, 1.0)
	for k in 9:   # horsehead: plates on an arc about the saddle, so the face stays over the well
		var a := -0.42 + k * 0.105
		var plate := A.box(_beam, Vector3(0.1, 0.42, 0.5), Vector3(cos(a) * FACE, sin(a) * FACE + 0.2, 0), "rust", paint, false, 1.0)
		plate.rotation.z = a
	for s in [-1, 1]:
		A.box(_beam, Vector3(0.95, 2.3, 0.06), Vector3(FACE - 0.5, 0.2, s * 0.22), "rust", paint.darkened(0.1), false, 1.0)
	A.box(_beam, Vector3(0.3, 0.3, 0.75), Vector3(-TAIL, 0.0, 0), "metal", dark, false)   # equaliser
	A.cyl(_beam, 0.06, 0.82, Vector3(-TAIL, 0.0, 0), "metal", Color(0.6, 0.6, 0.6), false, "z")
	A.cyl(_beam, 0.1, 0.5, Vector3.ZERO, "metal", dark, false, "z")   # saddle pin
	# Crank: two arms with counterweights and the wrist pins.
	_crank = Node3D.new()
	add_child(_crank)
	_crank.position = CRANK
	for s in [-1, 1]:
		A.box(_crank, Vector3(THROW + 0.25, 0.22, 0.1), Vector3(THROW / 2.0, 0, s * 0.6), "metal", dark, false)
		A.cyl(_crank, 0.62, 0.16, Vector3(-0.3, 0, s * 0.64), "metal", Color(0.3, 0.3, 0.32), false, "z", 0.62)
		A.cyl(_crank, 0.06, 0.12, Vector3(THROW, 0, s * 0.72), "metal", Color(0.65, 0.65, 0.65), false, "z")
	A.cyl(_crank, 0.12, 1.4, Vector3.ZERO, "metal", Color(0.5, 0.5, 0.5), false, "z")
	# Pitman arms: unit-length bars, stretched between their two pins every frame.
	for s in [-1, 1]:
		var p := Node3D.new()
		add_child(p)
		A.box(p, Vector3(0.12, 1.0, 0.08), Vector3.ZERO, "rust", paint, false, 1.0)
		p.set_meta("z", s)
		_pitmen.append(p)
	# Bridle, carrier bar and polished rod hang from the horsehead face.
	_hanger = Node3D.new()
	add_child(_hanger)
	for s in [-1, 1]:
		A.seg(_hanger, Vector3(0, 0, s * 0.12), Vector3(0, -BRIDLE, s * 0.1), 0.012, 0.012, "metal", Color(0.15, 0.15, 0.15))
	A.box(_hanger, Vector3(0.3, 0.07, 0.34), Vector3(0, -BRIDLE, 0), "metal", dark, false)
	A.cyl(_hanger, 0.035, 3.6, Vector3(0, -BRIDLE - 1.8, 0), "metal", Color(0.8, 0.8, 0.8))
	_theta = randf() * TAU


func _process(delta: float) -> void:
	_theta = fmod(_theta + TAU / PERIOD * delta, TAU)
	var pin := CRANK + Vector3(cos(_theta), sin(_theta), 0) * THROW
	# Beam angle: where the tail sits a pitman length from the pin (bisection; the distance falls as phi rises).
	var lo := -0.7
	var hi := 0.7
	for i in 18:
		var mid := (lo + hi) / 2.0
		if _tail(mid).distance_to(pin) > _len:
			lo = mid
		else:
			hi = mid
	var phi := (lo + hi) / 2.0
	_beam.rotation.z = phi
	_crank.rotation.z = _theta
	var tail := _tail(phi)
	for p in _pitmen:
		var z: float = p.get_meta("z")
		var a := pin + Vector3(0, 0, z * 0.78)
		var b := tail + Vector3(0, 0, z * 0.45)
		var d := b - a
		p.position = (a + b) / 2.0
		p.rotation = Vector3(0, 0, atan2(-d.x, d.y))
		p.scale = Vector3(1, Vector2(d.x, d.y).length(), 1)
	# The face is an arc about the saddle: the hanging point stays over the well, rising and falling.
	_hanger.position = Vector3(SADDLE.x + FACE, SADDLE.y + 0.2 + FACE * sin(phi), 0)


func _tail(phi: float) -> Vector3:
	return SADDLE + Vector3(-TAIL * cos(phi), -TAIL * sin(phi), 0)
