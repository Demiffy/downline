# First-person employee. Footsteps make noise (crouch = silent). 5 slots + 1 equipment slot.
extends CharacterBody3D

const Data = preload("res://src/data.gd")
const Suit = preload("res://src/suit.gd")
const Blood = preload("res://src/blood.gd")
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
const BODY_LAYER := 1 << 19   # your own suit: other cameras see it (observer photos, security feeds), yours doesn't

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
var _crouch_on := false
var _sprint_on := false
var _bob := 0.0
var _bob_off := Vector2.ZERO
var _sway := Vector2.ZERO

var hp := 100.0
var max_stamina := MAX_STAMINA
var stamina := MAX_STAMINA
var since_hurt := 99.0
var slots: Array = [null, null, null, null, null, null, null]  # items are {"id", "charge"}
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
var blind := 0.0   # white-out from the observer's flashbulb (1 = can't see a thing), fades on its own
var suit: Node3D
var inspecting := false   # holding a photo up to your face
var fear := 0.0           # 0..1: how close the danger is (drives breathing and heartbeat)
var _attack_cd := 0.0
var _bled := 0.0     # damage since the last splat (gas and acid hurt a little every frame)
var _drip := 0.0
var _heart_p: AudioStreamPlayer
var _step := 0.0
var _scan_cd := 0.0
var _hold := 0.0
var _hold_target: Object
var _held_id := "-"
var _asking: Array = []   # host items we asked for, not in our hands yet
var _shown_cracks := 0
var _shown_armor := false
var _suit_parts := {}
var _shown_lamp := false
var _shown_goggles := [false, false]
const HELMET_CELL := 300.0   # seconds of headlamp / night vision on a full helmet cell
var helmet_charge := HELMET_CELL
var headlamp_on := false
var nv_on := false
var headlamp: SpotLight3D
var _ir: OmniLight3D       # night vision's infrared lamp: invisible to the eye, bright through the goggles
var _stim := 0.0           # adrenaline left in you (seconds)
var crack_tier := 0        # the visor: 0 whole, 1-3 cracked (the worst it got since you were last at full health)


