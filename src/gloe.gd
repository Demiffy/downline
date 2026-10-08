# Gloe: the only friendly thing down here. A drifting orb of light that picks one employee as its
# best friend and floats beside them, lighting the way. Leave the facility and it waits for someone new.
extends Node3D

const Sfx = preload("res://src/sfx.gd")

var main
var level
var friend = null
var _orb: MeshInstance3D
var _light: OmniLight3D
var _t := 0.0


func _ready() -> void:
	add_to_group("fauna")   # the scanner sees it (field guide)
	var hum := AudioStreamPlayer3D.new()
	hum.stream = Sfx.stream("chime")
	hum.volume_db = -12.0
	hum.unit_size = 2.0
	hum.max_distance = 30.0
	hum.bus = "World"
	add_child(hum)
	hum.play.call_deferred(randf() * 2.0)
	var colors := [Color(1, 0.9, 0.5), Color(0.6, 1, 0.7), Color(0.6, 0.85, 1), Color(1, 0.7, 0.9), Color(1, 1, 0.95)]
	var c: Color = colors[randi() % colors.size()]
	_orb = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.14
	sm.height = 0.28
	_orb.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 8.0
	_orb.material_override = m
	_orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # its own light sits inside it
	add_child(_orb)
	var halo := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.3
	hm.height = 0.6
	halo.mesh = hm
	var h := StandardMaterial3D.new()
	h.albedo_color = Color(c, 0.18)
	h.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	h.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo.material_override = h
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(halo)
	_light = OmniLight3D.new()
	_light.light_color = c
	_light.light_energy = 1.6
	_light.omni_range = 8.0
	_light.shadow_enabled = true
	add_child(_light)
	_t = randf() * 10.0


func _process(delta: float) -> void:
	_t += delta
	var home := global_position
	if friend == null or not is_instance_valid(friend) or friend.dead or friend.global_position.y > -20.0 \
			or friend.global_position.distance_to(global_position) > 16.0:
		friend = null
		for p in main.players():
			if not p.dead and p.global_position.distance_to(global_position) < 7.0 and p.global_position.y < -20.0:
				friend = p
				Sfx.play(self, "ding", global_position, -10.0, 2.0)
				break
	if friend != null:
		var side: Vector3 = friend.global_transform.basis.x * 0.7 - friend.global_transform.basis.z * 0.5
		home = friend.global_position + Vector3(0, 2.2, 0) + side
	var bob := Vector3(sin(_t * 1.3) * 0.15, sin(_t * 2.1) * 0.12, cos(_t * 1.1) * 0.15)
	global_position = global_position.lerp(home + bob, minf(1.0, delta * 2.5))
	_light.light_energy = 1.5 + sin(_t * 3.0) * 0.15


## A copy (it goes where the host's goes): just its glow, breathing.
func net_visual(delta: float) -> void:
	_t += delta
	_light.light_energy = 1.5 + sin(_t * 3.0) * 0.15
