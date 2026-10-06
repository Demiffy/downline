# First-person employee. Footsteps make noise (crouch = silent). 5 slots + 1 equipment slot.
extends CharacterBody3D

const Data = preload("res://src/data.gd")
const B = preload("res://src/build.gd")
const Sfx = preload("res://src/sfx.gd")
const Viewmodel = preload("res://src/viewmodel.gd")
const Settings = preload("res://src/settings.gd")

signal died(cause: String)

const MAX_STAMINA := 7.0   # seconds of sprint
const STAMINA_REFILL := 4.0
const WALK := 4.0
const SPRINT := 6.5
const CROUCH := 2.0
const STAND_H := 1.8
const CROUCH_H := 1.1
const REACH := 2.6
const MOUSE := 0.0025

var main
var head: Node3D
var cam: Camera3D
var ray: RayCast3D
var shape: CapsuleShape3D
var col: CollisionShape3D
var spot: SpotLight3D
var lamp: OmniLight3D
var arm   # viewmodel.gd
var _weather := {}       # kind -> particle system
var _shake := 0.0
var _bob := 0.0
var _bob_off := Vector2.ZERO
var _sway := Vector2.ZERO

var hp := 100.0
var max_stamina := MAX_STAMINA
var stamina := MAX_STAMINA
var since_hurt := 99.0
var slots: Array = [null, null, null, null, null, null]  # items are {"id", "charge"}
var sel := 0
var equip = null
var light_on := false
var crouching := false
var frozen := false
var trapped = null   # a bear trap holding this player
var dead := false
var in_train := false
var wading := false   # knee-deep in flood water (set by hazards.gd)
var flash := 0.0
var _step := 0.0
var _scan_cd := 0.0
var _hold := 0.0
var _hold_target: Object
var _held_id := "-"


func _ready() -> void:
	add_to_group("players")
	add_to_group("movable")
	collision_layer = 4
	collision_mask = 1
	shape = CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = STAND_H
	col = CollisionShape3D.new()
	col.shape = shape
	col.position.y = STAND_H / 2
	add_child(col)
	head = Node3D.new()
	head.position.y = STAND_H - 0.2
	add_child(head)
	cam = Camera3D.new()
	cam.fov = float(Settings.v.fov)
	cam.near = 0.05
	head.add_child(cam)
	ray = RayCast3D.new()
	ray.target_position = Vector3(0, 0, -REACH)
	ray.collision_mask = 1 | 2
	cam.add_child(ray)
	spot = SpotLight3D.new()
	spot.spot_range = 24.0
	spot.spot_angle = 30.0
	spot.light_energy = 5.0
	spot.shadow_enabled = true
	spot.visible = false
	cam.add_child(spot)
	spot.position = Vector3(0.115, -0.125, -0.45)   # just ahead of the lens
	spot.light_cull_mask = 0xFFFFF & ~Viewmodel.LAYER   # lights the world, not your own hand
	lamp = B.omni(head, Vector3(0.3, -0.5, -0.3), Color(1, 0.8, 0.55), 1.6, 9.0, true)
	lamp.visible = false
	B.omni(head, Vector3.ZERO, Color(0.8, 0.85, 1.0), 0.12, 3.0)  # faint personal light so pitch black isn't literal
	arm = Viewmodel.new()   # first-person sleeve, glove and held item
	cam.add_child(arm)
	_weather["ACID_RAIN"] = _particles(Color(0.5, 1, 0.3), Vector3(0.02, 0.5, 0.02), Vector3(0, -1, 0), 16.0, 600, 1.2, 1.5)
	_weather["SANDSTORM"] = _particles(Color(0.8, 0.55, 0.3), Vector3(0.05, 0.05, 0.05), Vector3(1, -0.1, 0.2), 14.0, 900, 1.5, 0.0)
	_weather["SNOW"] = _particles(Color(0.95, 0.95, 1.0), Vector3(0.05, 0.05, 0.05), Vector3(0.2, -1, 0), 2.0, 700, 5.0, 0.3)
	var dust := _particles(Color(0.85, 0.8, 0.7), Vector3(0.015, 0.015, 0.015), Vector3(0, 0.1, 0), 0.05, 160, 7.0, 0.0, Vector3(5, 2.5, 5))
	dust.position.y = 1.4
	dust.emitting = true


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func set_weather(kind: String) -> void:
	for k in _weather:
		_weather[k].emitting = k == kind


func max_slots() -> int:
	return 6 if equip != null and equip.id == "BACKPACK" else 5


