# Two real game processes over ENet on this machine: one hosts, one joins (tests/mp.sh runs both).
# Each checks what it can see from its side. Run: tests/mp.sh
#   godot --headless --path . -s tests/mp.gd -- host <port>
#   godot --headless --path . -s tests/mp.gd -- client <port>
extends SceneTree

var fails := 0
var main
var net
var role := "host"
var port := 24570


func check(cond: bool, what: String) -> void:
	print(("ok    " if cond else "FAIL  ") + "[%s] %s" % [role, what])
	if not cond:
		fails += 1


func wait_until(cond: Callable, secs := 10.0) -> bool:
	var end := Time.get_ticks_msec() + int(secs * 1000)
	while not cond.call() and Time.get_ticks_msec() < end:
		await process_frame
	return cond.call()


func secs(t: float) -> void:
	await create_timer(t).timeout


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	role = args[0] if args.size() > 0 else "host"
	port = int(args[1]) if args.size() > 1 else port
	_run()


func _run() -> void:
	Engine.set_meta("fast_test", true)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame
	net = main.net
	match role:
		"host": await _host()
		"client": await _client()
		"host_late": await _host_late()
		"late": await _late()
	print("mp.gd [%s]: %s" % [role, "ALL PASSED" if fails == 0 else "%d FAILED" % fails])
	net.leave()
	await secs(0.3)
	quit(1 if fails else 0)


# --- host --------------------------------------------------------------------------------------

func _host() -> void:
	check(net.host(port, "Hosty") == "", "hosting on port %d" % port)
	check(await wait_until(func(): return net.roster.size() == 2, 20.0), "the client joins the lobby (%d on the roster)" % net.roster.size())
	var cid: int = net.roster.keys().filter(func(k): return k != 1)[0]
	check(net.name_of(cid) == "CLIENTY", "...under their name (%s)" % net.name_of(cid))
	await secs(0.5)
	net.start()
	check(await wait_until(func(): return net.puppets.has(cid), 10.0), "their body shows up on the host (a puppet)")
	# The client types LEAVE_CHECKPOINT: the host runs it.
	check(await wait_until(func(): return main.departed, 15.0), "a crewmate's LEAVE_CHECKPOINT runs on the host")
	# ...then ROUTE_TO: everyone travels.
	check(await wait_until(func(): return not main.at_checkpoint and not main.busy, 40.0), "a crewmate's ROUTE_TO takes the train to a station")
	var pup = net.puppets[cid]
	check(await wait_until(func(): return pup.visible and pup.global_position.distance_to(main.level.elevator_pos) < 4.0, 20.0), "the client walks to the lift; the host sees them there")
	# Hurt them: their own player takes it.
	pup.hurt(10.0, "A test.")
	await secs(1.0)
	# Wait for the client's pickup + drop + hit + door + voice.
	await secs(12.0)   # (the client picks up, drops, fights, opens a door and talks meanwhile)
	check(net.voice.frames_from(cid) > 10, "the client's voice arrives (%d frames)" % net.voice.frames_from(cid))
	var dead_mobs: int = main.get_tree().get_nodes_in_group("corpses").size()
	check(dead_mobs >= 1, "the client's blow killed a creature on the host (%d corpses)" % dead_mobs)
	var doors_open: int = main.level.facility.get_children().filter(func(d): return d.has_method("set_open") and d.open).size()
	check(doors_open >= 1, "doors open (the client opened one)")
	# Kill them: remains on the host's side, cargo impounded.
	pup.hurt(500.0, "A worse test.")
	check(await wait_until(func(): return main.get_tree().get_nodes_in_group("pickups").any(func(p): return p.id == "REMAINS"), 12.0), "the client dies: their remains drop on the host")
	check(await wait_until(func(): return net.roster.size() == 1, 25.0), "the client leaves: the roster is just the host again")
	check(not net.puppets.has(cid) or not is_instance_valid(net.puppets.get(cid)), "...and their body is gone")


# --- client ------------------------------------------------------------------------------------

var _died := false

