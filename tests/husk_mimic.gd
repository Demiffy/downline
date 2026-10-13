# A husk copying your emotes (husk.saw_emote, main.emoted): it does what you did a beat later, two or
# three times; the next time it doesn't: it stares, then comes for you. With a shots dir, pictures of
# it at its dance. Run: tests/run.sh 150 --headless --path . -s tests/husk_mimic.gd [-- <shots dir>]
extends SceneTree

var main
var fails := 0


func _initialize() -> void:
	_run()


func check(ok: bool, what: String) -> void:
	print(("ok    " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func wait(secs: float) -> void:
	var a := Time.get_ticks_msec()
	while Time.get_ticks_msec() - a < secs * 1000.0:
		await physics_frame


func _run() -> void:
	Engine.set_meta("fast_test", true)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame
	main.rng.seed = 4242
	main.term.run("LEAVE_CHECKPOINT")
	main.term.run("ROUTE_TO " + main.route[0][0].letter)
	while main.busy:
		await process_frame
	var lvl = main.level
	for n in lvl.get_children():
		if n.is_in_group("monsters") or n.is_in_group("fauna"):
			n.free()
	var p = main.player
	p.frozen = true
	p.set_physics_process(false)
	p.hp = 100000.0
	var fac = lvl.facility
	var c: Vector2i = fac.layout.cells[0]
	for cc: Vector2i in fac.layout.cells:
		var kind: String = fac.kinds.get(cc, "")
		if cc != Vector2i.ZERO and not fac.layout.corridor.has(cc) and not fac.group_of.has(cc) and not kind in ["pit", "collapsed", "vault", "stairwell", "atrium", "tunnel", "machine"]:
			c = cc
			break
	var start: Vector3 = fac.to_global(Vector3(c.x * 12.0, 0.1, c.y * 12.0))
	p.global_position = start
	var h = load("res://src/husk.gd").new()
	h.main = main
	h.level = lvl
	lvl.add_child(h)
	h.global_position = _roomy_spot(start, 3.5)
	p.look_at(h.global_position, Vector3.UP)
	await wait(1.5)
	var shots: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else ""
	var eye: Camera3D
	if shots != "":
		DirAccess.make_dir_recursive_absolute(shots)
		main.hud.visible = false
		eye = Camera3D.new()
		eye.cull_mask = 0xFFFFF & ~(1 << 19) & ~2   # (not your own suit and hands: as your own eyes)
		main.add_child(eye)
		eye.current = true
		var lamp := OmniLight3D.new()
		lamp.omni_range = 12.0
		lamp.light_energy = 1.6
		eye.add_child(lamp)
	for k in 24:   # (somewhere it can see you from: rooms are furnished)
		if h.sees(p):
			break
		var dir := Vector3(1, 0, 0).rotated(Vector3.UP, TAU * k / 24.0)
		h.global_position = start + dir * (2.5 + (k % 3) * 0.8)
		h.velocity = Vector3.ZERO
		await wait(0.1)
	p.look_at(h.global_position * Vector3(1, 0, 1) + Vector3(0, p.global_position.y, 0), Vector3.UP)
	print("in sight: ", h.sees(p))
	var copies: int = h._mimics_left
	var moves := ["WAVE", "DANCE", "CHICKEN", "FLEX"]
	for k in copies:
		var m: String = moves[k % moves.size()]
		main.emoted(p, m)
		await wait(0.3)
		check(h._anim_e.emote != m, "%s: not at once (a beat late)" % m)
		var seen := false
		for i in 40:
			await wait(0.05)
			if h._anim_e.emote == m:
				seen = true
				break
		check(seen, "%s: the husk copies it" % m)
		if shots != "" and seen:
			await wait(0.8)
			eye.look_at_from_position(p.global_position + Vector3(0, 1.6, 0), h.global_position + Vector3(0, 1.0, 0))
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(shots + "/mimic_%d_%s.png" % [k, m.to_lower().replace(" ", "_")])
		await wait(2.5)
	main.emoted(p, "SALUTE")
	await wait(0.3)
	check(h._stare > 0.0 and h._anim_e.emote != "SALUTE", "the next one: not copied; it stares")
	await wait(3.0)
	check(h.state == h.STRIKE or h.state == h.SLINK, "...then comes for you (state %d)" % h.state)
	print("husk_mimic.gd: " + ("ALL PASSED" if fails == 0 else "%d FAILED" % fails))
	quit()


func _roomy_spot(from: Vector3, dist: float) -> Vector3:
	var space = main.player.get_world_3d().direct_space_state
	var best := Vector3(1, 0, 0)
	var room := 0.0
	for k in 16:
		var dir := Vector3(1, 0, 0).rotated(Vector3.UP, TAU * k / 16.0)
		var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(from + Vector3(0, 1.0, 0), from + Vector3(0, 1.0, 0) + dir * 30.0, 1 | 16))
		var free: float = from.distance_to(hit.position) if not hit.is_empty() else 30.0
		if free > room:
			room = free
			best = dir
	var c := from + best * dist
	var floor_hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(c + Vector3(0, 1.0, 0), c + Vector3(0, -0.5, 0), 1))
	return Vector3(c.x, floor_hit.position.y + 0.05, c.z) if not floor_hit.is_empty() else from + best * 2.0
