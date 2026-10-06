# A bot that actually plays: real input actions, real physics, real time. It grabs the flashlight,
# uses the terminal, rides the train, walks to the lift, explores the facility for scrap, rides back
# up and drops the loot on the train. Screenshots every few seconds and at every event; a log of
# what happened (stuck spots, hits, HUD messages). Needs a window.
# Run: godot --path . -s tests/playtest.gd -- <out_dir> [seconds_underground]
extends SceneTree

var main
var p        # player
var out := "user://playtest"
var log_lines := PackedStringArray()
var shot_n := 0
var t0 := 0
var underground_secs := 150.0
var _last_feed := ""
var _last_alert := ""
var _hp := 100000.0
var _stuck_shots := 0
var _dmg := 0.0


func _who_hit() -> String:
	var best := "?"
	var bd := 6.0
	for m in main.get_tree().get_nodes_in_group("monsters"):
		var d: float = m.global_position.distance_to(p.global_position)
		if d < bd:
			bd = d
			best = m.get_script().resource_path.get_file().get_basename()
	return best


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	if args.size() > 1:
		underground_secs = float(args[1])
	DirAccess.make_dir_recursive_absolute(out)
	_run()


# --- plumbing ------------------------------------------------------------------------------

func say(s: String) -> void:
	var line := "[%6.1fs %s] %s" % [(Time.get_ticks_msec() - t0) / 1000.0, _clock(), s]
	print(line)
	log_lines.append(line)
	var f := FileAccess.open(out + "/log.txt", FileAccess.WRITE)
	f.store_string("\n".join(log_lines))


func _clock() -> String:
	if main == null:
		return "--:--"
	return "%02d:%02d" % [int(main.hours), int(fmod(main.hours, 1.0) * 60)]


func shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	shot_n += 1
	var name := "%03d_%s" % [shot_n, tag]
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	say("shot " + name)


func tick() -> void:
	await physics_frame
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE   # never steal the user's mouse
	# Watch the HUD and the player's health.
	var feed: String = main.hud.feed_l.text
	if feed != _last_feed:
		var lines := feed.split("\n")
		say("HUD: " + lines[lines.size() - 1])
		_last_feed = feed
	var alert: String = main.hud.alert_l.text
	if alert != _last_alert and alert != "":
		say("ALERT: " + alert)
	_last_alert = alert
	if p.hp < _hp - 0.01:
		var hit: float = _hp - p.hp
		_dmg += hit
		if hit > 5.0:   # a real hit, not acid drizzle
			say("HURT for %.0f (%s)" % [hit, _who_hit()])
			await shot("hurt")
	p.hp = 100000.0   # god mode (survives instakills); every hit is logged instead
	_hp = p.hp
	if main.over:
		say("GAME OVER: " + main.hud.big_l.text.replace("\n", " / "))
		await shot("game_over")
		finish()


func wait(secs: float) -> void:
	var end := Time.get_ticks_msec() + int(secs * 1000)
	while Time.get_ticks_msec() < end:
		await tick()


## Tap a key. Pressed during an idle frame, like real input, so "just pressed" checks see it.
func press(action: String) -> void:
	await process_frame
	Input.action_press(action)
	await process_frame
	await process_frame
	Input.action_release(action)
	await tick()


func release_all() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right", "sprint", "jump", "interact", "crouch"]:
		Input.action_release(a)


## Turn the view toward a point at a human-ish speed. Returns true when on target.
func aim(target: Vector3, rate := 5.0) -> bool:
	var eye: Vector3 = p.cam.global_position
	var d := target - eye
	var yaw := atan2(-d.x, -d.z)
	var pitch := atan2(d.y, Vector2(d.x, d.z).length())
	var dt := 1.0 / 60.0
	var dy := wrapf(yaw - p.rotation.y, -PI, PI)
	p.rotation.y += clampf(dy, -rate * dt, rate * dt)
	p.head.rotation.x += clampf(pitch - p.head.rotation.x, -rate * dt, rate * dt)
	return absf(dy) < 0.05 and absf(pitch - p.head.rotation.x) < 0.05


func look_at_slowly(target: Vector3, secs := 1.5) -> void:
	var end := Time.get_ticks_msec() + int(secs * 1000)
	while Time.get_ticks_msec() < end:
		if aim(target, 3.0):
			break
		await tick()