func _ready() -> void:
	add_to_group("players")
	add_to_group("movable")
	collision_layer = 4
	collision_mask = 1 | 16   # world + railing panels
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
	cam.cull_mask = 0xFFFFF & ~BODY_LAYER
	head.add_child(cam)
	_suit()
	ray = RayCast3D.new()
	ray.target_position = Vector3(0, 0, -REACH)
	ray.collision_mask = 1 | 2
	cam.add_child(ray)
	spot = SpotLight3D.new()
	spot.spot_range = 24.0
	spot.spot_angle = 30.0
	spot.light_energy = 5.0
	spot.shadow_enabled = true
	spot.light_volumetric_fog_energy = 5.0   # (the beam shows in the haze down there)
	spot.visible = false
	cam.add_child(spot)
	spot.position = Vector3(0.115, -0.125, -0.45)   # just ahead of the lens
	spot.light_cull_mask = 0xFFFFF & ~Viewmodel.LAYER   # lights the world, not your own hand
	headlamp = SpotLight3D.new()   # (HEADLAMP upgrade) on the helmet's brow, follows your look
	headlamp.spot_range = 20.0
	headlamp.spot_angle = 38.0
	headlamp.light_energy = 3.2
	headlamp.light_color = Color(1.0, 0.93, 0.8)
	headlamp.shadow_enabled = true
	headlamp.visible = false
	headlamp.light_cull_mask = 0xFFFFF & ~Viewmodel.LAYER
	cam.add_child(headlamp)
	headlamp.position = Vector3(0, 0.12, -0.05)
	_ir = B.omni(cam, Vector3(0, 0.2, 0), Color(0.9, 1.0, 0.9), 1.6, 22.0)   # (the IR illuminator: bright through the tube)
	_ir.visible = false
	lamp = B.omni(head, Vector3(0.3, -0.5, -0.3), Color(1, 0.8, 0.55), 1.6, 9.0, true)
	lamp.visible = false
	B.omni(head, Vector3.ZERO, Color(0.8, 0.85, 1.0), 0.12, 3.0)  # faint personal light so pitch black isn't literal
	arm = Viewmodel.new()   # first-person sleeve, glove and held item
	cam.add_child(arm)
	_heart_p = _loop("heart")
	_weather["ACID_RAIN"] = _particles(Color(0.5, 1, 0.3), Vector3(0.02, 0.5, 0.02), Vector3(0, -1, 0), 16.0, 600, 1.2, 1.5)
	_weather["SANDSTORM"] = _particles(Color(0.8, 0.55, 0.3), Vector3(0.05, 0.05, 0.05), Vector3(1, -0.1, 0.2), 14.0, 900, 1.5, 0.0)
	_weather["BLIZZARD"] = _particles(Color(0.95, 0.97, 1.0), Vector3(0.025, 0.025, 0.025), Vector3(1, -0.25, 0.35), 15.0, 1600, 1.3, 0.25)
	_weather["RAIN"] = _particles(Color(0.7, 0.75, 0.82, 0.45), Vector3(0.008, 0.45, 0.008), Vector3(0.04, -1, 0.02), 17.0, 900, 1.1, 0.0)
	_weather["STORM"] = _particles(Color(0.72, 0.76, 0.85, 0.5), Vector3(0.009, 0.55, 0.009), Vector3(0.3, -1, 0.12), 22.0, 1700, 0.9, 0.0)
	_weather["SNOW"] = _particles(Color(0.95, 0.95, 1.0), Vector3(0.05, 0.05, 0.05), Vector3(0.2, -1, 0), 2.0, 700, 5.0, 0.3)
	# What's overhead, as the weather sees it: rain, snow and sand stop at a roof (the train's, a
	# platform's) instead of falling through it onto you.
	var roof := GPUParticlesCollisionHeightField3D.new()
	roof.size = Vector3(44, 40, 44)
	roof.resolution = GPUParticlesCollisionHeightField3D.RESOLUTION_512
	roof.update_mode = GPUParticlesCollisionHeightField3D.UPDATE_MODE_ALWAYS
	roof.follow_camera_enabled = true
	add_child(roof)
	var dust := _particles(Color(0.85, 0.8, 0.7), Vector3(0.015, 0.015, 0.015), Vector3(0, 0.1, 0), 0.05, 160, 7.0, 0.0, Vector3(5, 2.5, 5))
	dust.position.y = 1.4
	dust.emitting = true


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount * float(Settings.v.get("shake", 1.0)))


func set_weather(kind: String) -> void:
	for k in _weather:
		_weather[k].emitting = k == kind


func max_slots() -> int:
	return 5 + (1 if equip != null and equip.id == "BACKPACK" else 0) + (1 if main != null and main.has_upgrade("CARGO_HARNESS") else 0)


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
		if e.is_action_pressed("headlamp"):
			_toggle_headlamp()
		elif e.is_action_pressed("night_vision"):
			_toggle_nv()
		elif k >= KEY_1 and k <= KEY_7:
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
	# Held, or pressed once to toggle (settings): a toggled sprint ends when you stop or run out of breath.
	if Settings.v.get("crouch_toggle", false):
		if not frozen and Input.is_action_just_pressed("crouch"):
			_crouch_on = not _crouch_on
	else:
		_crouch_on = Input.is_action_pressed("crouch")
	if Settings.v.get("sprint_toggle", false):
		if not frozen and Input.is_action_just_pressed("sprint"):
			_sprint_on = not _sprint_on
		if input.length() < 0.1 or stamina <= 0.0:
			_sprint_on = false
	else:
		_sprint_on = Input.is_action_pressed("sprint")
	crouching = not frozen and _crouch_on
	if crouching and Input.is_action_just_pressed("sprint"):
		_crouch_on = false   # (sprinting gets you up)
		crouching = false
	var sprinting := not crouching and not frozen and _sprint_on and input.length() > 0.1 and stamina > 0.0
	if sprinting and _stim <= 0.0:   # (adrenaline: it doesn't run out)
		stamina = maxf(0.0, stamina - delta)
	else:
		stamina = minf(max_stamina, stamina + delta * max_stamina / STAMINA_REFILL)
	var heavy := carrying_heavy()
	if heavy:
		sprinting = false
	var speed := (CROUCH if crouching else (SPRINT if sprinting else WALK)) * (0.58 if heavy else 1.0) * (0.62 if wading else 1.0) * (1.15 if _stim > 0.0 else 1.0)
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
				main.noise(global_position, ((15.0 if sprinting else 8.0) + (5.0 if heavy else 0.0) + (6.0 if wading else 0.0)) * (0.5 if main.has_upgrade("SOFT_SOLES") else 1.0))
				Sfx.play(self, "step_" + main.surface_at(global_position), global_position, -6.0 if sprinting else -11.0, randf_range(0.88, 1.12))


