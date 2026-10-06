# The Snatcher lives in the ceiling vents (the ones with yellow-painted frames). An occupied vent
# drips blood. Walk under it and a fleshy maw drops, swallows you, drags you through the ducts and
# spits you out under some other vent — or anywhere at all. You drop whatever you were holding.
extends Node3D

const A = preload("res://src/art.gd")
const B = preload("res://src/build.gd")
const Sfx = preload("res://src/sfx.gd")

var main
var level
var _cool := 0.0
var _maw: Node3D
var _drip: GPUParticles3D
var _busy := false


func _ready() -> void:
	add_to_group("snatchers")
	# Vent: yellow-painted frame, dark grille.
	A.box(self, Vector3(1.0, 0.06, 1.0), Vector3(0, -0.03, 0), "metal", Color(0.9, 0.75, 0.2), false)
	A.box(self, Vector3(0.8, 0.07, 0.8), Vector3(0, -0.035, 0), "grille", Color(0.6, 0.6, 0.6), false, 0.4)
	for x in [-0.25, 0.0, 0.25]:
		A.box(self, Vector3(0.04, 0.05, 0.8), Vector3(x, -0.07, 0), "rust", Color.WHITE, false, 0.3)
	A.box(self, Vector3(0.2, 0.01, 0.15), Vector3(0.2, -0.065, 0.3), "flesh", Color(0.5, 0.05, 0.05), false, 0.3)
	_maw = Node3D.new()
	add_child(_maw)
	A.cyl(_maw, 0.42, 1.2, Vector3(0, 0.6, 0), "flesh", Color(0.9, 0.55, 0.55), false, "y", 0.3)
	for k in 12:
		var a := TAU * k / 12.0
		var tooth := A.box(_maw, Vector3(0.07, 0.18, 0.07), Vector3(cos(a) * 0.36, 0.05, sin(a) * 0.36), "cream", Color(0.95, 0.9, 0.8), false, 0.3)
		tooth.rotation = Vector3(cos(a) * 0.5, 0, -sin(a) * 0.5)
	_maw.position.y = 1.4   # tucked up inside the duct
	_maw.visible = false
	_drip = GPUParticles3D.new()
	_drip.amount = 10
	_drip.lifetime = 1.2
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.3, 0.0, 0.3)
	pm.gravity = Vector3(0, -6.0, 0)
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.2
	_drip.process_material = pm
	var bm := BoxMesh.new()
	bm.size = Vector3(0.025, 0.08, 0.025)
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.45, 0.0, 0.0)
	dm.roughness = 0.1
	bm.material = dm
	_drip.draw_pass_1 = bm
	add_child(_drip)
	_drip.position.y = -0.1
	A.box(self, Vector3(0.6, 0.01, 0.5), Vector3(0, -3.97, 0.1), "flesh", Color(0.35, 0.02, 0.02), false, 0.4)  # blood pool below


func _physics_process(delta: float) -> void:
	_cool -= delta
	_drip.emitting = _cool <= 0.0
	if _busy or _cool > 0.0 or main == null:
		return
	for p in main.players():
		if p.dead or p.trapped != null:
			continue
		var d := Vector2(p.global_position.x - global_position.x, p.global_position.z - global_position.z).length()
		if d < 0.75 and global_position.y - p.global_position.y < 4.5 and global_position.y > p.global_position.y:
			_snatch(p)
			return


func _snatch(p) -> void:
	_busy = true
	_cool = 30.0
	_maw.visible = true
	_maw.position.y = 1.4
	Sfx.play(self, "slurp", global_position, 8.0)
	var tw := create_tween()
	tw.tween_property(_maw, "position:y", -2.3, 0.14).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	if tw.is_running():   # a long frame can finish it before we get here
		await tw.finished
	p.drop_held()
	p.hurt(15.0, "Digested in the vents.")
	p.flash = 1.0
	await main.hud.fade(1.0, 0.15)
	var tw2 := create_tween()
	tw2.tween_property(_maw, "position:y", 1.4, 0.4)
	p.global_position = _exit_point()
	Sfx.play(main, "slurp", null, 2.0, 0.6)
	await get_tree().create_timer(1.6).timeout
	await main.hud.fade(0.0, 0.4)
	p.shake(0.05)
	_maw.visible = false
	_busy = false


func _exit_point() -> Vector3:
	var others := get_tree().get_nodes_in_group("snatchers").filter(func(s): return s != self)
	if not others.is_empty() and randf() < 0.6:
		var o: Node3D = others[randi() % others.size()]
		return o.global_position + Vector3(1.2, -3.95, 0)
	return level.facility.random_point(level.rng, true) if level and level.facility else global_position + Vector3(0, -3.9, 2)