func _unhandled_input(e: InputEvent) -> void:
	if dead or frozen:
		return
	if e is InputEventMouseButton and e.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			return
		match e.button_index:
			MOUSE_BUTTON_WHEEL_UP: _select(sel - 1)
			MOUSE_BUTTON_WHEEL_DOWN: _select(sel + 1)
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT: _use()
			MOUSE_BUTTON_MIDDLE: _scan()
	elif e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens: float = MOUSE * float(Settings.v.sens)
		rotate_y(-e.relative.x * sens)
		_sway = (_sway - e.relative * 0.0006).limit_length(0.12)
		head.rotation.x = clampf(head.rotation.x - e.relative.y * sens * (-1.0 if Settings.v.invert_y else 1.0), -1.5, 1.5)
	elif e is InputEventKey and e.pressed and not e.echo:
		# Physical key position, so the number row works on any keyboard layout (e.g. Czech types + ě š č...).
		var k: int = e.physical_keycode if e.physical_keycode != KEY_NONE else e.keycode
		if k >= KEY_1 and k <= KEY_6:
			_select(k - KEY_1)


func _physics_process(delta: float) -> void:
	if dead:
		return
	var on_floor := is_on_floor()
	if on_floor:
		velocity.y = maxf(velocity.y, -1.0)
	else:
		velocity.y -= 20.0 * delta
	var input := Vector2.ZERO
	if not frozen and trapped == null:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	crouching = not frozen and Input.is_action_pressed("crouch")
	var sprinting := not crouching and not frozen and Input.is_action_pressed("sprint") and input.length() > 0.1 and stamina > 0.0
	if sprinting:
		stamina = maxf(0.0, stamina - delta)
	else:
		stamina = minf(max_stamina, stamina + delta * max_stamina / STAMINA_REFILL)
	var heavy := carrying_heavy()
	if heavy:
		sprinting = false
	var speed := (CROUCH if crouching else (SPRINT if sprinting else WALK)) * (0.58 if heavy else 1.0) * (0.62 if wading else 1.0)
	var dir := global_transform.basis * Vector3(input.x, 0, input.y)
	dir.y = 0.0
	dir = dir.normalized() * minf(input.length(), 1.0)
	var accel := 10.0 if on_floor else 2.0
	velocity.x = lerpf(velocity.x, dir.x * speed, minf(1.0, accel * delta))
	velocity.z = lerpf(velocity.z, dir.z * speed, minf(1.0, accel * delta))
	if not frozen and trapped == null and on_floor and not crouching and not heavy and Input.is_action_just_pressed("jump"):
		velocity.y = 6.0
	shape.height = move_toward(shape.height, CROUCH_H if crouching else STAND_H, delta * 6.0)
	col.position.y = shape.height / 2
	head.position.y = shape.height - 0.2
	var fall_speed := -velocity.y
	move_and_slide()
	if not on_floor and is_on_floor() and fall_speed > 4.0:   # landed
		Sfx.play(self, "land", global_position, -6.0 + minf(fall_speed - 4.0, 8.0), randf_range(0.9, 1.05))
		Sfx.play(self, "step_" + main.surface_at(global_position), global_position, -4.0, 0.8)
		main.noise(global_position, 8.0 + fall_speed)
		shake(minf(0.03, fall_speed * 0.002))
	var hs := Vector2(velocity.x, velocity.z).length()
	if on_floor and hs > 0.5:
		_bob += hs * delta * 1.8
		_bob_off = Vector2(cos(_bob) * 0.025, absf(sin(_bob)) * 0.045) * minf(1.0, hs / 4.0) * (1.0 if Settings.v.head_bob else 0.15)
	else:
		_bob_off = _bob_off.lerp(Vector2.ZERO, minf(1.0, delta * 8.0))
	if on_floor and hs > 0.5:
		_step += hs * delta
		if _step > 2.2:
			_step = 0.0
			if not crouching or wading:   # water splashes however you walk
				main.noise(global_position, (15.0 if sprinting else 8.0) + (5.0 if heavy else 0.0) + (6.0 if wading else 0.0))
				Sfx.play(self, "step_" + main.surface_at(global_position), global_position, -6.0 if sprinting else -11.0, randf_range(0.88, 1.12))


