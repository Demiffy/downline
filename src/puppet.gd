# Another player, as you see them: the suit (suit.gd) walking where they walk, looking where they
# look, holding what they hold (lit, if it's a light), crouching, falling down dead, a name over
# their head when you're close, and their voice coming from their helmet (voice.gd).
# To the world it's a player: creatures hunt it and the host's hazards hurt it, and whatever
# happens to it is passed on to the person playing it (net.to_owner).
extends Node3D

const Suit = preload("res://src/suit.gd")
const Items = preload("res://src/items.gd")
const Data = preload("res://src/data.gd")

var main
var net
var peer := 0
var display_name := ""

# What creatures and hazards read off a player.
var dead := false
var hp := 100.0
var cam: Camera3D       # where their eyes are (creatures check "is anyone looking at me?")
var head: Node3D
var spot: SpotLight3D
var lamp: OmniLight3D
var slots: Array = [null, null, null, null, null, null]
var sel := 0
var equip = null
var wading := false
var in_train := false
var frozen := false
var crouching := false
var velocity := Vector3.ZERO
var flash := 0.0
var shape := CapsuleShape3D.new()
var speaking := false

var _quiet := false   # setting from their own pose: nothing to pass back
var light_on := false:
	set(v):
		if light_on and not v and net and net.is_host and not _quiet:
			net.to_owner(peer, "light_off")
		light_on = v
var blind := 0.0:
	set(v):
		if v > blind + 0.05 and net and net.is_host:
			net.to_owner(peer, "blind", v)
		blind = v
var trapped = null:
	set(v):
		if (v != null) != (trapped != null) and net and net.is_host:
			net.to_owner(peer, "trapped", v != null)
		trapped = v

var _parts := {}
var _held_id := "-"
var _held: Node3D
var _tag: Label3D
var _target_pos := Vector3.ZERO
var _target_yaw := 0.0
var _target_pitch := 0.0
var _frame := "W"
var _walk := 0.0
var _fallen := false


func _ready() -> void:
	add_to_group("players")
	shape.height = 1.8
	var body := Node3D.new()
	add_child(body)
	body.name = "Body"
	_parts = Suit.standing(body)
	head = Node3D.new()
	add_child(head)
	head.position.y = 1.6
	cam = Camera3D.new()   # never current: just a viewpoint
	head.add_child(cam)
	spot = SpotLight3D.new()
	spot.spot_range = 24.0
	spot.spot_angle = 30.0
	spot.light_energy = 5.0
	spot.shadow_enabled = true
	spot.visible = false
	head.add_child(spot)
	spot.position = Vector3(0.25, -0.35, -0.4)
	lamp = OmniLight3D.new()
	lamp.light_color = Color(1, 0.8, 0.55)
	lamp.light_energy = 1.6
	lamp.omni_range = 9.0
	lamp.shadow_enabled = true
	lamp.visible = false
	add_child(lamp)
	lamp.position = Vector3(0.35, 1.0, -0.2)
	_tag = Label3D.new()   # their name, small, over the helmet when you're near
	_tag.text = display_name
	_tag.font_size = 40
	_tag.pixel_size = 0.004
	_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tag.modulate = Color(1.0, 0.85, 0.55, 0.9)
	_tag.outline_size = 8
	_tag.no_depth_test = false
	add_child(_tag)
	_tag.position.y = 2.15


## Their latest pose: [frame tag, local position, yaw, pitch, height, held id, lit, dead, in_train,
## speaking, level serial].
func set_pose(p: Array) -> void:
	_frame = p[0]
	if p[0] == "L" and p[10] != main.level_serial:
		visible = false   # they're at a stop we haven't reached (or left)
		return
	visible = true
	_target_pos = p[1]
	_target_yaw = p[2]
	_target_pitch = p[3]
	shape.height = p[4]
	crouching = p[4] < 1.6
	var held: String = p[5]
	slots[0] = {"id": held, "charge": 1.0} if held != "" else null
	_quiet = true
	light_on = p[6]
	_quiet = false
	var was_dead := dead
	dead = p[7]
	in_train = p[8]
	speaking = p[9]
	if dead and not was_dead:
		_fall()
	elif not dead and was_dead:
		_stand()
	if held != _held_id:
		_set_held(held)
	if global_position == Vector3.ZERO or global_position.distance_to(net.frame(_frame) * _target_pos) > 6.0:
		global_position = net.frame(_frame) * _target_pos   # first pose, or a teleport: no sliding


