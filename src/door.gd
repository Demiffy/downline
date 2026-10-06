# Double swing doors in a doorway. E toggles both leaves; monsters shove them open when close.
# The node sits at the doorway's left jamb (local x = 0 .. width); leaves swing on their outer hinges.
extends Node3D

const A = preload("res://src/art.gd")
const B = preload("res://src/build.gd")
const Sfx = preload("res://src/sfx.gd")

var open := false
var panel: StaticBody3D       # the leaf the player aims at (both carry the prompt)
var _leaves: Array[Node3D] = []
var _panels: Array[StaticBody3D] = []
var _swing := 1.0
var _check := 0.0


func setup(width: float, height: float, kind: String, tint: Color, start_open: bool, swing := 1.0) -> void:
	_swing = swing
	var lw := width / 2.0
	var wood := kind == "wood"
	for side in [0, 1]:
		var hinge := Node3D.new()
		add_child(hinge)
		hinge.position.x = 0.0 if side == 0 else width
		var dir := 1.0 if side == 0 else -1.0   # +x into the leaf from its hinge
		_leaves.append(hinge)
		var leaf := B.interactable(hinge, Vector3(lw - 0.03, height - 0.03, 0.06), Vector3(dir * lw / 2, height / 2, 0), tint, "Open door", toggle)
		leaf.get_child(1).material_override = A.mat(kind, tint, 1.0)
		_panels.append(leaf)
		var trim := tint.darkened(0.3)
		# Frame stiles and rails proud of the face, on both sides.
		for s in [-1, 1]:
			var z: float = s * 0.04
			A.box(leaf, Vector3(0.07, height - 0.03, 0.02), Vector3(-dir * (lw / 2 - 0.05), 0, z), kind, trim, false, 1.0)
			A.box(leaf, Vector3(0.07, height - 0.03, 0.02), Vector3(dir * (lw / 2 - 0.05), 0, z), kind, trim, false, 1.0)
			for y in [height / 2 - 0.05, -height / 2 + 0.05, -0.15]:
				A.box(leaf, Vector3(lw - 0.1, 0.07, 0.02), Vector3(0, y, z), kind, trim, false, 1.0)
			# Kick plate, push plate / pull handle, wired-glass window.
			A.box(leaf, Vector3(lw - 0.16, 0.28, 0.01), Vector3(0, -height / 2 + 0.2, z * 1.3), "metal", Color(0.6, 0.6, 0.58), false, 0.4)
			if wood:
				A.box(leaf, Vector3(lw - 0.3, 0.55, 0.012), Vector3(0, height * 0.22, z * 1.2), "wood", tint.darkened(0.15), false, 0.6)
			else:
				var win = A.box(leaf, Vector3(0.32, 0.5, 0.012), Vector3(dir * 0.05, height * 0.22, z * 1.2), "metal", Color.WHITE, false)
				win.material_override = A.glass()
				A.box(leaf, Vector3(0.38, 0.56, 0.008), Vector3(dir * 0.05, height * 0.22, z * 1.05), "metal", Color(0.2, 0.2, 0.2), false)
				for k in 3:   # wire mesh in the glass
					A.box(leaf, Vector3(0.32, 0.006, 0.014), Vector3(dir * 0.05, height * 0.22 - 0.18 + k * 0.18, z * 1.2), "metal", Color(0.3, 0.3, 0.3), false)
			if s < 0:   # push bar on the pull side's back
				A.box(leaf, Vector3(lw - 0.3, 0.05, 0.05), Vector3(0, -0.05, z * 2.2), "metal", Color(0.75, 0.75, 0.72), false, 0.3)
			else:
				A.box(leaf, Vector3(0.04, 0.3, 0.04), Vector3(-dir * (lw / 2 - 0.15), 0.0, z * 2.0), "metal", Color(0.75, 0.75, 0.72), false, 0.3)
		# Hinges on the outer edge.
		for y in [height * 0.35, -height * 0.35, 0.0]:
			A.cyl(leaf, 0.02, 0.12, Vector3(-dir * (lw / 2 - 0.01), y, 0.04), "metal", Color(0.4, 0.4, 0.4))
	panel = _panels[0]
	# Door closer arm on the head of the frame.
	for side in [0, 1]:
		var x := 0.25 if side == 0 else width - 0.25
		A.box(self, Vector3(0.28, 0.06, 0.06), Vector3(x, height - 0.1, 0.1), "metal", Color(0.25, 0.25, 0.25), false)
	if start_open:
		_apply(true, false)


func toggle() -> void:
	set_open(not open)


func set_open(o: bool) -> void:
	if o == open:
		return
	_apply(o, true)
	Sfx.play(self, "creak", _panels[0].global_position, -4.0, randf_range(0.8, 1.2))


func _apply(o: bool, animate: bool) -> void:
	open = o
	for i in _leaves.size():
		var p: StaticBody3D = _panels[i]
		p.prompt = "Close door" if open else "Open door"
		var target := (_swing * 1.5 * (1.0 if i == 0 else -1.0)) if open else 0.0
		if animate:
			create_tween().tween_property(_leaves[i], "rotation:y", target, 0.5 + i * 0.08).set_trans(Tween.TRANS_SINE)
		else:
			_leaves[i].rotation.y = target


func _physics_process(delta: float) -> void:
	_check -= delta
	if open or _check > 0.0:
		return
	_check = 0.3
	var c := (_panels[0].global_position + _panels[1].global_position) / 2.0
	for m in get_tree().get_nodes_in_group("monsters"):
		if m.global_position.distance_to(c) < 1.9:
			set_open(true)
			return
