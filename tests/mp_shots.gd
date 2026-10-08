# What a crewmate looks like from the other side: two windowed game processes, the host acts, the
# client takes screenshots (tests/mp_shots.sh runs both). Checks by eye: the crewmate's body, what
# it holds and how (lit lamp, shotgun two-handed, axe), its swing and its shot, walking, crouching,
# the name tag lighting up as it talks, the crew panel, its blood on our floor; then at a station,
# every kind of creature as the client's copy of it, and their one-off moves (the warden's swing,
# the observer's flash, the snatcher's maw, the trap's jaws), the wraith frosting our visor.
#   godot --path . -s tests/mp_shots.gd -- host <port> <out>
#   godot --path . -s tests/mp_shots.gd -- client <port> <out>
extends SceneTree

const Level = preload("res://src/level.gd")

var main
var net
var role := "host"
var port := 24580
var out := "/tmp/mp_shots"
var step_path := ""
var ack_path := ""
var _keep_alive := true
var quick := false   # just the crewmate aboard (no station, no creatures)


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	role = a[0]
	port = int(a[1])
	out = a[2]
	quick = a.size() > 3 and a[3] == "quick"
	DirAccess.make_dir_recursive_absolute(out)
	step_path = OS.get_user_data_dir() + "/mps_step_%d.txt" % port
	ack_path = OS.get_user_data_dir() + "/mps_ack_%d.txt" % port
	_run()


func frames(n: int) -> void:
	for i in n:
		await process_frame


func secs(t: float) -> void:
	await create_timer(t).timeout


func wait_until(cond: Callable, t := 10.0) -> bool:
	var end := Time.get_ticks_msec() + int(t * 1000)
	while not cond.call() and Time.get_ticks_msec() < end:
		await process_frame
	return cond.call()


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("saved ", name)


## Stand at `pos` (eyes) looking at `at`.
func look(pos: Vector3, at: Vector3) -> void:
	var p = main.player
	p.global_position = pos - Vector3(0, 1.6, 0)
	p.velocity = Vector3.ZERO
	var d := at - pos
	p.rotation.y = atan2(-d.x, -d.z)
	p.head.rotation.x = clampf(atan2(d.y, Vector2(d.x, d.z).length()), -1.4, 1.4)


func _immortal() -> void:   # nobody dies while we're filming
	while _keep_alive:
		if main and main.player:
			main.player.hp = maxf(main.player.hp, 100.0)
			main.player.trapped = null
			main.player.blind = 0.0
		await process_frame


func _run() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await frames(10)
	net = main.net
	for n in root.get_children():   # (no title screen)
		if n.get_script() and String(n.get_script().resource_path).ends_with("lobby.gd"):
			n.queue_free()
	_immortal()
	if role == "host":
		await _host()
	else:
		await _client()
	_keep_alive = false
	net.leave()
	await secs(0.3)
	quit()


# --- the step protocol: the host says what it's doing, the client says when it has the picture ---

func say_step(s: String, args := {}) -> void:
	args.step = s
	FileAccess.open(step_path, FileAccess.WRITE).store_string(JSON.stringify(args))
	print("STEP ", s)
	var ok := await wait_until(func(): return FileAccess.file_exists(ack_path) and FileAccess.get_file_as_string(ack_path) == s, 40.0)
	if not ok:
		print("no ack for ", s)


## Say the step, give the client a moment to frame it, then do the thing (so it's caught happening).
func say_then(s: String, args: Dictionary, what: Callable) -> void:
	args.step = s
	FileAccess.open(step_path, FileAccess.WRITE).store_string(JSON.stringify(args))
	print("STEP ", s)
	await secs(2.5)
	what.call()
	await wait_until(func(): return FileAccess.file_exists(ack_path) and FileAccess.get_file_as_string(ack_path) == s, 40.0)


var _last_step := ""

func next_step() -> Dictionary:
	await wait_until(func():
		if not FileAccess.file_exists(step_path):
			return false
		var d = JSON.parse_string(FileAccess.get_file_as_string(step_path))
		return d != null and d.step != _last_step, 120.0)
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(step_path))
	_last_step = d.step
	return d


func ack() -> void:
	FileAccess.open(ack_path, FileAccess.WRITE).store_string(_last_step)


