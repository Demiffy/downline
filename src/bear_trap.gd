# Rusty bear trap left in the dark. Step on it: it snaps shut, hurts, and holds you until you
# hold E to pry it open (which makes noise). Once sprung it stays shut.
extends Node3D

const A = preload("res://src/art.gd")
const B = preload("res://src/build.gd")
const Sfx = preload("res://src/sfx.gd")

var main
var level
var sprung := false
var victim = null
var _jaws: Array[Node3D] = []


func _ready() -> void:
	add_to_group("fauna")   # the scanner sees it (field guide)
	A.cyl(self, 0.26, 0.03, Vector3(0, 0.015, 0), "rust", Color(0.7, 0.65, 0.6))
	A.box(self, Vector3(0.62, 0.025, 0.07), Vector3(0, 0.02, 0), "rust", Color(0.6, 0.55, 0.5), false, 0.3)
	A.cyl(self, 0.07, 0.03, Vector3(0, 0.04, 0), "metal", Color(0.5, 0.5, 0.45))
	A.box(self, Vector3(0.4, 0.01, 0.01), Vector3(0.4, 0.01, 0.1), "metal", Color(0.3, 0.3, 0.3), false, 0.3, Vector3(0, 0.4, 0))
	for side in [-1, 1]:
		var jaw := Node3D.new()
		add_child(jaw)
		jaw.position = Vector3(0, 0.03, side * 0.03)
		# A half-ring of serrated teeth lying flat while armed.
		for k in 9:
			var a := PI * k / 8.0
			var p := Vector3(cos(a) * 0.27, 0, side * sin(a) * 0.27)
			A.box(jaw, Vector3(0.05, 0.02, 0.025), p, "rust", Color.WHITE, false, 0.3, Vector3(0, -side * a, 0))
			A.box(jaw, Vector3(0.02, 0.06, 0.02), p + Vector3(0, 0.03, 0), "metal", Color(0.75, 0.72, 0.68), false, 0.3)
		jaw.rotation.x = 0.0
		_jaws.append(jaw)
	var pry := B.interactable(self, Vector3(0.6, 0.15, 0.6), Vector3(0, 0.1, 0), Color(0, 0, 0, 0), "Pry the trap open", release, 1.2)
	pry.get_child(1).visible = false
	pry.collision_layer = 2   # only the interaction ray hits it, nobody trips on it


func _physics_process(_delta: float) -> void:
	if sprung or main == null:
		return
	for p in main.players():
		if p.dead:
			continue
		var d := Vector2(p.global_position.x - global_position.x, p.global_position.z - global_position.z).length()
		if d < 0.42 and absf(p.global_position.y - global_position.y) < 0.4:
			_snap(p)
			return


func _snap(p) -> void:
	sprung = true
	victim = p
	p.trapped = self
	var held := Vector3(global_position.x, p.global_position.y, global_position.z)
	if p.has_method("move_to"):
		p.move_to(held)   # (a crewmate: they're told)
	else:
		p.global_position = held
	p.hurt(25.0, "Bled out in a bear trap.")
	p.shake(0.05)
	Sfx.play(self, "snap", global_position, 8.0)
	main.noise(global_position, 14.0)
	for i in 2:
		var tw := create_tween()
		tw.tween_property(_jaws[i], "rotation:x", (1.35 if i == 0 else -1.35), 0.07)


func release() -> void:
	if victim != null and is_instance_valid(victim):
		victim.trapped = null
		victim = null
		Sfx.play(self, "creak", global_position, 2.0, 1.3)
		main.noise(global_position, 10.0)
		for i in 2:
			create_tween().tween_property(_jaws[i], "rotation:x", (0.6 if i == 0 else -0.6), 0.3)


func net_visual(_delta: float) -> void:
	if sprung and absf(_jaws[0].rotation.x) < 1.0:
		for i in 2:
			_jaws[i].rotation.x = 1.35 if i == 0 else -1.35