func _ray_clear(dir: Vector3, dist: float, h := 0.9) -> bool:
	var from: Vector3 = p.global_position + Vector3(0, h, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * dist, 1)
	q.exclude = [p.get_rid()]
	return p.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## Walk to a point using the real move actions. Steers around things, jumps when stuck,
## logs and screenshots stuck spots. Returns true on arrival.
func walk(target: Vector3, tol := 0.8, timeout := 40.0, sprint := false) -> bool:
	var end := Time.get_ticks_msec() + int(timeout * 1000)
	var last_pos: Vector3 = p.global_position
	var last_check := Time.get_ticks_msec()
	var dodge := 0.0
	var dodge_dir := 1.0
	var stuck_count := 0
	while Time.get_ticks_msec() < end:
		var to: Vector3 = target - p.global_position
		to.y = 0.0
		if to.length() < tol:
			release_all()
			return true
		var want: Vector3 = to.normalized()
		# Avoid what's right ahead: pick the clearer side.
		if not _ray_clear(want, 1.2) or not _ray_clear(want, 1.2, 0.3):
			var l: Vector3 = want.rotated(Vector3.UP, 0.8)
			var r: Vector3 = want.rotated(Vector3.UP, -0.8)
			want = l if _ray_clear(l, 1.5) else (r if _ray_clear(r, 1.5) else want)
		if dodge > 0.0:
			dodge -= 1.0 / 60.0
			want = want.rotated(Vector3.UP, dodge_dir * 1.4)
		aim(p.global_position + Vector3(0, 1.6, 0) + want * 4.0, 7.0)
		Input.action_press("move_forward")
		if sprint and p.stamina > 1.0:
			Input.action_press("sprint")
		else:
			Input.action_release("sprint")
		await tick()
		if Time.get_ticks_msec() - last_check > 1200:
			var moved: float = p.global_position.distance_to(last_pos)
			if moved < 0.35:
				stuck_count += 1
				say("STUCK at %s heading for %s (try %d)" % [_v(p.global_position), _v(target), stuck_count])
				if _stuck_shots < 12:
					_stuck_shots += 1
					await shot("stuck")
				if stuck_count % 2 == 0:   # back off and come at it from the side
					Input.action_release("move_forward")
					Input.action_press("move_back")
					await wait(0.5)
					Input.action_release("move_back")
				await press("jump")
				dodge = 0.8
				dodge_dir = -dodge_dir
				if stuck_count == 3:
					var side: Vector3 = (target - p.global_position).normalized().cross(Vector3.UP) * (5.0 if randf() < 0.5 else -5.0)
					say("detouring sideways")
					await walk(p.global_position + side, 1.0, 6.0)
				if stuck_count >= 6:
					release_all()
					return false
			last_pos = p.global_position
			last_check = Time.get_ticks_msec()
	release_all()
	say("walk timed out heading for %s" % _v(target))
	return false


func _v(v: Vector3) -> String:
	return "(%.1f, %.1f, %.1f)" % [v.x, v.y, v.z]


## Look at something and press E on it, like a player would: stand still, settle the crosshair, press.
func use(node: Node3D, tag: String, hold := 0.0) -> bool:
	var target := node.global_position
	var steady := 0
	for i in 180:
		aim(target, 6.0)
		await tick()
		var on: bool = p.ray.is_colliding() and p.ray.get_collider() == node
		steady = steady + 1 if on and Vector2(p.velocity.x, p.velocity.z).length() < 0.15 else 0
		if steady >= 4:
			break
	if steady < 4:
		say("couldn't get the crosshair on " + tag)
		await shot("cant_aim_" + tag)
		return false
	if hold > 0.0:
		Input.action_press("interact")
		await wait(hold + 0.3)
		Input.action_release("interact")
	else:
		await press("interact")
	say("used " + tag)
	return true


func periodic() -> void:
	while true:
		await create_timer(3.0).timeout
		if main and not main.over:
			await shot("tick")


func finish() -> void:
	release_all()
	say("done: %d screenshots, %.0f total damage absorbed" % [shot_n, _dmg])
	quit()


# --- the run --------------------------------------------------------------------------------

