# An explosion, as everyone sees it: a white flash, a fireball that rolls up and darkens into smoke,
# hot sparks and bits flung out on arcs, a dust ring racing out along the floor, a shockwave, and a
# scorch left on the ground. "flesh" (a pulsator bursting) throws wet red chunks and a pink mist
# instead of most of the fire. Everything is local (each machine makes its own copy) and cleans up
# after itself.
extends RefCounted

const B = preload("res://src/build.gd")

static var _puff: GradientTexture2D
static var _scorch: ImageTexture


static func at(parent: Node, pos: Vector3, radius: float, kind := "fire") -> void:
	var root := Node3D.new()
	root.name = "Blast"
	parent.add_child(root)
	root.global_position = pos
	var flesh := kind == "flesh"
	var floor_y := _floor(root, pos)
	var s := clampf(radius / 4.5, 0.6, 1.8)   # (bigger blasts, bigger everything)
	# The flash: very bright, very short, then the fire's own glow dying away.
	var l := B.omni(root, Vector3(0, 0.8, 0), Color(1.0, 0.75, 0.45) if not flesh else Color(1.0, 0.55, 0.45), 16.0 * s, 9.0 + radius * 1.6, true)
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 3.0 * s, 0.12)
	tw.tween_property(l, "light_energy", 0.0, 0.9).set_ease(Tween.EASE_OUT)
	# Fireball (or a burst of pink mist): puffs that swell, rise and burn out to soot.
	var fire := _particles(root, 26 if not flesh else 18, 0.85, 0.95)
	var fm := fire.process_material as ParticleProcessMaterial
	fm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	fm.emission_sphere_radius = 0.35 * s
	fm.direction = Vector3(0, 1, 0)
	fm.spread = 180.0
	fm.initial_velocity_min = 2.5 * s
	fm.initial_velocity_max = 6.5 * s
	fm.damping_min = 7.0
	fm.damping_max = 10.0
	fm.gravity = Vector3(0, 1.5, 0)
	fm.scale_min = 1.6 * s
	fm.scale_max = 2.8 * s
	fm.scale_curve = _curve([[0.0, 0.25], [0.25, 1.0], [1.0, 1.35]])
	fm.color_ramp = _ramp([[0.0, Color(1, 0.9, 0.6, 1)], [0.1, Color(1, 0.62, 0.18, 1)], [0.3, Color(0.92, 0.3, 0.06, 0.95)], [0.55, Color(0.3, 0.12, 0.06, 0.8)], [1.0, Color(0.06, 0.05, 0.05, 0.0)]]) if not flesh \
		else _ramp([[0.0, Color(1, 0.85, 0.85, 1)], [0.2, Color(0.95, 0.45, 0.45, 0.85)], [0.6, Color(0.6, 0.15, 0.18, 0.5)], [1.0, Color(0.3, 0.05, 0.08, 0.0)]])
	fire.position.y = 0.6
	_puff_material(fire, true)
	# Smoke: big, slow, rolling up and spreading, lingering a few seconds.
	var smoke := _particles(root, 28, 4.5, 0.55)
	var sm := smoke.process_material as ParticleProcessMaterial
	sm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	sm.emission_sphere_radius = 0.6 * s
	sm.direction = Vector3(0, 1, 0)
	sm.spread = 70.0
	sm.initial_velocity_min = 1.0
	sm.initial_velocity_max = 2.6 * s
	sm.damping_min = 1.5
	sm.damping_max = 2.5
	sm.gravity = Vector3(0, 0.8, 0)
	sm.scale_min = 2.2 * s
	sm.scale_max = 3.6 * s
	sm.scale_curve = _curve([[0.0, 0.4], [1.0, 1.8]])
	var smoke_c := Color(0.16, 0.15, 0.14) if not flesh else Color(0.45, 0.3, 0.3)
	sm.color_ramp = _ramp([[0.0, Color(smoke_c, 0.0)], [0.1, Color(smoke_c, 0.9)], [0.55, Color(smoke_c.lightened(0.1), 0.7)], [1.0, Color(smoke_c.lightened(0.2), 0.0)]])
	smoke.position.y = 0.8
	_puff_material(smoke, false)
	smoke.preprocess = 0.0
	# Sparks and bits: flung out on arcs, the sparks glowing, the bits dark (or wet red chunks).
	var bits := _particles(root, 46 if not flesh else 30, 1.4, 1.0)
	var bm := bits.process_material as ParticleProcessMaterial
	bm.direction = Vector3(0, 1, 0)
	bm.spread = 75.0
	bm.initial_velocity_min = 4.0 * s
	bm.initial_velocity_max = 11.0 * s
	bm.gravity = Vector3(0, -14, 0)
	bm.scale_min = 0.5
	bm.scale_max = 1.6
	bm.angular_velocity_min = -500.0
	bm.angular_velocity_max = 500.0
	bm.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
	bm.collision_bounce = 0.3
	bm.collision_friction = 0.6
	bits.collision_base_size = 0.03
	var cube := BoxMesh.new()
	cube.size = Vector3(0.05, 0.05, 0.09) if not flesh else Vector3(0.08, 0.06, 0.07)
	var bmat := StandardMaterial3D.new()
	bmat.vertex_color_use_as_albedo = true
	if flesh:
		bmat.albedo_color = Color(0.55, 0.08, 0.1)
		bmat.roughness = 0.2
		bm.color = Color(1, 1, 1)
	else:
		bmat.emission_enabled = true
		bmat.emission = Color(1.0, 0.55, 0.15)
		bmat.emission_energy_multiplier = 5.0
		bm.color_ramp = _ramp([[0.0, Color(1, 0.9, 0.6, 1)], [0.5, Color(1, 0.45, 0.1, 1)], [1.0, Color(0.2, 0.1, 0.05, 1)]])
	cube.material = bmat
	bits.draw_pass_1 = cube
	bits.position.y = 0.5
	# Dust thrown out along the floor in a ring.
	var dust := _particles(root, 30, 1.6, 1.0)
	var dm := dust.process_material as ParticleProcessMaterial
	dm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	dm.emission_ring_axis = Vector3.UP
	dm.emission_ring_radius = 0.4
	dm.emission_ring_inner_radius = 0.2
	dm.emission_ring_height = 0.05
	dm.direction = Vector3(1, 0.05, 0)
	dm.spread = 180.0
	dm.flatness = 0.9
	dm.initial_velocity_min = 5.0 * s
	dm.initial_velocity_max = 8.0 * s
	dm.damping_min = 6.0
	dm.damping_max = 9.0
	dm.gravity = Vector3(0, 0.2, 0)
	dm.scale_min = 0.9 * s
	dm.scale_max = 1.6 * s
	dm.scale_curve = _curve([[0.0, 0.5], [1.0, 1.6]])
	var dust_c := Color(0.55, 0.48, 0.4)
	dm.color_ramp = _ramp([[0.0, Color(dust_c, 0.0)], [0.1, Color(dust_c, 0.55)], [1.0, Color(dust_c, 0.0)]])
	dust.global_position = Vector3(pos.x, floor_y + 0.15, pos.z)
	_puff_material(dust, false)
	# The shockwave: a pale ring snapping out across the floor.
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.92
	tm.outer_radius = 1.0
	tm.rings = 32
	ring.mesh = tm
	var rmat := StandardMaterial3D.new()
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rmat.albedo_color = Color(1.0, 0.85, 0.65, 0.5) if not flesh else Color(1.0, 0.6, 0.6, 0.45)
	ring.material_override = rmat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ring)
	ring.global_position = Vector3(pos.x, floor_y + 0.08, pos.z)
	ring.scale = Vector3(0.2, 0.05, 0.2)
	var rt := ring.create_tween().set_parallel()
	rt.tween_property(ring, "scale", Vector3(radius * 1.3, 0.05, radius * 1.3), 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	rt.tween_property(rmat, "albedo_color:a", 0.0, 0.35)
	# A scorch (or a wet stain) left on the ground.
	var d := Decal.new()
	d.texture_albedo = _scorch_tex()
	d.size = Vector3(radius * 0.9, 1.2, radius * 0.9)
	d.modulate = Color(0.1, 0.08, 0.07, 0.85) if not flesh else Color(0.35, 0.04, 0.06, 0.8)
	d.cull_mask = 0xFFFFF & ~2
	parent.add_child(d)
	d.global_position = Vector3(pos.x, floor_y + 0.3, pos.z)
	d.rotation.y = randf() * TAU
	var dt := d.create_tween()
	dt.tween_interval(60.0)
	dt.tween_property(d, "modulate:a", 0.0, 4.0)
	dt.tween_callback(d.queue_free)
	for p in [fire, smoke, bits, dust]:
		p.emitting = true
	var gone := root.create_tween()
	gone.tween_interval(5.5)
	gone.tween_callback(root.queue_free)


static func _floor(n: Node3D, pos: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 0.5, 0), pos + Vector3(0, -4.0, 0), 1)
	var hit := n.get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position.y if not hit.is_empty() else pos.y