# --- host --------------------------------------------------------------------------------------

func hold(id: String, charge := 1.0) -> void:
	var p = main.player
	for i in p.slots.size():
		p.slots[i] = null
	p.sel = 0
	p.take({"id": id, "charge": charge})
	p.sel = 0
	p.light_on = id in ["FLASHLIGHT", "LANTERN"]


func _host() -> void:
	DirAccess.remove_absolute(step_path)
	DirAccess.remove_absolute(ack_path)
	net.host(port, "Hosty")
	await wait_until(func(): return net.roster.size() == 2, 60.0)
	await secs(1.0)
	net.start()
	await wait_until(func(): return not net.puppets.is_empty(), 20.0)
	var p = main.player
	var t = main.train
	await secs(1.0)
	# Aboard: the host by the far wall, facing the client.
	var at := func(x: float, z := 0.0) -> Vector3: return t.to_global(Vector3(x, 1.3, z))
	p.global_position = at.call(-1.0)
	p.rotation.y = t.global_rotation.y + PI / 2.0   # facing -x along the car (toward the client)
	p.head.rotation.x = 0.0
	hold("FLASHLIGHT")
	await secs(0.6)
	await say_step("flashlight")
	hold("LANTERN")
	await secs(0.6)
	await say_step("lantern")
	hold("SHOTGUN", 4.0)
	await secs(0.6)
	await say_step("shotgun")
	main.player._attack(main.player.slots[0])
	await say_step("shotgun_fire")
	hold("FIRE_AXE")
	await secs(0.6)
	await say_step("axe")
	p._attack_cd = 0.0
	main.player._attack(main.player.slots[0])
	await say_step("axe_swing")
	hold("CROWBAR")
	await secs(0.6)
	p._attack_cd = 0.0
	main.player._attack(main.player.slots[0])
	await say_step("crowbar_swing")
	hold("COPPER_PIPE")
	await secs(0.6)
	await say_step("holding_scrap")
	# Walking toward the client, then crouched.
	p.global_position = at.call(1.5)
	Input.action_press("move_forward")
	await secs(0.5)
	await say_step("walking")
	Input.action_press("crouch")
	await secs(0.6)
	await say_step("crouch_walk")
	Input.action_release("move_forward")
	await secs(0.5)
	await say_step("crouched")
	Input.action_release("crouch")
	p.global_position = at.call(-1.0)
	await secs(0.6)
	# Talking.
	var tone := PackedFloat32Array()
	for i in 3200:
		tone.append(sin(TAU * 200.0 * i / 16000.0) * 0.3)
	var talking := true
	var talk := func():
		while talking:
			net.voice.inject(tone)
			await secs(0.2)
	talk.call()
	await secs(0.5)
	await say_step("talking")
	talking = false
	# Bleeding.
	for i in 3:
		p.bleed(0.7, 0.4)
	for i in 6:
		p.global_position = at.call(-1.0 - i * 0.35)
		p.bleed(0.18, 0.1)
	await secs(0.5)
	await say_step("blood", {"at": [p.global_position.x, p.global_position.y, p.global_position.z]})
	if quick:
		await say_step("done")
		return
	# To a station.
	main.term.run("LEAVE_CHECKPOINT")
	var st: Dictionary = main.route[0][0]
	st.theme = "FACTORY"
	st.weather = "CLEAR"
	Engine.set_meta("fast_test", true)
	p.global_position = at.call(0.0)
	main.term.run("ROUTE_TO " + st.letter)
	await wait_until(func(): return not main.busy and not main.at_checkpoint, 60.0)
	await secs(2.0)
	var lvl = main.level
	var fac = lvl.facility
	lvl.hazards.events.clear()
	# One of every creature, in its own room, held still (we're filming, not fighting).
	var kinds := ["warden", "observer", "wraith", "mimic", "statue", "marionette", "pulsator", "roomba", "scrapper", "gloe", "bear_trap", "snatcher"]
	var mobs := {}
	for m in lvl.get_children():
		if m.get_script() != null and m.has_meta("net_id"):
			var k: String = m.get_script().resource_path.get_file().get_basename()
			if k in kinds:
				m.queue_free()
	await frames(5)
	var placed := []
	for k in kinds:
		var o: Vector3 = fac.random_point(lvl.rng, true)
		for tries in 80:   # each in a spot of its own, well apart from the rest
			if placed.all(func(q): return q.distance_to(o) > 8.0):
				break
			o = fac.random_point(lvl.rng, true)
		placed.append(o)
		var pos := o
		if k == "snatcher":
			pos = Vector3(o.x, o.y + 3.95, o.z)   # (up in the ceiling)
		elif k == "gloe":
			pos = o + Vector3(0, 1.5, 0)
		lvl._spawn(load("res://src/%s.gd" % k), pos)
		var m = lvl.get_children()[-1]
		mobs[k] = m
	await frames(5)
	for k in mobs:
		var m = mobs[k]
		m.set_physics_process(false)
		if k == "gloe":
			m.set_process(false)
	p.global_position = main.train.to_global(Vector3(0, 1.3, 0))   # (out of their way)
	await secs(2.0)
	for k in mobs:
		var m = mobs[k]
		await say_step("mob_" + k, {"id": m.get_meta("net_id"), "host_at": [m.global_position.x, m.global_position.y, m.global_position.z]})
	# Their moves.
	var w = mobs.warden
	w.state = w.HUNT
	await say_step("warden_hunt", {"id": w.get_meta("net_id")})
	await say_then("warden_swing", {"id": w.get_meta("net_id")}, func(): w.show_act("swing", [0]))
	var ob = mobs.observer
	ob.state = ob.CHARGE
	ob._charge = 1.0
	await say_step("observer_charge", {"id": ob.get_meta("net_id")})
	await say_then("observer_flash", {"id": ob.get_meta("net_id")}, func():
		main.net.ent_event(ob, "act", ["flash", []])
		ob.act("flash", []))
	ob.state = ob.FOLLOW
	var sn = mobs.snatcher
	await say_then("snatcher_maw", {"id": sn.get_meta("net_id")}, func(): main.net.ent_event(sn, "snatch", []))
	var bt = mobs.bear_trap
	await say_then("trap_shut", {"id": bt.get_meta("net_id")}, func():
		bt._jaws_to(true)
		bt.sprung = true)
	var mi = mobs.mimic
	mi._bite_start()
	await say_step("mimic_bite", {"id": mi.get_meta("net_id")})
	var sc = mobs.scrapper
	sc.fleeing = 30.0
	await say_step("scrapper_flee", {"id": sc.get_meta("net_id")})
	var wr = mobs.wraith
	wr.state = wr.STALK
	await say_step("wraith_close", {"id": wr.get_meta("net_id")})
	var stt = mobs.statue
	await say_then("statue_pose", {"id": stt.get_meta("net_id")}, func(): stt.show_act("pose", [2, Vector3(-0.3, 0.4, 0.1)]))
	await say_step("done")