func _process(delta: float) -> void:
	_fear_sounds(delta)
	if dead:
		return
	_attack_cd -= delta
	_bled = maxf(0.0, _bled - delta * 2.0)
	if hp < 40.0:   # badly hurt: you leave a trail of drips, faster the worse it is
		_drip -= delta
		if _drip <= 0.0:
			_drip = lerpf(0.5, 2.2, hp / 40.0) * randf_range(0.7, 1.3)
			bleed(randf_range(0.07, 0.16), 0.15)
	flash = maxf(0.0, flash - delta * 1.5)
	_stim = maxf(0.0, _stim - delta)
	var tier := 3 if hp < 20.0 else (2 if hp < 45.0 else (1 if hp < 75.0 else 0))
	if tier > crack_tier:
		crack_tier = tier
		Sfx.play(self, "crack_glass", null, -6.0, randf_range(0.9, 1.1))
	elif hp >= 99.5 and crack_tier > 0:   # patched up to full: a fresh visor
		crack_tier = 0
	if main.has_upgrade("ARMORED_SUIT") != _shown_armor:
		_shown_armor = main.has_upgrade("ARMORED_SUIT")
		Suit.set_armor(suit, _shown_armor)
		for mi: MeshInstance3D in suit.find_children("*", "MeshInstance3D", true, false):
			mi.layers = BODY_LAYER   # (your own suit, plates and straps included: only other cameras see it)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var gog := [main.has_upgrade("NIGHT_VISION"), nv_on]
	if gog != _shown_goggles:
		_shown_goggles = gog
		Suit.set_goggles(suit, gog[0], gog[1])
		for mi: MeshInstance3D in suit.find_children("*", "MeshInstance3D", true, false):
			mi.layers = BODY_LAYER
	if headlamp_on != _shown_lamp:
		_shown_lamp = headlamp_on
		Suit.set_headlamp(suit, headlamp_on)
		for mi: MeshInstance3D in suit.find_children("*", "MeshInstance3D", true, false):
			mi.layers = BODY_LAYER
	if crack_tier != _shown_cracks:
		_shown_cracks = crack_tier
		Suit.set_cracks(suit, crack_tier)
	if in_train and main.has_upgrade("INFIRMARY") and hp < 100.0:   # the train's cot and cabinet
		hp = minf(100.0, hp + delta * 8.0)
	blind = maxf(0.0, blind - delta * 0.2)
	suit.scale.y = shape.height / STAND_H
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
			main.hud.msg("%s battery depleted. Recharge it at the charging rack on the train." % Data.ITEMS[id].name)
	if id == "WALKIE" and it.charge > 0.0 and main.net.voice != null and main.net.voice.speaking:   # keyed up
		it.charge = maxf(0.0, it.charge - delta)
		if it.charge <= 0.0:
			main.hud.msg("Walkie battery flat. Recharge it at the charging rack on the train.")
	# The helmet cell runs the headlamp and the night-vision goggles.
	var draw := (1.0 if headlamp_on else 0.0) + (1.0 if nv_on else 0.0)
	if draw > 0.0:
		helmet_charge = maxf(0.0, helmet_charge - draw * delta)
		if helmet_charge <= 0.0:
			headlamp_on = false
			nv_on = false
			main.hud.msg("Helmet cell flat. Recharge it at the charging rack on the train.")
	headlamp.visible = headlamp_on
	_ir.visible = nv_on


func _interact(delta: float) -> void:
	var t = ray.get_collider() if ray.is_colliding() else null
	if t != null and t.has_meta("ragdoll"):   # any part of a body means the body
		t = t.get_meta("ragdoll")
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
	elif t != null and _can_pin(t):
		text = "[E] Pin the photo to the wall"
		if not frozen and Input.is_action_just_pressed("interact"):
			var it = slots[sel]
			slots[sel] = null
			main.pin_photo(it, ray.get_collision_point(), ray.get_collision_normal())
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


