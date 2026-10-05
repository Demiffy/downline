# Hinged door in a doorway. E toggles it; monsters shove it open when they get close.
# The node itself is the hinge; the panel hangs off it along local +x.
extends Node3D

const A = preload("res://src/art.gd")
const B = preload("res://src/build.gd")
const Sfx = preload("res://src/sfx.gd")

var open := false
var panel: StaticBody3D
var _swing := 1.0
var _check := 0.0


func setup(width: float, height: float, kind: String, tint: Color, start_open: bool, swing := 1.0) -> void:
	_swing = swing
	panel = B.interactable(self, Vector3(width - 0.06, height - 0.04, 0.07), Vector3(width / 2, height / 2, 0), tint, "Open door", toggle)
	panel.get_child(1).material_override = A.mat(kind, tint, 1.0)
	# Handle, kick plate, little window.
	for s in [-1, 1]:
		A.box(panel, Vector3(0.12, 0.04, 0.05), Vector3(width / 2 - 0.2, 0.0, s * 0.06), "metal", Color(0.7, 0.7, 0.65), false)
	A.box(panel, Vector3(width - 0.2, 0.25, 0.08), Vector3(0, -height / 2 + 0.2, 0), "metal", Color(0.5, 0.5, 0.5), false)
	if kind != "wood":
		A.box(panel, Vector3(0.35, 0.3, 0.08), Vector3(0, height * 0.22, 0), "metal", Color(0.08, 0.08, 0.08), false)
	if start_open:
		open = true
		rotation.y += _swing * 1.6
		panel.prompt = "Close door"


func toggle() -> void:
	set_open(not open)


func set_open(o: bool) -> void:
	if o == open:
		return
	open = o
	panel.prompt = "Close door" if open else "Open door"
	var target := rotation.y + (_swing * 1.6 if open else -_swing * 1.6)
	create_tween().tween_property(self, "rotation:y", target, 0.6).set_trans(Tween.TRANS_SINE)
	Sfx.play(self, "creak", panel.global_position, -4.0, randf_range(0.8, 1.2))


func _physics_process(delta: float) -> void:
	_check -= delta
	if open or _check > 0.0:
		return
	_check = 0.3
	var c := panel.global_position
	for m in get_tree().get_nodes_in_group("monsters"):
		if m.global_position.distance_to(c) < 1.9:
			set_open(true)
			return
