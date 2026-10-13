# Boot prints in sand, snow and mud: one at every foot plant, left and right in turn, for you and
# for each crewmate (their puppets). A print is a decal of the boot's lugged sole, pressed darker into
# the ground (blue-grey hollows in snow, a dark wet stamp in mud, a soft dent in sand); it fades
# out over a minute and a half. Kept on the stop's level (gone with it), from a pool that reuses the
# oldest, so walking about never piles up nodes.
#   var prints := Footprints.new()   (one per walker)
#   prints.walk(walker_node, main, delta, horizontal_velocity)   every frame
extends RefCounted

const STRIDE := 0.72        # metres between foot plants
const LIFE := 90.0          # seconds before a print has faded out
const POOL := 180           # prints kept at once, everyone's together
const KINDS := {"sand": Color(0.3, 0.19, 0.11, 0.85), "snow": Color(0.36, 0.44, 0.62, 0.9), "mud": Color(0.04, 0.03, 0.015, 0.92)}

static var _tex: ImageTexture
static var _pool: Array = []   # [decal, born]
static var _next := 0

var _walked := 0.0
var _left := false


## Call every frame for a walker: `vel` is how it's moving, `floor` whether it's on the ground.
func walk(who: Node3D, main, delta: float, vel: Vector3, floor := true) -> void:
	var hs := Vector2(vel.x, vel.z).length()
	if not floor or hs < 0.4 or main.level == null:
		_walked = 0.0
		return
	_walked += hs * delta
	if _walked < STRIDE:
		return
	_walked -= STRIDE
	_left = not _left
	var kind: String = main.surface_at(who.global_position)
	var yaw := atan2(-vel.x, -vel.z)
	var side := Vector3(cos(yaw), 0, -sin(yaw)) * (0.11 if _left else -0.11)
	_kick(main.level, who.global_position + side, kind, hs)
	if not KINDS.has(kind):
		return
	_print(main.level, who.global_position + side, yaw, kind, _left)


# What a foot kicks up as it comes down: [colour, how many, speed up, gravity, size, life]
const KICK := {"sand": [Color(0.78, 0.62, 0.42, 0.6), 9, 0.7, -0.6, 0.14, 1.0], "snow": [Color(0.95, 0.97, 1.0, 0.75), 7, 0.9, -2.5, 0.05, 0.6],
	"water": [Color(0.7, 0.78, 0.85, 0.85), 12, 2.4, -9.0, 0.035, 0.45], "mud": [Color(0.18, 0.13, 0.08, 0.9), 6, 1.6, -9.0, 0.03, 0.4],
	"grass": [Color(0.55, 0.5, 0.35, 0.3), 3, 0.4, -0.5, 0.06, 0.7]}
static var _kickers := {}   # kind -> [emitters], used in turn


## A little of the ground kicked up at a foot plant: dust off sand (more running), a puff of powder
## off snow, a splash of droplets in water, flecks of mud.
static func _kick(level: Node3D, at: Vector3, kind: String, speed: float) -> void:
	if not KICK.has(kind) or level == null:
		return
	var k: Array = KICK[kind]
	var list: Array = _kickers.get(kind, []).filter(func(e): return is_instance_valid(e))
	var p: CPUParticles3D
	if list.size() < 6:
		p = CPUParticles3D.new()
		p.one_shot = true
		p.explosiveness = 0.9
		p.amount = k[1]
		p.lifetime = k[5]
		p.direction = Vector3.UP
		p.spread = 55.0
		p.initial_velocity_min = k[2] * 0.5
		p.initial_velocity_max = k[2]
		p.gravity = Vector3(0, k[3], 0)
		p.damping_min = 0.5
		p.damping_max = 1.5
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = 0.08
		var q := QuadMesh.new()
		q.size = Vector2.ONE * float(k[4])
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.billboard_keep_scale = true
		m.vertex_color_use_as_albedo = true
		var g := GradientTexture2D.new()   # (soft round)
		var gr := Gradient.new()
		gr.set_color(0, Color(1, 1, 1, 1))
		gr.set_color(1, Color(1, 1, 1, 0))
		g.gradient = gr
		g.fill = GradientTexture2D.FILL_RADIAL
		g.fill_from = Vector2(0.5, 0.5)
		g.fill_to = Vector2(1.0, 0.5)
		g.width = 16
		g.height = 16
		m.albedo_texture = g
		q.material = m
		p.mesh = q
		var c: Color = k[0]
		var ramp := Gradient.new()
		ramp.set_color(0, c)
		ramp.set_color(1, Color(c.r, c.g, c.b, 0.0))
		p.color_ramp = ramp
		var grow := Curve.new()
		grow.max_value = 3.0
		grow.add_point(Vector2(0, 1.0))
		grow.add_point(Vector2(1, 3.0 if kind in ["sand", "grass", "snow"] else 1.0))
		p.scale_amount_curve = grow
		list.append(p)
	else:
		p = list.pop_front()
		list.append(p)
	_kickers[kind] = list
	if p.get_parent() != level:
		if p.get_parent() != null:
			p.get_parent().remove_child(p)
		level.add_child(p)
	p.global_position = at + Vector3(0, 0.04, 0)
	p.speed_scale = clampf(0.7 + speed / 10.0, 0.7, 1.3)   # (running kicks it up harder)
	p.restart()
	p.emitting = true


