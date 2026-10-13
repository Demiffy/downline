# A swivel office chair on casters: E to sit in it; sat, you scoot it about with your feet (WASD,
# slowly) and it turns with you; space (or sprint) gets you up. Empty, walk into it and it rolls off,
# and keeps rolling a little. Its seat and back swivel on the post, the star base turns lazily after
# the way it's going. Everyone sees it where it is (net.act "chair": the key, where, which way, sat).
extends "res://src/interact.gd"

const A = preload("res://src/art.gd")
const Merge = preload("res://src/merge.gd")
const Sfx = preload("res://src/sfx.gd")

var top: Node3D       # the seat, back and arms on the post: turns with whoever's sat
var base: Node3D      # the star and its casters
var sitter = null     # the player sat in it, here (null: empty, or someone else's)
var taken := false    # someone's sat in it (here or on another machine)
var _vel := Vector3.ZERO
var _spin := 0.0   # how fast it is turning (rad/s): shoved off-centre, it spins away
var _send := 0.0
var _creak := 0.0
var _shape: CollisionShape3D


## Build one at `at` (in `parent`'s frame), facing `yaw`, `tint` its upholstery.
static func make(parent: Node3D, at: Vector3, yaw: float, tint := Color(0.16, 0.16, 0.17)) -> Node3D:
	var c = load("res://src/office_chair.gd").new()
	parent.add_child(c)
	c.position = at
	c.build(yaw, tint)
	return c


func build(yaw: float, tint: Color) -> void:
	prompt = "Sit"
	shared = false   # (sitting is yours alone; where the chair goes is passed on by net.act)
	action = func(): _sit_down()
	add_to_group("office_chairs")
	_shape = CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.6, 1.0, 0.6)
	_shape.shape = bs
	_shape.position.y = 0.5
	add_child(_shape)
	var dark := Color(0.12, 0.12, 0.13)
	var chrome := Color(0.7, 0.72, 0.74)
	base = Node3D.new()
	add_child(base)
	for k in 5:   # the star: five legs out to a caster each
		var a := TAU * k / 5.0
		var tip := Vector3(cos(a) * 0.31, 0.07, sin(a) * 0.31)
		A.seg(base, Vector3(0, 0.1, 0), tip, 0.022, 0.016, "metal", chrome)
		A.box(base, Vector3(0.03, 0.05, 0.05), tip + Vector3(0, -0.01, 0), "plastic", dark, false, 0.2)
		var wheel := A.cyl(base, 0.032, 0.03, tip + Vector3(0, -0.035, 0.0), "rubber", Color.WHITE, false, "x")
		wheel.rotation.y = a
	A.cyl(base, 0.05, 0.08, Vector3(0, 0.1, 0), "plastic", dark, false)
	top = Node3D.new()
	add_child(top)
	A.cyl(top, 0.026, 0.3, Vector3(0, 0.27, 0), "metal", chrome, false)   # the gas post
	A.cyl(top, 0.034, 0.12, Vector3(0, 0.18, 0), "plastic", dark, false)  # its shroud
	A.box(top, Vector3(0.24, 0.04, 0.24), Vector3(0, 0.43, 0), "metal", dark, false, 0.2)   # the tilt plate
	A.box(top, Vector3(0.5, 0.08, 0.48), Vector3(0, 0.48, 0), "leather", tint, false, 0.4)   # the seat
	A.box(top, Vector3(0.46, 0.03, 0.44), Vector3(0, 0.525, 0), "leather", tint.lightened(0.06), false, 0.4)
	var back := A.box(top, Vector3(0.46, 0.5, 0.07), Vector3(0, 0.86, 0.25), "leather", tint, false, 0.4)
	back.rotation.x = -0.12
	A.seg(top, Vector3(0, 0.46, 0.2), Vector3(0, 0.66, 0.28), 0.02, 0.02, "metal", dark)   # the spine
	for sx in [-1.0, 1.0]:   # arms
		A.seg(top, Vector3(sx * 0.24, 0.47, 0.06), Vector3(sx * 0.25, 0.66, 0.04), 0.016, 0.016, "metal", dark)
		A.box(top, Vector3(0.06, 0.035, 0.26), Vector3(sx * 0.25, 0.68, 0.02), "rubber", Color.WHITE, false, 0.3)
	Merge.bake(base, 2.0, false, 60.0)
	Merge.bake(top, 2.0, false, 60.0)
	top.rotation.y = yaw
	base.rotation.y = yaw * 0.7