func _process(delta: float) -> void:
	if not visible:
		return
	var want: Vector3 = net.frame(_frame) * _target_pos
	var before := global_position
	global_position = global_position.lerp(want, minf(1.0, delta * 12.0))
	var frame_yaw: float = net.frame(_frame).basis.get_euler().y
	rotation.y = lerp_angle(rotation.y, _target_yaw + frame_yaw, minf(1.0, delta * 14.0))
	head.rotation.x = lerpf(head.rotation.x, _target_pitch, minf(1.0, delta * 14.0))
	head.position.y = shape.height - 0.2
	var moved := Vector2(global_position.x - before.x, global_position.z - before.z).length()
	velocity = (global_position - before) / maxf(delta, 0.001)
	var held = slots[0]
	spot.visible = light_on and held != null and held.id == "FLASHLIGHT" and not dead
	lamp.visible = light_on and held != null and held.id == "LANTERN" and not dead
	if not dead:
		_animate(moved, delta)
	var cam_node := get_viewport().get_camera_3d()
	_tag.visible = cam_node != null and cam_node.global_position.distance_to(global_position) < 9.0 and not dead
	if speaking:   # a soft pulse on the name while they talk
		_tag.modulate = Color(0.6, 1.0, 0.6, 0.95)
	else:
		_tag.modulate = Color(1.0, 0.85, 0.55, 0.9)


## Walking: legs swing, arms counter-swing, the body bobs and leans into it; crouched, it sinks
## and bends at the knees; the head follows where they look.
func _animate(moved: float, delta: float) -> void:
	var speed := moved / maxf(delta, 0.001)
	_walk += speed * delta * 2.6
	var amt := clampf(speed / 4.0, 0.0, 1.0)
	var s := sin(_walk)
	var crouch := clampf((1.8 - shape.height) / 0.7, 0.0, 1.0)
	_parts.thigh_l.rotation.x = s * 0.6 * amt + crouch * 0.9
	_parts.thigh_r.rotation.x = -s * 0.6 * amt + crouch * 0.9
	_parts.shin_l.rotation.x = -maxf(0.0, -s) * 0.9 * amt - crouch * 1.5
	_parts.shin_r.rotation.x = -maxf(0.0, s) * 0.9 * amt - crouch * 1.5
	_parts.upper_arm_l.rotation.x = -s * 0.45 * amt + 0.06
	var holding: bool = slots[0] != null
	_parts.upper_arm_r.rotation.x = (s * 0.45 * amt + 0.06) if not holding else (0.9 - _target_pitch * 0.6)
	_parts.forearm_r.rotation.x = 0.28 if not holding else 0.5
	var body: Node3D = get_node("Body")
	body.position.y = -crouch * 0.5 + absf(cos(_walk)) * 0.03 * amt
	_parts.torso.rotation.x = -0.08 * amt - crouch * 0.25
	_parts.head.rotation.x = clampf(_target_pitch, -0.9, 0.9) + crouch * 0.2


func _set_held(id: String) -> void:
	_held_id = id
	if _held:
		_held.queue_free()
		_held = null
	if id == "" or not Data.ITEMS.has(id) or Data.kind(id) == "remains":
		return
	var hand: Node3D = _parts.forearm_r
	_held = Items.build(id)
	hand.add_child(_held)
	var size: Vector3 = Data.ITEMS[id].size
	_held.scale = Vector3.ONE * minf(1.0, 0.5 / maxf(size.x, maxf(size.y, size.z))) if Data.is_heavy(id) else Vector3.ONE
	_held.position = Vector3(0, -0.34, -0.06)
	_held.rotation = Vector3(-PI / 2.0, 0, 0)   # pointing forward out of the fist


func _fall() -> void:
	_fallen = true
	var body: Node3D = get_node("Body")
	var tw := create_tween()
	tw.tween_property(body, "rotation:x", -PI / 2.0, 0.5).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(body, "position:y", 0.2, 0.5)
	visible = false   # the host spawns their remains as a ragdoll where they fell


func _stand() -> void:
	_fallen = false
	var body: Node3D = get_node("Body")
	body.rotation = Vector3.ZERO
	body.position = Vector3.ZERO
	visible = true


# --- what the world does to them: passed on to their player --------------------------------------

func hurt(amount: float, cause := "") -> void:
	if dead or net == null or not net.is_host:
		return
	net.to_owner(peer, "hurt", amount, cause)


func shake(amount: float) -> void:
	if net and net.is_host and amount >= 0.01:
		net.to_owner(peer, "shake", amount)


func drop_held() -> void:
	if net and net.is_host:
		net.to_owner(peer, "drop")


## Something moved them (a trap snapping shut, a snatcher spitting them out).
func move_to(pos: Vector3) -> void:
	global_position = pos
	if net and net.is_host:
		var tag: String = "T" if main.train.on_board(pos) else ("L" if main.level != null else "W")
		net.to_owner(peer, "teleport", tag, net.frame(tag).affine_inverse() * pos)