func _process(delta: float) -> void:
	if dead:
		return
	flash = maxf(0.0, flash - delta * 1.5)
	since_hurt += delta
	if since_hurt > 3.0:
		# Above 50 you heal back to 100; at 50 or below you're stuck at 50.
		var cap := 100.0 if hp > 50.0 else 50.0
		if hp < cap:
			hp = minf(cap, hp + delta * 2.5)
	_scan_cd -= delta
	_shake = move_toward(_shake, 0.0, delta * 0.1)
	cam.h_offset = _bob_off.x + randf_range(-1.0, 1.0) * _shake
	cam.v_offset = _bob_off.y + randf_range(-1.0, 1.0) * _shake
	_sway = _sway.lerp(Vector2.ZERO, minf(1.0, delta * 6.0))
	arm.rotation = Vector3(_sway.y, _sway.x, 0)
	_tools(delta)
	_interact(delta)
	_held_visual()
	if global_position.y < -150.0:
		die("Fell into the dark.")


func _tools(delta: float) -> void:
	var it = slots[sel]
	var id: String = it.id if it != null else ""
	var lit: bool = light_on and it != null and it.charge > 0.0
	spot.visible = lit and id == "FLASHLIGHT"
	arm.set_lit(lit)
	lamp.visible = lit and id == "LANTERN"
	if lit:
		it.charge -= delta
		if it.charge <= 0.0:
			light_on = false
			main.hud.msg("%s battery depleted. Recharge on the train." % Data.ITEMS[id].name)
	if in_train:
		for s in slots + [equip]:
			if s != null and s.charge >= 0.0:
				s.charge = minf(main.charge_max(s.id), s.charge + 25.0 * delta)


func _interact(delta: float) -> void:
	var t = ray.get_collider() if ray.is_colliding() else null
	if t != _hold_target:
		_hold = 0.0
		_hold_target = t
	var text := ""
	var prog := 0.0
	if t != null and t.is_in_group("pickups"):
		var d: Dictionary = Data.ITEMS[t.id]
		text = ("[E] Lift %s  (HEAVY, both hands)" if d.get("heavy", false) else "[E] Pick up %s") % d.name
		if Data.kind(t.id) == "scrap":
			text += "   (%s)" % Data.res_text(d.res)
		if not frozen and Input.is_action_just_pressed("interact"):
			_pick(t)
	elif t != null and t.has_method("interact"):
		var hold: float = t.hold_time
		text = ("[Hold E] " if hold > 0.0 else "[E] ") + t.prompt
		if not frozen and hold <= 0.0 and Input.is_action_just_pressed("interact"):
			t.interact(self)
		elif not frozen and hold > 0.0 and Input.is_action_pressed("interact") and _hold >= 0.0:
			_hold += delta
			prog = _hold / hold
			if _hold >= hold:
				_hold = -1.0  # must release E before it can trigger again
				t.interact(self)
	if not Input.is_action_pressed("interact"):
		_hold = 0.0
	if not frozen:
		if Input.is_action_just_pressed("drop"):
			_drop()
		if Input.is_action_just_pressed("drop_equip"):
			_drop_equip()
		if Input.is_action_just_pressed("scan"):
			_scan()
	main.hud.set_prompt(text, prog)


## Holding something heavy takes both hands: slow, no sprint or jump, can't switch until you drop it.
func carrying_heavy() -> bool:
	return slots[sel] != null and Data.is_heavy(slots[sel].id)


func _select(i: int) -> void:
	if carrying_heavy():
		main.hud.msg("Both hands are full. [Q] to set it down.")
		return
	sel = posmod(i, max_slots())
	light_on = false


func _use() -> void:
	var it = slots[sel]
	if it == null:
		return
	if Data.kind(it.id) == "disk":
		if not in_train:
			main.hud.msg("Bring the disk to the train to upload it.")
			return
		slots[sel] = null
		main.upload_disk()
		return
	if Data.kind(it.id) == "equip":
		# Using held equipment swaps it into the equipment slot.
		var old = equip
		equip = it
		slots[sel] = old
		Sfx.play(self, "rustle", null, -6.0, randf_range(0.9, 1.15))
		return
	if it.id in ["FLASHLIGHT", "LANTERN"]:
		if it.charge <= 0.0:
			main.hud.msg("Battery is empty. Recharge it on the train.")
			return
		light_on = not light_on
		Sfx.play(self, "click", null, -4.0)


func _scan() -> void:
	if equip == null or equip.id != "SCANNER":
		main.hud.msg("No scanner equipped.")
		return
	if _scan_cd > 0.0:
		return
	_scan_cd = 5.0
	main.scan(global_position, 14.0)