# --- sitting -----------------------------------------------------------------------------------------

func _sit_down() -> void:
	var p = who_now
	if p == null or taken or not p.has_method("sit"):
		return
	p.sit(self)


## Called by the player sitting down in it (here).
func taken_by(p) -> void:
	sitter = p
	taken = true
	_shape.disabled = true
	_vel = Vector3.ZERO
	Sfx.play(self, "creak", global_position + Vector3(0, 0.5, 0), -12.0, 1.4)
	_tell()


func let_go() -> void:
	sitter = null
	taken = false
	_shape.disabled = false
	Sfx.play(self, "creak", global_position + Vector3(0, 0.5, 0), -14.0, 1.6)
	_tell()


## Whoever's sat in it moved: it comes along under them, turning with them.
func follow(p: Node3D, delta: float) -> void:
	var was := global_position
	global_position = Vector3(p.global_position.x, global_position.y if absf(p.global_position.y - global_position.y) < 0.3 else p.global_position.y, p.global_position.z)
	top.global_rotation.y = p.global_rotation.y   # (facing the way you face: its back behind you)
	_roll(global_position - was, delta)
	_send -= delta
	if _send <= 0.0:
		_send = 0.1
		_tell()


func _physics_process(delta: float) -> void:
	if sitter != null or taken:
		return
	# Empty: walked into, it rolls off; then coasts to a stop (or a wall).
	var main = _main()
	var p = main.player if main else null
	if p != null and not p.dead and p.get("seat") == null:
		var d: Vector3 = global_position - p.global_position
		d.y = 0.0
		var inp := Input.get_vector("move_left", "move_right", "move_forward", "move_back") if not p.frozen else Vector2.ZERO
		var wish: Vector3 = p.global_basis * Vector3(inp.x, 0, inp.y)   # (where you're walking: up against it, you've stopped)
		wish.y = 0.0
		if d.length() < 0.85 and wish.length() > 0.3 and wish.normalized().dot(d.normalized()) > 0.4:
			_vel = wish.normalized() * 3.2 + d.normalized() * 0.4
			var off := Vector2(d.x, d.z).normalized().cross(Vector2(wish.x, wish.z).normalized())   # (off-centre: it spins)
			_spin = clampf(_spin + (off * 5.0 + randf_range(-1.5, 1.5)) * 0.25, -7.0, 7.0)
	if absf(_spin) > 0.02:
		top.rotation.y += _spin * delta
		base.rotation.y += _spin * 0.35 * delta
		_spin *= exp(-1.6 * delta)
		if _vel.length() <= 0.02:
			_send -= delta
			if _send <= 0.0:
				_send = 0.1
				_tell()
	if _vel.length() > 0.02:
		var step := _vel * delta
		var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 0.3, 0), global_position + Vector3(0, 0.3, 0) + step.normalized() * (step.length() + 0.32), 1)
		q.exclude = [get_rid()]
		if get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			global_position += step
			_roll(step, delta)
		else:
			_vel = -_vel * 0.25   # (a bump off the wall)
		_vel *= exp(-1.8 * delta)
		_send -= delta
		if _send <= 0.0:
			_send = 0.1
			_tell()


## Rolling: the base comes round after the way it's going (casters trailing), a creak now and then.
func _roll(step: Vector3, delta: float) -> void:
	var sp := Vector2(step.x, step.z).length() / maxf(delta, 0.001)
	if sp > 0.2:
		base.rotation.y = lerp_angle(base.rotation.y, atan2(step.x, step.z), minf(1.0, delta * 1.5))
		_creak -= delta * sp
		if _creak <= 0.0:
			_creak = randf_range(2.0, 5.0)
			Sfx.play(self, "creak", global_position + Vector3(0, 0.3, 0), -22.0, randf_range(1.6, 2.2))


func _tell() -> void:
	var main = _main()
	if main and main.net.active:
		main.net.act("chair", [net_key(), global_position, top.global_rotation.y, taken])


## From the crew: where it's got to.
func moved(at: Vector3, yaw: float, is_taken: bool) -> void:
	if sitter != null:
		return
	var step := at - global_position
	global_position = at
	top.global_rotation.y = yaw
	_roll(step, 0.1)
	taken = is_taken
	_shape.disabled = is_taken
	_vel = Vector3.ZERO


func _main():
	var net = get_tree().root.get_node_or_null("Net") if is_inside_tree() else null
	return net.main if net != null and is_instance_valid(net.main) else null