## Holding a photo, looking at a wall of the train (not the floor or ceiling): it can go up there.
func _can_pin(t: Object) -> bool:
	var it = slots[sel]
	return it != null and it.id == "PHOTO" and t is Node and main.train.is_ancestor_of(t) \
		and absf(ray.get_collision_normal().y) < 0.4 and not t.has_method("interact")


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
	if Data.kind(it.id) == "photo":
		inspecting = not inspecting
		arm.set_inspect(inspecting)
		Sfx.play(self, "rustle", null, -10.0, 1.4)
		return
	if Data.kind(it.id) == "weapon":
		_attack(it)
		return
	match Data.kind(it.id):
		"medkit":
			if hp >= 100.0:
				main.hud.msg("You're not hurt.")
				return
			slots[sel] = null
			hp = 100.0
			since_hurt = 99.0
			Sfx.play(self, "rustle", null, -4.0, 0.8)
			Sfx.play(self, "blip", null, -10.0, 0.7)
			main.hud.msg("Patched up. Good as new, nearly.")
			return
		"ammo":   # load the shotgun you carry
			for g in slots:
				if g != null and g.id == "SHOTGUN":
					if not _reload(g):
						main.hud.msg("The shotgun's full.")
					return
			main.hud.msg("No shotgun to load.")
			return
		"stim":
			slots[sel] = null
			_stim = 20.0
			stamina = max_stamina
			Sfx.play(self, "click", null, -2.0, 0.6)
			main.hud.msg("Adrenaline. Twenty seconds: move.")
			return
		"wedge":   # jam the swing door you're looking at
			var t = ray.get_collider() if ray.is_colliding() else null
			var door = t.get_parent().get_parent() if t != null and t.get_parent() != null else null
			if door == null or not door.has_method("set_wedged"):
				main.hud.msg("Look at a swing door to wedge it.")
				return
			if door.wedged:
				main.hud.msg("That one's already wedged.")
				return
			slots[sel] = null
			main.wedge_door(door)
			main.hud.msg("Wedged shut. It'll hold a while.")
			return
		"flare", "lure":   # strike it / wind it, and throw it
			slots[sel] = null
			it.extra = {"active": true}
			Sfx.play(self, "hiss" if it.id == "FLARE" else "click", null, -6.0, 1.3)
			_throw(it, 7.0)
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


# --- fighting ---------------------------------------------------------------------------

func _attack(it: Dictionary) -> void:
	if _attack_cd > 0.0:
		return
	var d: Dictionary = Data.ITEMS[it.id]
	_attack_cd = d.swing
	if it.id == "SHOTGUN":
		if it.charge < 1.0:
			if _reload(it):
				return
			Sfx.play(self, "dry_fire", null, -4.0)
			main.hud.msg("Out of shells. Buy a box (SHOP), or find one down there.")
			_attack_cd = 0.3
			return
		it.charge -= 1.0
		arm.recoil()
		main.net.act("shoot")
		Sfx.play(self, "shotgun", global_position + Vector3.UP * 1.5, 8.0, randf_range(0.95, 1.05))
		main.noise(global_position, 60.0)
		shake(0.05)
		_shoot(d)
		return
	var lands: float = arm.swing(it.id, d.swing)
	main.net.act("swing", lands)
	Sfx.play(self, "swish", null, -6.0, randf_range(0.85, 1.1) * (0.8 if it.id == "FIRE_AXE" else 1.0))
	await get_tree().create_timer(lands, false).timeout
	if not dead and slots[sel] == it:
		_melee(d)