func _run() -> void:
	t0 = Time.get_ticks_msec()
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 30:
		await process_frame
	p = main.player
	p.hp = 100000.0
	say("spawned on the train at " + _v(p.global_position))
	periodic()
	await shot("start")

	# 1. Grab the starter kit off the shelf.
	for n in main.get_tree().get_nodes_in_group("pickups"):
		if n.id == "FLASHLIGHT" or n.id == "SCANNER":
			await walk(n.global_position, 1.3, 15.0)
			await use(n, "pick up " + n.id)
			say("slots: " + str(p.slots.map(func(s): return s.id if s != null else "-")))
	for i in p.slots.size():
		if p.slots[i] != null and p.slots[i].id == "FLASHLIGHT":
			p._select(i)
		elif p.slots[i] != null and p.slots[i].id == "SCANNER":
			p.sel = i
			p._use()   # equip it (same as clicking with it held)
	for i in p.slots.size():
		if p.slots[i] != null and p.slots[i].id == "FLASHLIGHT":
			p._select(i)
	await shot("kit")

	# 2. Terminal: leave the checkpoint, route to the first station.
	var term_btn: Node3D = null
	for n in main.train.get_children():
		if n.has_method("interact") and n.prompt == "Use terminal":
			term_btn = n
	await walk(term_btn.global_position + Vector3(-1.2, 0, 0), 0.6, 15.0)
	await use(term_btn, "terminal")
	await wait(0.5)
	await shot("terminal_open")
	for cmd in ["LEAVE_CHECKPOINT", "MAP"]:
		main.term.run(cmd)
		await wait(1.5)
	await shot("terminal_map")
	var dest: String = main.route[0][0].letter
	main.term.run("VIEW_STATION " + dest)
	await wait(1.0)
	main.term.close()
	main.term.run("ROUTE_TO " + dest)
	say("routing to station " + dest)
	while main.busy:
		await tick()
	say("arrived: " + str(main.stop))
	await wait(1.0)
	await shot("arrived")

	# 3. Walk off the train to the lift.
	var lvl = main.level
	var el = lvl.elevator
	await look_at_slowly(el.global_position + Vector3(0, 8, 0), 2.0)
	await shot("view_of_headframe")
	var door: Vector3 = main.train.to_global(Vector3(2.6, 1.0, 1.6))   # out the side door
	await walk(door, 0.5, 10.0)
	await walk(door + Vector3(0, 0, 2.5), 0.6, 10.0)
	var front: Vector3 = el.global_position + Vector3(0, 0, -Elevator_SHAFT() - 2.5)
	for wp in lvl.trail:   # follow the signposts, like a player
		await walk(wp, 1.5, 40.0, true)
	if not await walk(front, 1.2, 90.0, true):
		say("never reached the lift on foot")
	await shot("at_lift")
	var call_btn = _find_interact(el, "Call")
	if not el.at_top or el.moving:
		await use(call_btn, "call button")
		while el.moving or not el.at_top:
			await tick()
	await walk(el.cab.global_position + Vector3(0, 0, -0.5), 0.6, 15.0)
	await walk(el.cab.global_position + Vector3(0.3, 0, 0.6), 0.5, 8.0)
	var ride_btn = _find_interact(el.cab, "Ride")
	await use(ride_btn, "ride button")
	await wait(2.0)
	await shot("riding_down")
	while el.moving:
		await tick()
	await shot("bottom")
	if p.global_position.y > -20.0:
		say("BOT: never made it down; ending the run")
		finish()
		return
	await walk(el.cab.global_position + Vector3(0, 0, -3.0), 0.6, 10.0)   # out through the doors first

	# 4. Explore below. Light on, find scrap room by room, fill the pockets.
	p.light_on = true
	var fac = lvl.facility
	var below_start := Time.get_ticks_msec()
	var carried := 0
	var visited := {}
	while (Time.get_ticks_msec() - below_start) / 1000.0 < underground_secs and carried < 3:
		var target = _nearest_scrap(fac)
		if target == null:
			say("no reachable scrap left")
			break
		var tid: String = target.id
		say("going for %s at %s" % [tid, _v(target.global_position)])
		if await _path_to(fac, target.global_position, 45.0) and is_instance_valid(target):
			await walk(target.global_position, 1.4, 8.0)
			if is_instance_valid(target) and await use(target, "pick up " + tid):
				carried += 1
				await shot("picked_" + tid)
			elif is_instance_valid(target):
				target.set_meta("bot_skip", true)
		elif is_instance_valid(target):
			target.set_meta("bot_skip", true)
		var c: Vector2i = fac.cell_at(p.global_position)
		if not visited.has(c):
			visited[c] = true
			say("entered room %s (%s)" % [c, fac.kinds.get(c, "?")])
			await look_around()
	# 5. Back to the lift and up.
	say("heading back to the lift with %d items" % carried)
	await _path_to(fac, el.cab.global_position + Vector3(0, 0, -3.0), 90.0)
	if el.at_top:
		await use(_find_interact(el, "Call", true), "call button (bottom)")
		while el.moving or el.at_top:
			await tick()
	await walk(el.cab.global_position + Vector3(0, 0, -0.5), 0.6, 15.0)
	await walk(el.cab.global_position + Vector3(0.3, 0, 0.6), 0.5, 8.0)
	await use(_find_interact(el.cab, "Ride"), "ride button (up)")
	while el.moving or not el.at_top:
		await tick()
	await shot("back_up")
	p.light_on = false

	# 6. Back to the train and unload.
	await walk(el.global_position + Vector3(0, 0, -Elevator_SHAFT() - 3.0), 1.0, 20.0)
	var back: Array = lvl.trail.duplicate()
	back.reverse()
	for wp in back:
		await walk(wp, 1.5, 40.0, true)
	var door2: Vector3 = main.train.to_global(Vector3(2.6, 1.0, 1.6))
	await walk(door2 + Vector3(0, 0, 2.5), 1.0, 90.0, true)
	await walk(door2, 0.5, 10.0)
	await walk(door2 + Vector3(0, 0, -1.2), 0.5, 10.0)
	for i in p.slots.size():
		if p.slots[i] != null and p.slots[i].id != "FLASHLIGHT":
			p._select(i)
			await press("drop")
			await wait(0.3)
	await shot("unloaded")
	say("scrap on the train: %d" % main._items_in(func(n): return main.train.contains(n.global_position)).size())
	finish()