static func _print(level: Node3D, at: Vector3, yaw: float, kind: String, left: bool) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var d: Decal
	if _pool.size() < POOL:
		d = Decal.new()
		d.texture_albedo = _sole()
		d.size = Vector3(0.15, 0.5, 0.33)
		d.normal_fade = 0.5
		d.upper_fade = 0.2
		d.lower_fade = 0.2
		d.cull_mask = 1   # (the ground, not the grass or anyone standing on it)
		_pool.append([d, now])
	else:
		_pool = _pool.filter(func(e): return is_instance_valid(e[0]))
		if _pool.size() < POOL:
			_print(level, at, yaw, kind, left)
			return
		_next = (_next + 1) % _pool.size()
		d = _pool[_next][0]
		_pool[_next][1] = now
	if d.get_parent() != level:
		if d.get_parent() != null:
			d.get_parent().remove_child(d)
		level.add_child(d)
	d.global_position = at + Vector3(0, 0.2, 0)
	d.rotation = Vector3(0, yaw, 0)
	d.scale = Vector3(-1.0 if left else 1.0, 1.0, 1.0)   # (a left boot is a right one mirrored)
	d.modulate = KINDS[kind]
	var tw := d.create_tween()
	tw.tween_interval(LIFE * 0.6)
	tw.tween_property(d, "modulate:a", 0.0, LIFE * 0.4)


## The print of the boot's sole: heel and forefoot, the arch narrow between, lugs across both,
## deepest (darkest) at the rims where the weight comes down.
static func _sole() -> ImageTexture:
	if _tex != null:
		return _tex
	var w := 48
	var h := 104
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var u := (x + 0.5) / w * 2.0 - 1.0   # -1..1 across
			var v := (y + 0.5) / h               # 0 toe .. 1 heel
			var half := 0.0   # the sole's half width along it
			if v < 0.58:
				half = 0.9 * sqrt(maxf(0.0, 1.0 - pow((v - 0.3) / 0.3, 2.0)))   # forefoot
			elif v < 0.7:
				half = 0.55   # the arch
			else:
				half = 0.78 * sqrt(maxf(0.0, 1.0 - pow((v - 0.85) / 0.15, 2.0)))   # heel
			var off := (u - 0.12 * (0.5 - v)) / maxf(half, 0.001)   # (a touch of curve, toe in)
			if absf(off) > 1.0 or half <= 0.0:
				continue
			var a := 0.7 + 0.3 * smoothstep(0.55, 1.0, absf(off))   # rim pressed deeper
			var lug := fmod(v * 22.0, 1.0)
			if v < 0.58 or v > 0.7:
				a *= 0.7 if lug < 0.35 else 1.0   # the lugs' grooves
			a *= smoothstep(1.0, 0.85, absf(off))   # soft edge
			img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
	img.generate_mipmaps()
	_tex = ImageTexture.create_from_image(img)
	return _tex
