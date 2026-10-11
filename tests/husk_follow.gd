# A husk tagging along while you walk into it, stop, circle it and shuffle about: it should keep a
# crewmate's distance without twitching to and fro (direction reversals and turn-backs counted).
# Run: tests/run.sh 120 --headless --path . -s tests/husk_follow.gd [-- <seed> [<shots dir>]]
#   With a shots dir (and a window): a camera high behind the player, a frame every half second.
extends SceneTree

var main
var fails := 0


func check(cond: bool, what: String) -> void:
	print(("ok    " if cond else "FAIL  ") + what)
	if not cond:
		fails += 1


func _initialize() -> void:
	_run()


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
	# The biggest room: space to walk about in.
	var fac = lvl.facility
	var c: Vector2i = fac.layout.cells[0]
	var start: Vector3 = fac.to_global(Vector3(c.x * 12.0, 0.1, c.y * 12.0))
	p.global_position = start
	p.hp = 100000.0
	var h = load("res://src/husk.gd").new()
	h.main = main
	h.level = lvl
	lvl.add_child(h)
	h.global_position = _clear_spot(start, 4.0)   # (in plain sight: it only tags along with someone it's seen)
	for i in 30:
		await physics_frame
	var args := OS.get_cmdline_user_args()
	var trace := args.size() > 0
	if trace:
		seed(int(args[0]))
	var shots: String = args[1] if args.size() > 1 else ""
	var eye: Camera3D
	if shots != "":
		DirAccess.make_dir_recursive_absolute(shots)
		main.hud.visible = false
		eye = Camera3D.new()   # straight down from just under the ceiling, the room lit
		eye.projection = Camera3D.PROJECTION_ORTHOGONAL
		eye.size = 16.0
		main.add_child(eye)
		eye.current = true
		var lamp := OmniLight3D.new()
		lamp.omni_range = 30.0
		lamp.light_energy = 2.5
		eye.add_child(lamp)
	h.prey = p
	h.state = 1   # TAG_ALONG
	h._t = 0.0
	h._patience = 1.0e9
	h._pick_spot()
	var reversals := 0
	var turnbacks := 0
	var last_v := Vector3.ZERO
	var last_turn := 0.0
	var last_rot: float = h.rotation.y
	var closest := 99.0
	var farthest := 0.0
	var walked := 0.0
	var last_pos: Vector3 = h.global_position
	var frames := 0
	var t := 0.0
	while t < 24.0:
		var dt := 1.0 / 60.0
		t += dt
		# The player: walks into it, stands, circles round it, then shuffles back and forth near it.
		var to_h: Vector3 = (h.global_position - p.global_position) * Vector3(1, 0, 1)
		var step := Vector3.ZERO
		if t < 5.0:
			step = to_h.normalized() * 2.5
		elif t < 8.0:
			step = Vector3.ZERO
		elif t < 15.0:
			step = to_h.normalized().cross(Vector3.UP) * 3.0 + to_h.normalized() * (0.8 if to_h.length() > 2.5 else 0.0)
		else:
			step = to_h.normalized() * (2.0 if int(t * 1.5) % 2 == 0 else -2.0)
		p.velocity = step   # (walking: walls stop you)
		p.move_and_slide()
		await physics_frame
		frames += 1
		if t < 1.0:
			continue
		var v: Vector3 = h.velocity * Vector3(1, 0, 1)
		if v.length() > 0.3 and last_v.length() > 0.3 and v.normalized().dot(last_v.normalized()) < -0.2:
			reversals += 1
		if v.length() > 0.3:
			last_v = v
		var turn: float = wrapf(h.rotation.y - last_rot, -PI, PI)
		if absf(turn) > 0.01 and absf(last_turn) > 0.01 and signf(turn) != signf(last_turn):
			turnbacks += 1
		if absf(turn) > 0.01:
			last_turn = turn
		last_rot = h.rotation.y
		if eye != null:
			var mid: Vector3 = (p.global_position + h.global_position) * 0.5
			eye.global_position = Vector3(mid.x, start.y + 2.6, mid.z)
			eye.rotation = Vector3(-PI / 2, 0, 0)
			if frames % 30 == 0:
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("%s/f%03d.png" % [shots, frames / 30])
		if trace and frames % 30 == 0:
			print("t=%.1f d=%.2f moving=%s backing=%s dest_off=%.2f spot=%s v=%.2f" % [t, h.global_position.distance_to(p.global_position), h._moving, h._backing, h.global_position.distance_to(h._dest), str(h._spot.snapped(Vector3.ONE * 0.1)), h.velocity.length()])
		closest = minf(closest, h.global_position.distance_to(p.global_position))
		farthest = maxf(farthest, h.global_position.distance_to(p.global_position))
		walked += (h.global_position - last_pos).length()
		last_pos = h.global_position
	print("reversals %d  turn-backs %d  closest %.2f m  farthest %.2f m  walked %.1f m over %d frames" % [reversals, turnbacks, closest, farthest, walked, frames])
	check(reversals <= 6, "it doesn't dart to and fro (%d reversals in 23 s)" % reversals)
	check(turnbacks <= 30, "it doesn't twitch round and back (%d)" % turnbacks)
	check(farthest < 10.0 and walked > 3.0, "it comes along with you (walked %.1f m, never more than %.1f m off)" % [walked, farthest])
	check(closest > 0.9, "it keeps out of your way (closest %.2f m)" % closest)
	print("husk_follow.gd: ", "ALL PASSED" if fails == 0 else "%d FAILED" % fails)
	quit(1 if fails else 0)


## A spot `dist` from `from` on open floor, in plain sight of it.
func _clear_spot(from: Vector3, dist: float) -> Vector3:
	var space = main.player.get_world_3d().direct_space_state
	for k in 24:
		var c := from + Vector3(1, 0, 0).rotated(Vector3.UP, TAU * k / 24.0) * dist
		var sight := PhysicsRayQueryParameters3D.create(c + Vector3(0, 1.0, 0), from + Vector3(0, 1.0, 0), 1)
		var floor_hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(c + Vector3(0, 1.0, 0), c + Vector3(0, -0.5, 0), 1))
		if space.intersect_ray(sight).is_empty() and not floor_hit.is_empty() and floor_hit.position.y > from.y - 0.3:
			return Vector3(c.x, floor_hit.position.y + 0.05, c.z)
	return from + Vector3(dist, 0.2, 0)
