# The Leviathan: a vast segmented worm under the dunes, active late in the day. Every so often
# the ground rumbles — that's it listening. Make a sound on the surface during a rumble and it
# marks the spot, the ground cracks, and it bursts out in an arc to swallow everything there.
# A solid roof over your head saves you. Crouch and keep still until the rumbling stops.
extends Node3D

const A = preload("res://src/art.gd")
const B = preload("res://src/build.gd")
const Sfx = preload("res://src/sfx.gd")

enum { IDLE, RUMBLE, WARN, ERUPT }
const SEGMENTS := 18
const KILL_RADIUS := 3.6

var main
var level
var state := IDLE
var _t := 0.0
var _next := 0.0
var _target := Vector3.ZERO
var _dir := Vector3.FORWARD
var _worm: Node3D
var _segs: Array[Node3D] = []
var _rumble: AudioStreamPlayer
var _dust: GPUParticles3D
var _killed := false


func _ready() -> void:
	add_to_group("ground_listeners")
	_next = randf_range(15.0, 30.0)
	_rumble = AudioStreamPlayer.new()
	_rumble.stream = Sfx.stream("rumble")
	_rumble.volume_db = -4.0
	add_child(_rumble)
	_worm = Node3D.new()
	add_child(_worm)
	_worm.visible = false
	var flesh := Color(0.62, 0.42, 0.36)
	for i in SEGMENTS:
		var seg := Node3D.new()
		_worm.add_child(seg)
		var r := lerpf(1.6, 0.7, float(i) / SEGMENTS)
		A.cyl(seg, r, 1.5, Vector3.ZERO, "rock", flesh.darkened(0.15 * (i % 2)), false, "z")
		A.cyl(seg, r * 1.05, 0.25, Vector3(0, 0, 0.7), "rust", Color(0.7, 0.6, 0.55), false, "z")
		for k in 4:   # ridge spikes along the back
			if k == 0:
				var spike := A.box(seg, Vector3(0.2, r * 0.7, 0.3), Vector3(0, r + r * 0.25, 0), "rock", flesh.darkened(0.35), false, 1.0)
				spike.rotation.x = -0.3
		_segs.append(seg)
	# The head: a ring of teeth around a glowing gullet.
	var head := _segs[0]
	A.cyl(head, 1.75, 0.5, Vector3(0, 0, -0.85), "flesh", Color(0.8, 0.5, 0.5), false, "z")
	for k in 16:
		var a := TAU * k / 16.0
		var tooth := A.box(head, Vector3(0.18, 0.6, 0.18), Vector3(cos(a) * 1.35, sin(a) * 1.35, -1.2), "cream", Color(0.95, 0.9, 0.78), false, 0.3)
		tooth.rotation = Vector3(0, 0, a + PI / 2)
		tooth.rotate_object_local(Vector3.RIGHT, -0.5)
	var gullet := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.1
	sm.height = 1.2
	gullet.mesh = sm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.5, 0.05, 0.05)
	gm.emission_enabled = true
	gm.emission = Color(1, 0.25, 0.1)
	gm.emission_energy_multiplier = 1.5
	gullet.material_override = gm
	head.add_child(gullet)
	gullet.position.z = -0.6
	_dust = GPUParticles3D.new()
	_dust.amount = 160
	_dust.lifetime = 1.6
	_dust.one_shot = true
	_dust.explosiveness = 0.7
	_dust.emitting = false
	_dust.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 2.0
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 60.0
	pm.initial_velocity_min = 3.0
	pm.initial_velocity_max = 9.0
	pm.gravity = Vector3(0, -9.0, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.6
	_dust.process_material = pm
	var bm := BoxMesh.new()
	bm.size = Vector3(0.25, 0.25, 0.25)
	bm.material = A.mat("sand", Color.WHITE, 1.0)
	_dust.draw_pass_1 = bm
	add_child(_dust)


func _surface_players() -> Array:
	return main.players().filter(func(p): return not p.dead and p.global_position.y > -20.0)


## Called for every noise in the world (see main.noise).
func hear(pos: Vector3) -> void:
	if state != RUMBLE or pos.y < -20.0:
		return
	state = WARN
	_t = 0.0
	_target = Vector3(pos.x, 0.0, pos.z)
	_dir = Vector3(1, 0, 0).rotated(Vector3.UP, randf() * TAU)
	_rumble.volume_db = 2.0
	Sfx.play(self, "roar", _target, 14.0, 0.6)
	_burst(_target, 50)


func _burst(at: Vector3, n: int) -> void:
	_dust.global_position = at
	_dust.amount = n
	_dust.restart()
	_dust.emitting = true


func _process(delta: float) -> void:
	_t += delta
	match state:
		IDLE:
			if _t > _next and not _surface_players().is_empty():
				state = RUMBLE
				_t = 0.0
				_rumble.volume_db = -4.0
				_rumble.play()
				main.hud.msg("The ground is shaking. Something below is listening...")
		RUMBLE:
			for p in _surface_players():
				p.shake(0.012)
			if _t > 7.0:
				_rumble.stop()
				_go_idle()
		WARN:
			for p in _surface_players():
				p.shake(0.03)
			if _t > 1.4:
				state = ERUPT
				_t = 0.0
				_killed = false
				_worm.visible = true
				_burst(_target + _dir * 9.0, 160)
				Sfx.play(self, "boom", _target, 12.0, 0.5)
		ERUPT:
			var dur := 2.4
			for i in SEGMENTS:
				var u := clampf((_t - i * 0.06) / dur, 0.0, 1.0)
				var p := _arc(u)
				var ahead := _arc(minf(u + 0.02, 1.0))
				_segs[i].visible = u > 0.0 and u < 1.0
				_segs[i].global_position = p
				if ahead.distance_to(p) > 0.001:
					_segs[i].look_at(ahead, Vector3.UP if absf((ahead - p).normalized().y) < 0.98 else Vector3.RIGHT)
			var head_u := clampf(_t / dur, 0.0, 1.0)
			if not _killed and head_u > 0.78:   # head reaches the ground at the target here
				_killed = true
				_burst(_target, 160)
				Sfx.play(self, "boom", _target, 14.0, 0.4)
				for p in _surface_players():
					var d := Vector2(p.global_position.x - _target.x, p.global_position.z - _target.z).length()
					if d < KILL_RADIUS and not _roofed(p.global_position):
						p.hurt(500.0, "Swallowed whole by the leviathan.")
					elif d < 12.0:
						p.shake(0.08)
			if _t > dur + SEGMENTS * 0.06:
				_worm.visible = false
				_rumble.stop()
				_go_idle()


func _go_idle() -> void:
	state = IDLE
	_t = 0.0
	_next = randf_range(25.0, 45.0)


## Leap path: out of the sand 12 m away, up in an arc, down onto the target, and under.
func _arc(u: float) -> Vector3:
	var p0 := _target + _dir * 13.0 + Vector3(0, -6, 0)
	var p1 := _target + _dir * 9.0 + Vector3(0, 22, 0)
	var p2 := _target + Vector3(0, 10, 0)
	var p3 := _target - _dir * 3.0 + Vector3(0, -10, 0)
	var a := p0.lerp(p1, u)
	var b := p1.lerp(p2, u)
	var c := p2.lerp(p3, u)
	return a.lerp(b, u).lerp(b.lerp(c, u), u)


func _roofed(pos: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 1.9, 0), pos + Vector3(0, 40, 0), 1)
	return not get_world_3d().direct_space_state.intersect_ray(q).is_empty()