# --- client ------------------------------------------------------------------------------------

## A spot beside the crewmate (along the car, across it), at eye height.
func near(h, along: float, across: float) -> Vector3:
	return h.global_position + main.train.global_basis * Vector3(along, 0, across) + Vector3(0, 1.6, 0)


func pup():
	return net.puppets.values()[0] if not net.puppets.is_empty() else null


func _client() -> void:
	await secs(2.0)
	Engine.set_meta("fast_test", true)   # (the host's pace)
	net.join("127.0.0.1", port, "Clienty")
	await wait_until(func(): return net.started, 60.0)
	await wait_until(func(): return pup() != null and pup().visible, 20.0)
	var p = main.player
	p.slots[0] = {"id": "LANTERN", "charge": 300.0, "extra": {}}
	p.sel = 0
	p.light_on = true
	while true:
		var d := await next_step()
		var s: String = d.step
		if s == "done":
			ack()
			break
		var t = main.train
		var h = pup()
		match s:
			"flashlight", "lantern", "shotgun", "axe", "holding_scrap", "talking":
				look(near(h, -2.6, 0.55), h.global_position + Vector3(0, 1.1, 0))
				await secs(0.4)
				await shot(s)
				if s == "shotgun":
					look(near(h, -1.3, 1.1), h.global_position + Vector3(0, 1.15, 0))
					await secs(0.3)
					await shot("shotgun_side")
			"shotgun_fire":
				look(near(h, -1.3, 1.1), h.global_position + Vector3(0, 1.15, 0))
				await wait_until(func(): return h._recoil > 0.6, 5.0)
				await shot(s)
			"axe_swing", "crowbar_swing":
				look(near(h, -1.3, 1.1), h.global_position + Vector3(0, 1.15, 0))
				await wait_until(func(): return h._swing >= 0.0, 5.0)
				await wait_until(func(): return h._swing > h._swing_len * 0.45, 5.0)
				await shot(s + "_windup")
				await wait_until(func(): return h._swing > h._swing_len * 0.68, 5.0)
				await shot(s + "_strike")
			"walking", "crouch_walk", "crouched":
				look(near(h, -2.8, 0.5), h.global_position + Vector3(0, 0.9, 0))
				await secs(0.15)
				await shot(s)
			"blood":
				var at := Vector3(d.at[0], d.at[1], d.at[2])
				look(at + Vector3(0, 1.65, 0) + t.global_basis.z * 1.6 - t.global_basis.x * 0.8, at + t.global_basis.x * 0.9)
				await secs(0.3)
				await shot(s)
			"done":
				pass
			_:
				if d.has("id"):
					_cur = d
					await _film(s, int(d.id))
		ack()
	print("mp_shots client: done")