func _pick(p) -> void:
	var it := {"id": p.id, "charge": p.charge}
	if carrying_heavy():
		main.hud.msg("Both hands are full. [Q] to set it down.")
		return
	if Data.is_heavy(p.id):
		if slots[sel] != null:
			var free := slots.slice(0, max_slots()).find(null)
			if free < 0:
				main.hud.msg("You need a free hand slot to lift that.")
				Sfx.play(self, "error", null, -8.0)
				return
			sel = free
		slots[sel] = it
		light_on = false
		p.queue_free()
		Sfx.play(self, "heavy_lift", global_position, -2.0)
		main.hud.msg("Heavy: slow going, no running. [Q] to set it down.")
		return
	if Data.kind(p.id) == "equip" and equip == null:
		equip = it
		main.hud.msg("Equipped %s.%s" % [Data.ITEMS[p.id].name, "  [F] or middle mouse to scan." if p.id == "SCANNER" else ""])
	else:
		var i: int = sel if slots[sel] == null else slots.slice(0, max_slots()).find(null)
		if i < 0:
			main.hud.msg("Inventory full. [Q] drops the held item.")
			Sfx.play(self, "error", null, -8.0)
			return
		slots[i] = it
	p.queue_free()
	Sfx.play(self, "rustle", null, -6.0, randf_range(0.9, 1.15))


## Let go of whatever is in hand (monsters can make you do this).
func drop_held() -> void:
	_drop()


func _drop() -> void:
	var it = slots[sel]
	if it == null:
		return
	slots[sel] = null
	light_on = false
	_throw(it)


func _drop_equip() -> void:
	if equip == null:
		return
	if equip.id == "BACKPACK" and slots[5] != null:
		_throw(slots[5])
		slots[5] = null
	_throw(equip)
	equip = null
	sel = mini(sel, max_slots() - 1)


func _throw(it: Dictionary) -> void:
	var fwd := -cam.global_transform.basis.z
	var pos := cam.global_position + fwd * 0.7
	if ray.is_colliding() and ray.get_collision_point().distance_to(cam.global_position) < 0.9:
		pos = ray.get_collision_point() - fwd * 0.3
	if Data.is_heavy(it.id):   # set down in front of you, not thrown
		pos = global_position + Vector3(fwd.x, 0, fwd.z).normalized() * 0.9 + Vector3(0, 0.6, 0)
	var p = main.spawn_item(it.id, pos, it.charge)
	p.linear_velocity = (fwd * 0.6 if Data.is_heavy(it.id) else fwd * 3.0) + velocity


func hurt(amount: float, cause := "") -> void:
	if dead:
		return
	hp -= amount
	flash = minf(1.0, flash + amount / 40.0)
	if since_hurt > 0.5:
		Sfx.play(self, "hurt", null, -2.0)
	since_hurt = 0.0
	if hp <= 0.0:
		die(cause)


func die(cause: String) -> void:
	if dead:
		return
	dead = true
	hp = 0.0
	light_on = false
	spot.visible = false
	lamp.visible = false
	for i in slots.size():
		if slots[i] != null:
			_throw(slots[i])
			slots[i] = null
	if equip != null:
		_throw(equip)
		equip = null
	var tw := create_tween()
	tw.tween_property(head, "position:y", 0.3, 0.6)
	tw.parallel().tween_property(head, "rotation:z", 1.2, 0.6)
	died.emit(cause)


func _held_visual() -> void:
	var it = slots[sel]
	var id: String = it.id if it != null else ""
	if id == _held_id:
		return
	_held_id = id
	arm.set_item(id)


## World-space particles that follow the player (weather, dust motes).
func _particles(c: Color, size: Vector3, dir: Vector3, speed: float, amount: int, life: float, emit: float, extents := Vector3(15, 1, 15)) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.emitting = false
	p.local_coords = false
	p.position = Vector3(-dir.x * 6.0, 8.0 if dir.y < -0.5 else 1.5, -dir.z * 6.0)
	p.visibility_aabb = AABB(Vector3(-25, -25, -25), Vector3(50, 50, 50))
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = extents
	m.direction = dir.normalized()
	m.spread = 8.0
	m.initial_velocity_min = speed * 0.8
	m.initial_velocity_max = speed * 1.2
	m.gravity = Vector3.ZERO
	m.turbulence_enabled = speed < 1.0
	p.process_material = m
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = B.mat(c, emit)
	p.draw_pass_1 = bm
	add_child(p)
	return p