## The swing lands: the nearest creature in front of you within reach (nothing solid in between),
## else whatever wall or crate is there.
func _melee(d: Dictionary) -> void:
	var from := cam.global_position
	var fwd := -cam.global_transform.basis.z
	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.65
	q.shape = sh
	q.transform = Transform3D(Basis(), from + fwd * (d.reach * 0.55))
	q.collision_mask = 8 | 64   # bodies and hit boxes (monster.gd HITBOX)
	var best = null
	var bd := INF
	for hit in space.intersect_shape(q, 12):
		var m = hit.collider
		if m != null and m.has_meta("monster"):
			m = m.get_meta("monster")
		if m == null or not m.has_method("take_hit"):
			continue
		var to: Vector3 = m.global_position + Vector3(0, 0.6, 0) - from
		if fwd.dot(to.normalized()) < 0.35 or to.length() > d.reach + 0.7:
			continue
		var los := PhysicsRayQueryParameters3D.create(from, from + to, 1)
		los.exclude = [get_rid(), m.get_rid()]
		if not space.intersect_ray(los).is_empty():
			continue
		if to.length() < bd:
			bd = to.length()
			best = m
	main.noise(global_position, 9.0)
	if best != null:
		main.hit_entity(best, d.damage, from)
		shake(0.02)
		return
	var ray_q := PhysicsRayQueryParameters3D.create(from, from + fwd * d.reach, 1)
	ray_q.exclude = [get_rid()]
	var wall := space.intersect_ray(ray_q)
	if not wall.is_empty():   # clanged off something
		Sfx.play(self, "clank", wall.position, 0.0, randf_range(0.8, 1.0))
		main.noise(wall.position, 14.0)
		shake(0.015)


## Eight pellets in a tight cone; each creature takes the sum of what hit it.
## Load the shotgun from a box of shells you carry (it takes a moment, a shell at a time).
func _reload(gun: Dictionary) -> bool:
	var cap: float = main.charge_max("SHOTGUN")
	for i in slots.size():
		var box = slots[i]
		if box == null or box.id != "SHELLS" or box.charge < 1.0:
			continue
		var n := mini(int(cap - gun.charge), int(box.charge))
		if n <= 0:
			return false
		gun.charge += n
		box.charge -= n
		if box.charge < 1.0:
			slots[i] = null
		_attack_cd = 0.45 * n + 0.3
		for k in n:
			get_tree().create_timer(0.45 * k, false).timeout.connect(func(): Sfx.play(self, "clack", null, -6.0, randf_range(0.9, 1.05)))
		get_tree().create_timer(0.45 * n, false).timeout.connect(func(): Sfx.play(self, "clunk", null, -8.0, 1.3))
		main.hud.msg("Loaded %d shell%s (%d in the box)." % [n, "" if n == 1 else "s", int(box.charge)])
		return true
	return false


func _shoot(d: Dictionary) -> void:
	var from := cam.global_position
	var cb := cam.global_transform.basis
	var space := get_world_3d().direct_space_state
	var dmg := {}
	for i in int(d.pellets):
		var spread := Vector2(randf_range(-1, 1), randf_range(-1, 1)).limit_length(1.0) * 0.07
		var dir: Vector3 = (-cb.z + cb.x * spread.x + cb.y * spread.y).normalized()
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * d.reach, 1 | 8 | 64)   # (64: monster.gd HITBOX)
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		var c = hit.collider
		if c != null and c.has_meta("monster"):
			c = c.get_meta("monster")
		if c != null and c.has_method("take_hit"):
			dmg[c] = dmg.get(c, 0.0) + d.damage
		elif i % 3 == 0:
			main.noise(hit.position, 12.0)
	for m in dmg:
		if is_instance_valid(m):
			main.hit_entity(m, dmg[m], from)


# --- fear -----------------------------------------------------------------------------------

func _loop(sound: String) -> AudioStreamPlayer:
	var a := AudioStreamPlayer.new()
	a.stream = Sfx.stream(sound)
	a.volume_db = -80.0
	add_child(a)
	a.play.call_deferred()
	return a


## Your heartbeat inside the helmet: silent when calm; loud and fast when something close is after
## you or you're badly hurt.
func _fear_sounds(delta: float) -> void:
	var f := 0.0
	if not dead:
		for m in get_tree().get_nodes_in_group("monsters"):
			var dist: float = m.global_position.distance_to(global_position)
			if dist < 16.0:
				var k := 1.0 - dist / 16.0
				if m.has_method("is_hunting") and m.is_hunting():
					k = minf(1.0, k * 1.6 + 0.25)
				f = maxf(f, k)
		f = maxf(f, (1.0 - hp / 100.0) * 0.85)
	fear = lerpf(fear, f, minf(1.0, delta * (2.5 if f > fear else 0.35)))
	_heart_p.volume_db = linear_to_db(maxf(0.0001, (fear - 0.15) * 1.1)) if not dead else -80.0
	_heart_p.pitch_scale = 1.0 + fear * 1.3