var _cur := {}

## Close on a creature: a few metres off in whichever direction is clear, looking at it.
func _film(s: String, nid: int) -> void:
	await wait_until(func(): return not main.busy, 60.0)   # (arrived: the station has stopped sliding past)
	await wait_until(func(): return net.ents.has(nid) and is_instance_valid(net.ents[nid]), 10.0)
	var m = net.ents.get(nid)
	if m == null:
		print("no mirror for ", s)
		return
	var k: String = m.get_script().resource_path.get_file().get_basename()
	if _cur.has("host_at"):
		var ha := Vector3(_cur.host_at[0], _cur.host_at[1], _cur.host_at[2])
		print("FILM %s mirror %s host %s off %.2f" % [k, m.global_position, ha, ha.distance_to(m.global_position)])
	var floor_y: float = m.global_position.y
	var height := 1.0
	match k:
		"snatcher":
			floor_y = m.global_position.y - 3.95
			height = 3.0
		"gloe":
			floor_y = m.global_position.y - 1.5
			height = 1.5
		"roomba", "bear_trap", "scrapper":
			height = 0.2
		"warden", "observer":
			height = 1.6
		"wraith", "statue", "marionette":
			height = 1.2
	var target := Vector3(m.global_position.x, floor_y + height, m.global_position.z)
	var dist := 2.2 if height < 0.5 else (3.6 if k in ["warden", "observer", "snatcher"] else 2.8)
	var best := Vector3.INF
	for i in 8:
		var dir := Vector3.FORWARD.rotated(Vector3.UP, i * TAU / 8.0)
		var eye := Vector3(target.x, floor_y + 1.6, target.z) + dir * dist
		var q := PhysicsRayQueryParameters3D.create(target, eye, 1)
		if main.player.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			best = eye
			break
	if best == Vector3.INF:
		best = Vector3(target.x, floor_y + 1.6, target.z) + Vector3(0, 0, dist)
	look(best, target)
	match s:
		"warden_swing":
			await wait_until(func(): return m._arms[0].rotation.x < -1.2, 6.0)
		"observer_flash":
			await wait_until(func(): return m._flash.light_energy > 20.0, 6.0)
		"snatcher_maw":
			await wait_until(func(): return m._maw.visible and m._maw.position.y < -1.5, 6.0)
		"trap_shut":
			await wait_until(func(): return m.shut, 6.0)
			await secs(0.3)
		"statue_pose":
			await wait_until(func(): return absf(m._head.rotation.y - 0.4) < 0.01, 6.0)
		"mimic_bite", "scrapper_flee", "warden_hunt", "observer_charge":
			await secs(0.5)
		"wraith_close":
			look(Vector3(target.x, floor_y + 1.6, target.z) + (best - Vector3(target.x, floor_y + 1.6, target.z)).normalized() * 1.6, target)
			await secs(1.2)
		_:
			await secs(0.6)
	await shot(s)