func _client() -> void:
	main.player.died.connect(func(_c): _died = true)
	await secs(1.0)
	check(net.join("127.0.0.1", port, "Clienty") == "", "connecting to 127.0.0.1:%d" % port)
	check(await wait_until(func(): return net.active and net.roster.size() == 2, 20.0), "in the lobby with the host")
	check(await wait_until(func(): return net.started, 20.0), "the host starts the shift")
	check(await wait_until(func(): return main.get_tree().get_nodes_in_group("pickups").size() >= 2, 10.0), "the host's starter kit is mirrored aboard (%d items)" % main.get_tree().get_nodes_in_group("pickups").size())
	main.term.run("LEAVE_CHECKPOINT")
	check(await wait_until(func(): return main.departed and not main.route.is_empty(), 10.0), "LEAVE_CHECKPOINT: the host's route arrives in the state")
	main.term.out.clear()
	main.term.run("ROUTE_TO " + main.route[0][0].letter)
	check(await wait_until(func(): return not main.at_checkpoint, 20.0), "ROUTE_TO: the train leaves for the station")
	check(await wait_until(func(): return not main.busy and main.level != null and not main.at_checkpoint, 40.0), "...and arrives")
	check(main.level.facility != null and main.level.facility.layout.cells.size() > 3, "the same site is built here (%d rooms)" % main.level.facility.layout.cells.size())
	check(await wait_until(func(): return main.get_tree().get_nodes_in_group("net_mobs").size() > 0, 10.0), "the host's creatures are mirrored (%d)" % main.get_tree().get_nodes_in_group("net_mobs").size())
	var items: Array = main.get_tree().get_nodes_in_group("pickups").filter(func(p): return main.level.is_ancestor_of(p))
	check(items.size() > 5, "the host's scrap is mirrored at the station (%d)" % items.size())
	# Walk (teleport) to the lift.
	main.player.global_position = main.level.elevator_pos + Vector3(0, 0.6, -3.0)
	main.player.velocity = Vector3.ZERO
	var hp0: float = main.player.hp
	check(await wait_until(func(): return main.player.hp < hp0, 15.0), "the host hurts our puppet: we lose %.0f HP" % (hp0 - main.player.hp))
	main.player.hp = 100.0
	# Pick something up.
	var target = items.filter(func(p): return Data_kind(p.id) == "scrap" and not p.get("heavy"))[0]
	main.player.global_position = target.global_position + Vector3(0.8, 0.2, 0)
	await secs(0.2)
	var slots0: int = main.player.slots.filter(func(it): return it != null).size()
	main.player._pick(target)
	check(await wait_until(func(): return main.player.slots.filter(func(it): return it != null).size() > slots0, 6.0), "picking up the host's item: it lands in our hands")
	check(await wait_until(func(): return not is_instance_valid(target) or target.is_queued_for_deletion(), 4.0), "...and it's gone from the floor")
	# Drop it again.
	main.player.sel = main.player.slots.find_custom(func(it): return it != null)
	await process_frame
	var live := func(): return main.get_tree().get_nodes_in_group("pickups").filter(func(p): return not p.is_queued_for_deletion()).size()
	var n0: int = live.call()
	main.player._drop()
	check(await wait_until(func(): return live.call() > n0, 6.0), "dropping it: the host spawns it, we see it")
	# Hit a creature hard enough to kill it (the host decides).
	var mobs: Array = main.get_tree().get_nodes_in_group("net_mobs").filter(func(m): return m.has_method("take_hit") and m.has_method("die") and not (m.get_script().resource_path.get_file() in ["statue.gd", "wraith.gd", "roomba.gd", "pulsator.gd"]))
	if not mobs.is_empty():
		main.hit_entity(mobs[0], 9999.0, mobs[0].global_position + Vector3(1, 1, 0))
		check(await wait_until(func(): return not is_instance_valid(mobs[0]) or mobs[0].dead, 6.0), "our blow kills a creature: it dies here too")
	# Open a door.
	var doors: Array = main.level.facility.get_children().filter(func(d): return d.has_method("set_open") and not d.open)
	if not doors.is_empty():
		doors[0].panel.interact(main.player)
		check(await wait_until(func(): return doors[0].open, 6.0), "opening a door goes through the host and opens here")
	# Talk.
	var tone := PackedFloat32Array()
	for i in 16000:
		tone.append(sin(TAU * 220.0 * i / 16000.0) * 0.3)
	for k in 5:
		net.voice.inject(tone.slice(k * 3200, (k + 1) * 3200))
		await process_frame
	await secs(4.0)
	# Die (the host's blow): back aboard after the card.
	check(await wait_until(func(): return _died, 30.0), "the host's hurt kills us")
	check(await wait_until(func(): return main.get_tree().get_nodes_in_group("pickups").any(func(p): return p.id == "REMAINS"), 10.0), "...our remains are mirrored where we fell")
	check(await wait_until(func(): return not main.player.dead, 15.0), "...and we wake aboard")
	await secs(1.0)


func Data_kind(id: String) -> String:
	return load("res://src/data.gd").kind(id)


# --- joining a shift under way ---------------------------------------------------------------

func _host_late() -> void:
	check(net.host(port, "Hosty") == "", "hosting")
	net.start()   # alone
	main.term.run("LEAVE_CHECKPOINT")
	main.term.run("ROUTE_TO " + main.route[0][0].letter)
	check(await wait_until(func(): return not main.at_checkpoint and not main.busy, 40.0), "the host travels to a station alone")
	main.set_meta("ready_for_late", true)
	print("HOST_AT_STATION")
	check(await wait_until(func(): return net.roster.size() == 2, 40.0), "a latecomer joins mid-shift")
	var cid: int = net.roster.keys().filter(func(k): return k != 1)[0]
	check(await wait_until(func(): return net.puppets.has(cid) and net.puppets[cid].visible, 15.0), "...and turns up at the station (their puppet is here)")
	check(await wait_until(func(): return net.roster.size() == 1, 30.0), "...and leaves")


func _late() -> void:
	await secs(14.0)   # (the host has left the checkpoint by now)
	check(net.join("127.0.0.1", port, "Latey") == "", "joining a shift under way")
	check(await wait_until(func(): return net.started and not main.at_checkpoint and main.level != null and main.level.facility != null, 30.0), "we're brought to the station the crew is at")
	check(main.train.on_board(main.player.global_position), "...standing aboard the train")
	check(await wait_until(func(): return main.get_tree().get_nodes_in_group("net_mobs").size() > 0 and main.get_tree().get_nodes_in_group("pickups").size() > 5, 10.0),
		"...with the station's creatures and scrap mirrored (%d / %d)" % [main.get_tree().get_nodes_in_group("net_mobs").size(), main.get_tree().get_nodes_in_group("pickups").size()])
	check(main.departed and not main.route.is_empty() and main.hours > 8.0, "...and the shift's state (route, clock %.2f)" % main.hours)
	await secs(3.0)