func _scan() -> void:
	if equip == null or equip.id != "SCANNER":
		main.hud.msg("No scanner equipped.")
		return
	if _scan_cd > 0.0:
		return
	var boost: bool = main.has_upgrade("SIGNAL_BOOSTER")
	_scan_cd = 3.0 if boost else 5.0
	main.scan(global_position, 26.0 if boost else 16.0)


func _pick(p) -> void:
	if carrying_heavy():
		main.hud.msg("Both hands are full. [Q] to set it down.")
		return
	if not _room_for(p.id):
		return
	if main.net.puppet_mirror(p):   # it's the host's: ask for it (it lands in our hands when they say so)
		if not p.has_meta("asked"):
			# Gone from the floor straight away, here: the crosshair finds the next thing at once,
			# as quick as the host picks up. If the host says no (someone beat us to it), it's back.
			p.set_meta("asked", true)
			p.visible = false
			p.collision_layer = 0
			_asking.append(p)
			main.net.request("pick", [main.net.id_of(p)])
			get_tree().create_timer(1.5).timeout.connect(func():
				_asking.erase(p)
				if is_instance_valid(p) and not p.is_queued_for_deletion():
					p.visible = true
					p.collision_layer = 2
					p.remove_meta("asked"))
		return
	var it := {"id": p.id, "charge": p.charge, "extra": p.extra}
	p.queue_free()
	take(it)


## Is there a hand (or the equipment slot) free for this? (Things asked for from the host and
## not here yet count as taking a hand.)
func _room_for(id: String) -> bool:
	_asking = _asking.filter(func(q): return is_instance_valid(q) and not q.is_queued_for_deletion())
	var free := slots.slice(0, max_slots()).count(null) - _asking.filter(func(q): return Data.kind(q.id) != "equip").size()
	if not _asking.is_empty() and free <= 0 and not (Data.kind(id) == "equip" and equip == null):
		main.hud.msg("Inventory full. [Q] drops the held item.")
		Sfx.play(self, "error", null, -8.0)
		return false
	if Data.is_heavy(id):
		if slots[sel] != null and slots.slice(0, max_slots()).find(null) < 0:
			main.hud.msg("You need a free hand slot to lift that.")
			Sfx.play(self, "error", null, -8.0)
			return false
		return true
	if Data.kind(id) == "equip" and equip == null:
		return true
	if slots[sel] == null or slots.slice(0, max_slots()).find(null) >= 0:
		return true
	main.hud.msg("Inventory full. [Q] drops the held item.")
	Sfx.play(self, "error", null, -8.0)
	return false


## An item into our hands (picked up here, or handed over by the host).
func take(it: Dictionary) -> void:
	if not it.has("extra"):
		it.extra = {}
	if Data.is_heavy(it.id):
		if carrying_heavy() or (slots[sel] != null and slots.slice(0, max_slots()).find(null) < 0):
			_throw(it)   # (no room after all: it goes back on the floor)
			return
		if slots[sel] != null:
			sel = slots.slice(0, max_slots()).find(null)
		slots[sel] = it
		light_on = false
		Sfx.play(self, "heavy_lift", global_position, -2.0)
		main.hud.msg("Heavy: slow going, no running. [Q] to set it down.")
		return
	if Data.kind(it.id) == "equip" and equip == null:
		equip = it
		main.hud.msg("Equipped %s.%s" % [Data.ITEMS[it.id].name, "  [F] or middle mouse to scan." if it.id == "SCANNER" else ""])
	else:
		var i: int = sel if slots[sel] == null else slots.slice(0, max_slots()).find(null)
		if i < 0:
			_throw(it)
			return
		slots[i] = it
	Sfx.play(self, "rustle", null, -6.0, randf_range(0.9, 1.15))


