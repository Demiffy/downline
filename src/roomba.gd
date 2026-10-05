# Trap on wheels: drives straight, turns randomly on bump, two laser sensors in front.
# Break a laser -> it beeps for a moment (run!) -> big explosion.
extends CharacterBody3D

const B = preload("res://src/build.gd")
const Sfx = preload("res://src/sfx.gd")

const SPEED := 1.8
const FUSE := 0.8

var main
var level
var dir := Vector3.FORWARD
var armed := -1.0
var _beep := 0.0
var _click := 0.0
var rays: Array[RayCast3D] = []


func _ready() -> void:
	add_to_group("monsters")
	collision_layer = 8
	collision_mask = 1
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = 0.35
	sh.height = 0.2
	cs.shape = sh
	cs.position.y = 0.1
	add_child(cs)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.35
	cm.bottom_radius = 0.35
	cm.height = 0.14
	mi.mesh = cm
	mi.material_override = B.mat(Color(0.12, 0.12, 0.13), 0.0, 0.6)
	mi.position.y = 0.1
	add_child(mi)
	B.box(self, Vector3(0.08, 0.04, 0.08), Vector3(0, 0.19, -0.2), Color(1, 0.1, 0.1), false, 4.0)
	for ang in [-0.3, 0.3]:
		var r := RayCast3D.new()
		r.position = Vector3(0, 0.15, 0)
		r.target_position = Vector3(0, 0, -3).rotated(Vector3.UP, ang)
		r.collision_mask = 1 | 4
		add_child(r)
		rays.append(r)
		var beam := B.box(self, Vector3(0.012, 0.012, 3.0), Vector3(0, 0.15, 0) + Vector3(0, 0, -1.5).rotated(Vector3.UP, ang), Color(1, 0.05, 0.05), false, 6.0)
		beam.rotation.y = ang
	dir = Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)


func _physics_process(delta: float) -> void:
	if armed >= 0.0:
		armed += delta
		_beep -= delta
		if _beep <= 0.0:
			_beep = 0.1
			Sfx.play(self, "beep", global_position, 6.0)
		if armed > FUSE:
			main.explode(global_position, 6.0, 200.0, "A roomba went off.")
			queue_free()
		return
	velocity = dir * SPEED + Vector3(0, -4, 0)
	move_and_slide()
	if is_on_wall():
		dir = dir.rotated(Vector3.UP, randf_range(PI * 0.6, PI * 1.4))
	rotation.y = atan2(-dir.x, -dir.z)
	_click -= delta
	if _click <= 0.0:
		_click = 0.5
		Sfx.play(self, "click", global_position, -10.0)
	for r in rays:
		var hit = r.get_collider()
		if hit and hit.is_in_group("players"):
			armed = 0.0
			Sfx.play(self, "beep", global_position, 6.0)
