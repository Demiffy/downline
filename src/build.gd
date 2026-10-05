# Tiny geometry helpers: everything in the world is boxes for now.
extends RefCounted

const Interact = preload("res://src/interact.gd")
const Paint = preload("res://src/paint.gd")

static var _mats := {}


static func mat(c: Color, emit := 0.0, metal := 0.0) -> StandardMaterial3D:
	var k := "%s|%s|%s" % [c.to_html(), emit, metal]
	if not _mats.has(k):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.metallic = metal
		m.roughness = 0.85 - metal * 0.5
		if emit > 0.0:
			m.emission_enabled = true
			m.emission = c
			m.emission_energy_multiplier = emit
		_mats[k] = m
	return _mats[k]


static func mesh(size: Vector3, c: Color, emit := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat(c, emit)
	return mi


static func _shape(body: CollisionObject3D, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	body.add_child(cs)


## A box. solid = has collision. Returns the node that was placed.
static func box(parent: Node, size: Vector3, pos: Vector3, c: Color, solid := true, emit := 0.0) -> Node3D:
	var mi := mesh(size, c, emit)
	if not solid:
		parent.add_child(mi)
		mi.position = pos
		return mi
	var body := StaticBody3D.new()
	_shape(body, size)
	body.add_child(mi)
	parent.add_child(body)
	body.position = pos
	return body


static func invisible_wall(parent: Node, size: Vector3, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	_shape(body, size)
	parent.add_child(body)
	body.position = pos


static func interactable(parent: Node, size: Vector3, pos: Vector3, c: Color, text: String, act: Callable, hold := 0.0, emit := 0.0) -> StaticBody3D:
	var it := Interact.new()
	it.prompt = text
	it.action = act
	it.hold_time = hold
	_shape(it, size)
	it.add_child(mesh(size, c, emit))
	parent.add_child(it)
	it.position = pos
	return it


## Old weathered paint on the surface behind it (see paint.gd for styles). Text size is
## px * pixel_size metres, as with a Label3D. Faces +z.
static func label(parent: Node, text: String, pos: Vector3, px := 64, c := Color.WHITE, style := "stencil", pixel_size := 0.006) -> MeshInstance3D:
	return Paint.quad(parent, text, pos, px * pixel_size, c, style)


## Glowing text for displays and lit signs (elevator readout, boards, neon).
static func display(parent: Node, text: String, pos: Vector3, px := 64, c := Color.WHITE) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = px
	l.pixel_size = 0.006
	l.modulate = c
	l.outline_size = 0
	l.double_sided = false
	l.shaded = false
	parent.add_child(l)
	l.position = pos
	return l


static func omni(parent: Node, pos: Vector3, c: Color, energy: float, rng: float, shadow := false) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = c
	l.light_energy = energy
	l.omni_range = rng
	l.shadow_enabled = shadow
	parent.add_child(l)
	l.position = pos
	return l