## The host took something out of our hands (remains carried aboard).
func consume(id: String) -> void:
	for i in slots.size():
		if slots[i] != null and slots[i].id == id:
			slots[i] = null
			return


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
	if equip.id == "BACKPACK":   # the slot it gave you goes with it
		var last := max_slots() - 1
		if slots[last] != null:
			_throw(slots[last])
			slots[last] = null
	_throw(equip)
	equip = null
	sel = mini(sel, max_slots() - 1)


func _throw(it: Dictionary, speed := 3.0) -> void:
	var fwd := -cam.global_transform.basis.z
	var pos := cam.global_position + fwd * 0.7
	if ray.is_colliding() and ray.get_collision_point().distance_to(cam.global_position) < 0.9:
		pos = ray.get_collision_point() - fwd * 0.3
	if Data.is_heavy(it.id):   # set down in front of you, not thrown
		pos = global_position + Vector3(fwd.x, 0, fwd.z).normalized() * 0.9 + Vector3(0, 0.6, 0)
	var vel: Vector3 = (fwd * 0.6 if Data.is_heavy(it.id) else fwd * speed + Vector3(0, speed * 0.25, 0)) + velocity
	if not main.net.authority():   # the host makes the item; we just say where and how fast
		var tag: String = "T" if main.train.on_board(pos) else ("L" if main.level != null else "W")
		main.net.request("drop", [main.net.item_to_wire(it), tag, main.net.frame(tag).affine_inverse() * pos, vel])
		return
	var p = main.spawn_item(it.id, pos, it.charge)
	p.set_extra(it.get("extra", {}))
	p.linear_velocity = vel


func _toggle_headlamp() -> void:
	if dead or frozen:
		return
	if not main.has_upgrade("HEADLAMP"):
		main.hud.msg("No headlamp. The HEADLAMP upgrade fits one to the helmet.")
		return
	if helmet_charge <= 0.0:
		main.hud.msg("Helmet cell flat. Recharge it at the charging rack on the train.")
		return
	headlamp_on = not headlamp_on
	Sfx.play(self, "click", null, -6.0, 1.2)


func _toggle_nv() -> void:
	if dead or frozen:
		return
	if not main.has_upgrade("NIGHT_VISION"):
		main.hud.msg("No goggles. The NIGHT_VISION upgrade fits them to the helmet.")
		return
	if helmet_charge <= 0.0:
		main.hud.msg("Helmet cell flat. Recharge it at the charging rack on the train.")
		return
	nv_on = not nv_on
	Sfx.play(self, "flash_whine" if nv_on else "click", null, -16.0, 1.6)


## Talking over the radio: a walkie in hand with some battery left.
func transmitting() -> bool:
	var it = slots[sel]
	return not dead and it != null and it.id == "WALKIE" and float(it.charge) > 0.0


## Hearing the radio: a walkie with some battery anywhere in your slots.
func has_radio() -> bool:
	return not dead and slots.any(func(it): return it != null and it.id == "WALKIE" and float(it.charge) > 0.0)


func helmet_max() -> float:
	return HELMET_CELL * (1.6 if main.has_upgrade("BATTERY_PACK") else 1.0)


## The charging rack on the train: every battery you carry topped up, shells restocked.
func recharge() -> void:
	var n := 0
	for s in slots + [equip]:   # (batteries: the shotgun's shells come in boxes now)
		if s != null and Data.kind(s.id) in ["weapon", "ammo"]:
			continue
		if s != null and float(s.get("charge", -1.0)) >= 0.0 and s.charge < main.charge_max(s.id):
			s.charge = main.charge_max(s.id)
			n += 1
	if main.has_upgrade("HEADLAMP") or main.has_upgrade("NIGHT_VISION"):
		if helmet_charge < helmet_max():
			n += 1
		helmet_charge = helmet_max()
	Sfx.play(self, "power_up", null, -10.0, 1.6)
	main.hud.msg("Charged." if n > 0 else "Nothing here needs charging.")


