# Blood on the floor: splats where you're hit, and a trail of drips while you're badly hurt.
# Each one is a Decal (so it lies on whatever is below: grating, stairs, the train's boards),
# fresh and glossy red at first, drying dark over half a minute. They belong to whatever you
# were standing in (the station or the train), so they stay where they fell.
extends RefCounted

const MAX := 160   # oldest go first past this
static var _tex: Array[ImageTexture] = []
static var _all: Array = []


## A splat (or a drip, if small) on the floor under `pos`. `parent` keeps it.
static func spill(parent: Node3D, pos: Vector3, size: float) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 0.4, 0), pos + Vector3(0, -2.5, 0), 1)
	var hit := parent.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	if _tex.is_empty():
		for i in 6:
			_tex.append(_make(i))
	var d := Decal.new()
	d.texture_albedo = _tex[randi() % _tex.size()]
	d.size = Vector3(size, 0.25, size)
	d.upper_fade = 0.2
	d.lower_fade = 0.2
	d.modulate = Color(1.0, 0.9, 0.9)
	d.cull_mask = 0xFFFFF & ~2   # not on your own first-person hand
	parent.add_child(d)
	d.global_position = hit.position
	d.global_basis = Basis(Vector3.UP, randf() * TAU)
	var tw := d.create_tween()   # drying: duller and darker
	tw.tween_property(d, "modulate", Color(0.42, 0.3, 0.3), 30.0).set_ease(Tween.EASE_OUT)
	_all.append(d)
	while _all.size() > MAX:
		var old = _all.pop_front()
		if is_instance_valid(old):
			old.queue_free()


## A blood splat texture: an irregular pool with a ragged rim and flecks thrown off it.
static func _make(variant: int) -> ImageTexture:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = variant * 7349 + 11
	var noise := FastNoiseLite.new()
	noise.seed = variant
	noise.frequency = 0.09
	var blobs := [[Vector2(32, 32), rng.randf_range(10.0, 15.0)]]
	for i in rng.randi_range(5, 11):   # flecks and satellite drops
		var a := rng.randf() * TAU
		var r := rng.randf_range(15.0, 28.0)
		blobs.append([Vector2(32, 32) + Vector2(cos(a), sin(a)) * r, rng.randf_range(1.2, 3.5)])
	for y in n:
		for x in n:
			var p := Vector2(x, y)
			var v := 0.0
			for b in blobs:
				var r: float = b[1] * (1.0 + 0.35 * noise.get_noise_2d(x, y))
				v = maxf(v, 1.0 - p.distance_to(b[0]) / r)
			if v <= 0.0:
				continue
			var a := clampf(v * 5.0, 0.0, 1.0)
			var dark := 0.55 + 0.45 * clampf(v * 1.6, 0.0, 1.0)   # thicker in the middle
			img.set_pixel(x, y, Color(0.42 * dark, 0.03, 0.025, a * 0.95))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