func look_around() -> void:
	for a in [0.0, 1.6, 3.2, 4.8]:
		var target: Vector3 = p.global_position + Vector3(0, 1.4, 0) + Vector3(0, 0, -5).rotated(Vector3.UP, p.rotation.y + a)
		await look_at_slowly(target, 1.0)
	await shot("room")


func _path_to(fac, goal: Vector3, timeout: float) -> bool:
	var end := Time.get_ticks_msec() + int(timeout * 1000)
	while Time.get_ticks_msec() < end:
		if fac.cell_at(p.global_position) == fac.cell_at(goal):
			return await walk(goal, 1.2, 15.0)
		var wp: Vector3 = fac.path_next(p.global_position, goal)
		if not await walk(wp, 0.9, 20.0):
			say("couldn't reach doorway %s" % _v(wp))
			return false
		# step through the doorway so the next waypoint is the next door
		var through: Vector3 = wp + (wp - fac.to_global(Vector3(fac.cell_at(p.global_position).x * 12.0, 0, fac.cell_at(p.global_position).y * 12.0))).normalized() * 1.5
		await walk(through, 0.6, 4.0)
	return false


func _nearest_scrap(fac):
	var best = null
	var best_d := INF
	for n in main.get_tree().get_nodes_in_group("pickups"):
		if n.global_position.y > -20 or n.has_meta("bot_skip"):
			continue
		var a: Vector2i = fac.cell_at(p.global_position)
		var b: Vector2i = fac.cell_at(n.global_position)
		var d: float = absf(a.x - b.x) + absf(a.y - b.y) + p.global_position.distance_to(n.global_position) * 0.01
		if d < best_d:
			best_d = d
			best = n
	return best


func _find_interact(root_node: Node, word: String, lowest := false):
	var best = null
	for n in root_node.get_children():
		if n.has_method("interact") and word.to_lower() in String(n.prompt).to_lower():
			if best == null or (lowest and n.global_position.y < best.global_position.y) or (not lowest and n.global_position.y > best.global_position.y):
				best = n
	return best


func Elevator_SHAFT() -> float:
	return 2.15
