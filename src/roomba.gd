# Trap on wheels: an old security cleaning unit. Drives straight, turns randomly on bump, and
# watches the floor ahead with two laser sensors. Break a beam -> it beeps faster and faster -> boom.
extends "res://src/monster.gd"

const SPEED := 1.8
const FUSE := 0.8

var dir := Vector3.FORWARD
var armed := -1.0
var _beep := 0.0
var _click := 0.0
var rays: Array[RayCast3D] = []
var _eye: Node3D
var _ring_mat: StandardMaterial3D
var _brushes: Array[Node3D] = []


func _ready() -> void:
	add_to_group("monsters")
	presence("servo", -10.0, 3.0)
	collision_layer = 8
	collision_mask = 1
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = 0.36
	sh.height = 0.2
	cs.shape = sh
	cs.position.y = 0.1
	add_child(cs)
	# Chassis, rubber bumper, two-tone lid with a handle slot.
	A.cyl(self, 0.35, 0.09, Vector3(0, 0.07, 0), "metal", Color(0.16, 0.16, 0.17))
	A.cyl(self, 0.37, 0.05, Vector3(0, 0.06, 0), "metal", Color(0.07, 0.07, 0.07))
	A.cyl(self, 0.31, 0.03, Vector3(0, 0.125, 0), "metal", Color(0.42, 0.43, 0.45))
	A.cyl(self, 0.2, 0.015, Vector3(0, 0.143, 0.04), "metal", Color(0.12, 0.12, 0.13))
	A.box(self, Vector3(0.14, 0.012, 0.03), Vector3(0, 0.15, 0.15), "metal", Color(0.05, 0.05, 0.05), false)
	A.box(self, Vector3(0.2, 0.01, 0.06), Vector3(0, 0.145, -0.12), "hazard", Color.WHITE, false, 0.3)
	# Status ring that pulses red (faster when armed).
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.22
	tm.outer_radius = 0.24
	ring.mesh = tm
	_ring_mat = glow_mat(Color(1, 0.12, 0.08), 2.0)
	ring.material_override = _ring_mat
	add_child(ring)
	ring.position.y = 0.14
	# Sensor eye: a dome at the front with a sweeping red pupil.
	A.sphere(self, 0.07, Vector3(0, 0.12, -0.31), "metal", Color(0.05, 0.05, 0.06), 0.0, 0.8)
	_eye = Node3D.new()
	add_child(_eye)
	_eye.position = Vector3(0, 0.125, -0.31)
	var pupil := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.03, 0.02, 0.02)
	pupil.mesh = pm
	pupil.material_override = glow_mat(Color(1, 0.1, 0.05), 8.0)
	_eye.add_child(pupil)
	pupil.position.z = -0.06
	var tw := _eye.create_tween().set_loops()
	tw.tween_property(_eye, "rotation:y", 0.6, 0.7).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_eye, "rotation:y", -0.6, 0.7).set_trans(Tween.TRANS_SINE)
	# Two side brushes that spin.
	for side in [-1, 1]:
		var brush := Node3D.new()
		add_child(brush)
		brush.position = Vector3(side * 0.22, 0.02, -0.2)
		for k in 3:
			var bristle := A.box(brush, Vector3(0.16, 0.008, 0.012), Vector3(0.07, 0, 0).rotated(Vector3.UP, k * TAU / 3.0), "metal", Color(0.55, 0.5, 0.4), false, 0.3)
			bristle.rotation.y = k * TAU / 3.0
		A.spin(brush, "y", 0.35 * side)
		_brushes.append(brush)
	# Laser sensors (visible beams so you can learn to step around them).
	for ang in [-0.3, 0.3]:
		var r := RayCast3D.new()
		r.position = Vector3(0, 0.15, -0.3)
		r.target_position = Vector3(0, 0, -3).rotated(Vector3.UP, ang)
		r.collision_mask = 1 | 4
		add_child(r)
		rays.append(r)
		var beam := B.box(self, Vector3(0.01, 0.01, 3.0), Vector3(0, 0.15, -0.3) + Vector3(0, 0, -1.5).rotated(Vector3.UP, ang), Color(1, 0.05, 0.05), false, 6.0)
		beam.rotation.y = ang
	dir = Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)


func _physics_process(delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	if armed >= 0.0:
		armed += delta
		_beep -= delta
		_ring_mat.emission_energy_multiplier = 8.0 if fmod(t * (6.0 + armed * 20.0), 1.0) < 0.5 else 0.5
		if _beep <= 0.0:
			_beep = maxf(0.04, 0.14 - armed * 0.12)
			Sfx.play(self, "beep", global_position, 6.0)
		if armed > FUSE:
			main.explode(global_position, 6.0, 200.0, "A roomba went off.")
			queue_free()
		return
	_ring_mat.emission_energy_multiplier = 1.2 + sin(t * 2.0) * 0.8
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


# --- hits ---

## An armoured shell: hits just glance off in sparks and knock it onto a new heading.
func take_hit(_dmg: float, from: Vector3, by = null) -> void:
	var at := global_position + Vector3(0, 0.15, 0)
	hit_fx(self, at, (from - at).normalized(), "metal")
	if by != null:
		var away: Vector3 = global_position - by.global_position
		away.y = 0.0
		dir = away.normalized()
	if not get_meta("told", false):
		set_meta("told", true)
		main.hud.msg("It just bounces off the casing.")