func hurt(amount: float, cause := "") -> void:
	if dead:
		return
	if main.net.active and not main.net.is_host and not _net_ok:
		return   # with a crew, damage is the host's to deal (it arrives as net_hurt)
	if main.has_upgrade("ARMORED_SUIT"):
		amount *= 0.75
	hp -= amount
	flash = minf(1.0, flash + amount / 40.0)
	_bled += amount
	if _bled >= 8.0:   # a real hit: a splat under you, bigger the harder it was
		for i in clampi(int(_bled / 20.0), 1, 4):
			bleed(clampf(0.25 + _bled * 0.008, 0.3, 0.9), 0.35)
		_bled = 0.0
	if since_hurt > 0.5:
		Sfx.play(self, "hurt", null, -2.0)
	since_hurt = 0.0
	if hp <= 0.0:
		die(cause)


## Blood on the floor near you, kept by whatever you're standing in (the train or the station).
func bleed(size: float, spread: float) -> void:
	var host: Node3D = main.train if in_train else (main.level if main.level != null else main)
	var at := global_position + Vector3(randf_range(-spread, spread), 0.3, randf_range(-spread, spread))
	Blood.spill(host, at, size)
	main.net.blood(host, at, size)   # (the crew sees it on their floor too)


## A line for you (creatures and the world use this for whoever it's meant for; puppets pass it on).
func say(text: String) -> void:
	main.hud.msg(text)


func fog_visor(amount: float) -> void:
	main.hud.fog_visor(amount)


## The ringing after a flash goes off in your face.
func ring_ears() -> void:
	Sfx.play(self, "tinnitus", null, -10.0)


var _net_ok := false

## Damage the host dealt us.
func net_hurt(amount: float, cause: String) -> void:
	_net_ok = true
	hurt(amount, cause)
	_net_ok = false


func die(cause: String) -> void:
	if dead:
		return
	dead = true
	hp = 0.0
	bleed(1.2, 0.1)   # a pool where you fell
	suit.visible = false
	light_on = false
	spot.visible = false
	lamp.visible = false
	headlamp_on = false
	nv_on = false
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


## Back on your feet at `pos` (the Bureau's recovery after a death or being left behind).
func revive(pos: Vector3) -> void:
	dead = false
	hp = 100.0
	crack_tier = 0
	blind = 0.0
	suit.visible = true
	stamina = max_stamina
	flash = 0.0
	trapped = null
	frozen = false
	velocity = Vector3.ZERO
	global_position = pos
	rotation.y = -PI / 2
	head.rotation = Vector3.ZERO
	head.position.y = shape.height - 0.2


## The employee as everyone else sees them (suit.gd). Only on BODY_LAYER, so it never gets in
## your own way (no shadows, nothing to collide with).
func _suit() -> void:
	suit = Node3D.new()
	add_child(suit)
	_suit_parts = Suit.standing(suit)
	for mi: MeshInstance3D in suit.find_children("*", "MeshInstance3D", true, false):
		mi.layers = BODY_LAYER
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _held_visual() -> void:
	var it = slots[sel]
	var id: String = it.id if it != null else ""
	if id == _held_id:
		return
	_held_id = id
	inspecting = false
	arm.set_item(id, it.get("extra", {}) if it != null else {})
	Suit.set_held(suit, _suit_parts, id, BODY_LAYER)   # (your suit, as photos and camera feeds see you, holds it too)


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
	if speed >= 1.0:   # weather: gone where it meets a roof (the height field over you: see _ready)
		m.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	p.process_material = m
	# Fading out as they come close to your eyes (a speck an inch from the lens would fill the
	# screen as a big square otherwise).
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	mat.distance_fade_min_distance = 0.35 if speed < 1.0 else 0.15
	mat.distance_fade_max_distance = 1.4 if speed < 1.0 else 0.7
	if emit > 0.0:
		mat.emission_enabled = true
		mat.emission = c
		mat.emission_energy_multiplier = emit
	if size.x == size.y and size.y == size.z:   # specks and flakes: soft round dots, not cubes
		var q := QuadMesh.new()
		q.size = Vector2(size.x, size.x) * 1.6
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL   # (dust: unseen in the dark, it shows where a light falls on it)
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(1.0, 0.5)
		gt.width = 32
		gt.height = 32
		mat.albedo_texture = gt
		if speed < 1.0:
			mat.albedo_color = Color(c, 0.55)   # dust: faint
		q.material = mat
		p.draw_pass_1 = q
	else:
		var bm := BoxMesh.new()
		bm.size = size
		bm.material = mat
		p.draw_pass_1 = bm
	add_child(p)
	return p