static func _particles(root: Node3D, amount: int, life: float, explosive: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = explosive
	p.emitting = false
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-12, -4, -12), Vector3(24, 16, 24))
	p.process_material = ParticleProcessMaterial.new()
	root.add_child(p)
	return p


## Soft round puffs that face the camera; `glow` ones light themselves (fire), the rest are lit.
static func _puff_material(p: GPUParticles3D, glow: bool) -> void:
	if _puff == null:
		_puff = GradientTexture2D.new()
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.add_point(0.55, Color(1, 1, 1, 0.6))
		g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
		_puff.gradient = g
		_puff.fill = GradientTexture2D.FILL_RADIAL
		_puff.fill_from = Vector2(0.5, 0.5)
		_puff.fill_to = Vector2(1.0, 0.5)
		_puff.width = 64
		_puff.height = 64
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var m := StandardMaterial3D.new()
	m.albedo_texture = _puff
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if glow else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	if glow:   # (unshaded, alpha-blended: a saturated orange that doesn't white out)
		m.albedo_color = Color(1.4, 1.2, 1.0)
	q.material = m
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func _ramp(points: Array) -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(points.map(func(e): return e[0]))
	g.colors = PackedColorArray(points.map(func(e): return e[1]))
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


static func _curve(points: Array) -> CurveTexture:
	var c := Curve.new()
	for e in points:
		c.add_point(Vector2(e[0], e[1]))
	var t := CurveTexture.new()
	t.curve = c
	return t


## A ragged dark blotch, darkest in the middle, with a few streaks out from it.
static func _scorch_tex() -> ImageTexture:
	if _scorch == null:
		var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
		var rng := RandomNumberGenerator.new()
		rng.seed = 77
		var streaks := []
		for k in 9:
			streaks.append([rng.randf() * TAU, rng.randf_range(0.55, 0.95)])
		for y in 128:
			for x in 128:
				var v := Vector2(x - 63.5, y - 63.5) / 63.5
				var r := v.length()
				var a := clampf(1.0 - r * 1.6, 0.0, 1.0)
				for st in streaks:
					var ang := absf(angle_difference(v.angle(), st[0]))
					if r < st[1]:
						a = maxf(a, clampf(1.0 - ang * 9.0, 0.0, 1.0) * (1.0 - r / st[1]) * 0.8)
				a *= 0.75 + 0.25 * rng.randf()
				img.set_pixel(x, y, Color(1, 1, 1, a))
		_scorch = ImageTexture.create_from_image(img)
	return _scorch
