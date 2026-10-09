# Save and continue with a crew. Two rounds (tests/mp_save.sh runs both):
#   round 1: host + client play to a station; the client has a crowbar; the host saves.
#   round 2: the host continues that run; the client joins and is back at that station with its
#            crowbar, the run's photos, and what was left lying there.
extends SceneTree

const PATH := "user://test_mp_run.save"
const Save = preload("res://src/save.gd")

var fails := 0
var main
var net
var role := "host"
var port := 24570
var round := 1


func check(cond: bool, what: String) -> void:
	print(("ok    " if cond else "FAIL  ") + "[%s %d] %s" % [role, round, what])
	if not cond:
		fails += 1


func wait_until(cond: Callable, t := 10.0) -> bool:
	var end := Time.get_ticks_msec() + int(t * 1000)
	while not cond.call() and Time.get_ticks_msec() < end:
		await process_frame
	return cond.call()


func secs(t: float) -> void:
	await create_timer(t).timeout


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	role = args[0]
	port = int(args[1])
	round = int(args[2])
	_run()


func _run() -> void:
	Engine.set_meta("fast_test", true)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame
	main.save_path = PATH
	main.autosaves = role == "host"
	net = main.net
	match [role, round]:
		["host", 1]: await _host1()
		["host", 2]: await _host2()
		["client", 1]: await _client1()
		_: await _client2()
	print("mp_save.gd [%s %d]: %s" % [role, round, "ALL PASSED" if fails == 0 else "%d FAILED" % fails])
	net.leave()
	await secs(0.3)
	quit(1 if fails else 0)


func _host1() -> void:
	Save.delete(PATH)
	net.host(port, "Hosty")
	check(await wait_until(func(): return net.roster.size() == 2, 20.0), "the client joins")
	await secs(0.5)
	net.start()
	await secs(1.0)
	main.term.run("LEAVE_CHECKPOINT")
	main.term.run("ROUTE_TO " + main.route[0][0].letter)
	check(await wait_until(func(): return not main.at_checkpoint and not main.busy, 40.0), "at a station")
	main.add_photo({"stamp": "STN %s   09:30" % main.stop.letter})
	main.credits = 555
	await secs(4.0)   # (the client picks up its crowbar)
	main.autosave()   # asks the crew what they've got...
	await secs(1.0)
	check(main.crew_pockets.has("CLIENTY"), "the client's pockets come back to the host (%s)" % main.crew_pockets.keys())
	check(main.autosave(), "...and go into the save")
	check(Save.peek(PATH).get("crew", []).has("CLIENTY"), "the save lists the crew")
	await secs(1.0)


func _client1() -> void:
	await secs(1.0)
	net.join("127.0.0.1", port, "Clienty")
	check(await wait_until(func(): return net.started, 20.0), "the shift starts")
	check(await wait_until(func(): return not main.at_checkpoint and not main.busy and main.level != null, 60.0), "at a station")
	main.player.take({"id": "CROWBAR", "charge": -1.0})
	await secs(8.0)


func _host2() -> void:
	check(Save.exists(PATH), "there's a run to continue")
	net.host(port, "Hosty")
	check(await wait_until(func(): return net.roster.size() == 2, 20.0), "the client joins")
	await secs(0.5)
	check(main.continue_run(), "continuing the saved run")
	net.start()
	check(not main.at_checkpoint and main.credits == 555, "...at the station, with the credits")
	await secs(8.0)


func _client2() -> void:
	await secs(1.0)
	net.join("127.0.0.1", port, "Clienty")
	check(await wait_until(func(): return net.started, 20.0), "the shift starts")
	check(await wait_until(func(): return not main.at_checkpoint and main.level != null and main.level.facility != null, 30.0), "we're brought to the saved station")
	check(await wait_until(func(): return main.credits == 555, 5.0), "...the run's credits")
	check(await wait_until(func(): return main.player.slots.any(func(it): return it != null and it.id == "CROWBAR"), 8.0), "...and our crowbar is back in our hands")
	check(main.photo_log.size() == 1, "...the run's photos (%d)" % main.photo_log.size())
	check(main.get_tree().get_nodes_in_group("pickups").filter(func(p): return main.level.is_ancestor_of(p)).size() > 5, "...and the station's scrap")
