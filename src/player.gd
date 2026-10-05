# First-person employee. Footsteps make noise (crouch = silent). 5 slots + 1 equipment slot.
extends CharacterBody3D

const Data = preload("res://src/data.gd")
const B = preload("res://src/build.gd")
const Sfx = preload("res://src/sfx.gd")

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
var held: MeshInstance3D
var rain: GPUParticles3D

var hp := 100.0
var stamina := MAX_STAMINA
var since_hurt := 99.0
var slots: Array = [null, null, null, null, null, null]  # items are {"id", "charge"}
var sel := 0
var equip = null
var light_on := false
var crouching := false
var frozen := false
var dead := false
var in_train := false
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
	cam.fov = 80
	cam.near = 0.05
	head.add_child(cam)
	ray = RayCast3D.new()
	ray.target_position = Vector3(0, 0, -REACH)
	ray.collision_mask = 1 | 2
	cam.add_child(ray)
	spot = SpotLight3D.new()
	spot.spot_range = 24.0
	spot.spot_angle = 26.0
	spot.light_energy = 3.0
	spot.shadow_enabled = true
	spot.visible = false
	cam.add_child(spot)
	spot.position = Vector3(0.2, -0.15, 0)
	lamp = B.omni(head, Vector3(0.3, -0.5, -0.3), Color(1, 0.8, 0.55), 1.6, 9.0, true)
	lamp.visible = false
	B.omni(head, Vector3.ZERO, Color(0.8, 0.85, 1.0), 0.12, 3.0)  # faint personal light so pitch black isn't literal
	held = MeshInstance3D.new()
	held.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF  # don't shadow our own flashlight beam
	cam.add_child(held)
	held.position = Vector3(0.32, -0.28, -0.55)
	rain = _make_rain()
	add_child(rain)


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
		rotate_y(-e.relative.x * MOUSE)
		head.rotation.x = clampf(head.rotation.x - e.relative.y * MOUSE, -1.5, 1.5)
	elif e is InputEventKey and e.pressed and not e.echo:
		if e.keycode >= KEY_1 and e.keycode <= KEY_6:
			_select(e.keycode - KEY_1)
		elif e.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _physics_process(delta: float) -> void:
	if dead:
		return
	var on_floor := is_on_floor()
	if on_floor:
		velocity.y = maxf(velocity.y, -1.0)
	else:
		velocity.y -= 20.0 * delta
	var input := Vector2.ZERO
	if not frozen:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	crouching = not frozen and Input.is_action_pressed("crouch")
	var sprinting := not crouching and not frozen and Input.is_action_pressed("sprint") and input.length() > 0.1 and stamina > 0.0
	if sprinting:
		stamina = maxf(0.0, stamina - delta)
	else:
		stamina = minf(MAX_STAMINA, stamina + delta * MAX_STAMINA / STAMINA_REFILL)
	var speed := CROUCH if crouching else (SPRINT if sprinting else WALK)
	var dir := global_transform.basis * Vector3(input.x, 0, input.y)
	dir.y = 0.0
	dir = dir.normalized() * minf(input.length(), 1.0)
	var accel := 10.0 if on_floor else 2.0
	velocity.x = lerpf(velocity.x, dir.x * speed, minf(1.0, accel * delta))
	velocity.z = lerpf(velocity.z, dir.z * speed, minf(1.0, accel * delta))
	if not frozen and on_floor and not crouching and Input.is_action_just_pressed("jump"):
		velocity.y = 6.0
	shape.height = move_toward(shape.height, CROUCH_H if crouching else STAND_H, delta * 6.0)
	col.position.y = shape.height / 2
	head.position.y = shape.height - 0.2
	move_and_slide()
	var hs := Vector2(velocity.x, velocity.z).length()
	if on_floor and hs > 0.5:
		_step += hs * delta
		if _step > 2.2:
			_step = 0.0
			if not crouching:
				main.noise(global_position, 15.0 if sprinting else 8.0)
				Sfx.play(self, "step", global_position, -8.0 if sprinting else -14.0, randf_range(0.8, 1.2))


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
	lamp.visible = lit and id == "LANTERN"
	if lit:
		it.charge -= delta
		if it.charge <= 0.0:
			light_on = false
			main.hud.msg("%s battery depleted. Recharge on the train." % Data.ITEMS[id].name)
	if in_train:
		for s in slots + [equip]:
			if s != null and s.charge >= 0.0:
				s.charge = minf(Data.ITEMS[s.id].charge, s.charge + 25.0 * delta)


func _interact(delta: float) -> void:
	var t = ray.get_collider() if ray.is_colliding() else null
	if t != _hold_target:
		_hold = 0.0
		_hold_target = t
	var text := ""
	var prog := 0.0
	if t != null and t.is_in_group("pickups"):
		var d: Dictionary = Data.ITEMS[t.id]
		text = "[E] Pick up %s" % d.name
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


func _select(i: int) -> void:
	sel = posmod(i, max_slots())
	light_on = false


func _use() -> void:
	var it = slots[sel]
	if it == null:
		return
	if Data.kind(it.id) == "equip":
		# Using held equipment swaps it into the equipment slot.
		var old = equip
		equip = it
		slots[sel] = old
		Sfx.play(self, "pickup", null, -6.0)
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
	if Data.kind(p.id) == "equip" and equip == null:
		equip = it
	else:
		var i: int = sel if slots[sel] == null else slots.slice(0, max_slots()).find(null)
		if i < 0:
			main.hud.msg("Inventory full. [Q] drops the held item.")
			Sfx.play(self, "error", null, -8.0)
			return
		slots[i] = it
	p.queue_free()
	Sfx.play(self, "pickup", null, -6.0)


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
	var p = main.spawn_item(it.id, pos, it.charge)
	p.linear_velocity = fwd * 3.0 + velocity


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
	if id == "":
		held.mesh = null
		return
	var size: Vector3 = Data.ITEMS[id].size
	var bm := BoxMesh.new()
	bm.size = size
	held.mesh = bm
	held.material_override = B.mat(Data.color(id), 0.0, 0.3)
	held.scale = Vector3.ONE * minf(0.7, 0.25 / size.length())


func _make_rain() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 600
	p.lifetime = 1.2
	p.emitting = false
	p.local_coords = false
	p.position.y = 12.0
	p.visibility_aabb = AABB(Vector3(-20, -20, -20), Vector3(40, 40, 40))
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(15, 1, 15)
	m.direction = Vector3(0, -1, 0)
	m.spread = 5.0
	m.initial_velocity_min = 14.0
	m.initial_velocity_max = 18.0
	m.gravity = Vector3(0, -9.8, 0)
	p.process_material = m
	var bm := BoxMesh.new()
	bm.size = Vector3(0.02, 0.5, 0.02)
	bm.material = B.mat(Color(0.5, 1, 0.3), 1.5)
	p.draw_pass_1 = bm
	return p
