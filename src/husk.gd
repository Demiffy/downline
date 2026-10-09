# A Husk: a dead employee's body that lay too long in the dark, taken by whatever the wraiths are.
# It gets up in a shroud of cold mist with two pale points of light behind the visor and wanders.
# When it sees you it comes to arm's length and stands there, staring, head tilting, whispering,
# for a few long seconds; then it goes for you. It backs off and stares again. Kill it and it
# falls, just a body again (and still worth carrying home).
extends "res://src/monster.gd"

const Suit = preload("res://src/suit.gd")

enum { WANDER, APPROACH, STARE, ATTACK }
const SIGHT := 18.0
const STARE_AT := 2.4
const DAMAGE := 40.0

var state := WANDER
var prey
var _t := 0.0
var _stare := 5.0
var _goal := Vector3.ZERO
var _wander := 0.0
var _parts := {}
var _whisper: AudioStreamPlayer3D
var _eyes: Array[StandardMaterial3D] = []


func _ready() -> void:
	_setup_body(0.32, 1.8)
	health = 90.0
	hit_kind = "cloth"
	var body := Node3D.new()
	add_child(body)
	body.name = "Body"
	_parts = Suit.standing(body)
	for mi: MeshInstance3D in body.find_children("*", "MeshInstance3D", true, false):   # greyed, as if frost-burnt
		var m := mi.material_override as StandardMaterial3D
		if m != null:
			var d := m.duplicate() as StandardMaterial3D
			d.albedo_color = Color(0.3, 0.33, 0.38)   # drained of colour, frost-blue
			d.rim_enabled = true
			d.rim = 0.4
			mi.material_override = d
	Suit.set_cracks(body, 3)
	for s in [-1.0, 1.0]:   # two pale lights where the eyes were
		var e := glow_mat(Color(0.75, 0.85, 1.0), 6.0)
		var eye := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.012
		sm.height = 0.024
		eye.mesh = sm
		eye.material_override = e
		_parts.head.add_child(eye)
		eye.position = Vector3(s * 0.04, 0.165, -0.178)   # just behind the glass
		_eyes.append(e)
	_whisper = presence("whisper", -10.0, 3.0)
	_mist()
	_goal = global_position


func _mist() -> void:
	var p := GPUParticles3D.new()
	p.amount = 20
	p.lifetime = 2.2
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.25, 0.8, 0.2)
	pm.direction = Vector3(0, 0.3, 0)
	pm.spread = 60.0
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.2
	pm.gravity = Vector3(0, -0.1, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.3
	var fade := Gradient.new()
	fade.set_color(0, Color(0.5, 0.55, 0.62, 0.0))
	fade.add_point(0.3, Color(0.5, 0.55, 0.62, 0.18))
	fade.set_color(fade.get_point_count() - 1, Color(0.5, 0.55, 0.62, 0.0))
	var ft := GradientTexture1D.new()
	ft.gradient = fade
	pm.color_ramp = ft
	p.process_material = pm
	var qm := QuadMesh.new()
	qm.size = Vector2(0.5, 0.5)
	var mm := StandardMaterial3D.new()
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mm.vertex_color_use_as_albedo = true
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	mm.albedo_texture = gt
	qm.material = mm
	p.draw_pass_1 = qm
	add_child(p)
	p.position.y = 0.9


func _physics_process(delta: float) -> void:
	_t += delta
	match state:
		WANDER:
			_wander -= delta
			if _wander <= 0.0 or global_position.distance_to(_goal) < 1.0:
				_wander = randf_range(5.0, 10.0)
				_goal = level.wander_point(global_position) if level else global_position
			walk_to(_goal, 1.1, delta, 3.0)
			var p = nearest_player(SIGHT, true)
			if p != null:
				prey = p
				state = APPROACH
				Sfx.play(self, "whisper", global_position + Vector3.UP * 1.6, -4.0, 0.8)
		APPROACH:
			if not _valid():
				return
			var d: float = global_position.distance_to(prey.global_position)
			var v := walk_to(prey.global_position, 1.6, delta, 5.0) if d > STARE_AT else Vector3.ZERO
			if d <= STARE_AT or (v == Vector3.ZERO and d < STARE_AT + 1.6):   # (or as close as the way gets)
				state = STARE
				_t = 0.0
				_stare = randf_range(4.0, 6.0)
		STARE:   # standing there, close, looking at you
			if not _valid():
				return
			stand_still(delta)
			face(prey.global_position, delta, 6.0)
			if global_position.distance_to(prey.global_position) > STARE_AT + 3.0:
				state = APPROACH
			elif _t > _stare:
				state = ATTACK
				_t = 0.0
				show_act("attack")
		ATTACK:
			if not _valid():
				return
			var v := walk_to(prey.global_position, 5.0, delta, 14.0)
			var dd: float = global_position.distance_to(prey.global_position)
			if dd < 1.2 or (v == Vector3.ZERO and dd < 2.2):
				prey.hurt(DAMAGE, "Your old crewmate didn't recognise you.")
				Sfx.play(self, "wraith_grab", global_position + Vector3.UP * 1.4, 2.0, 0.9)
				state = APPROACH   # back off to arm's length, and stare again
				_t = 0.0
			elif _t > 2.0:
				state = APPROACH
	_animate(delta)


func _valid() -> bool:
	if prey == null or not is_instance_valid(prey) or prey.dead or not sees(prey):
		_t = 0.0 if state != WANDER else _t
		if prey == null or not is_instance_valid(prey) or prey.dead or global_position.distance_to(prey.global_position) > SIGHT:
			state = WANDER
			prey = null
			return false
	return true


func is_hunting() -> bool:
	return state != WANDER


func act(what: String, _args: Array) -> void:
	if what == "attack":
		Sfx.play(self, "wraith_shriek", global_position + Vector3.UP * 1.6, 0.0, 0.8)


## A shambling walk; staring, the head tilts slowly over and the eyes flare.
func _animate(_delta: float) -> void:
	var g := _anim * 2.4
	var moving := velocity.length() > 0.2
	var amt := 0.5 if moving else 0.0
	_parts.thigh_l.rotation.x = sin(g) * amt
	_parts.thigh_r.rotation.x = -sin(g) * amt
	_parts.shin_l.rotation.x = -maxf(0.0, -sin(g)) * amt
	_parts.shin_r.rotation.x = -maxf(0.0, sin(g)) * amt
	var reach := 1.3 if state == ATTACK else (0.15 if state == STARE else 0.05)
	_parts.upper_arm_l.rotation.x = reach - sin(g) * amt * 0.3
	_parts.upper_arm_r.rotation.x = reach + sin(g) * amt * 0.3
	var tilt := (sin(_t * 0.6) * 0.55) if state == STARE else 0.12
	_parts.head.rotation = Vector3(0.15, 0, tilt)
	_parts.torso.rotation.x = 0.12 + sin(g * 2.0) * 0.03 * amt
	for e in _eyes:
		e.emission_energy_multiplier = 7.0 if state == STARE or state == ATTACK else 3.0


func net_visual(delta: float) -> void:
	_t += delta
	super.net_visual(delta)


## It drops: a body again.
func death_anim() -> void:
	if main and main.net.authority() and level != null:
		var r = main.spawn_item("REMAINS", global_position + Vector3(0, 0.3, 0), -1.0, level)
		if r:
			r.set_meta("no_possess", true)
	queue_free()
