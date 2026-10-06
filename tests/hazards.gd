# Hazards, events, habitats and the pause menu. Run: godot --headless --path . -s tests/hazards.gd
extends SceneTree

var fails := 0
var main


func check(cond: bool, what: String) -> void:
	print(("ok    " if cond else "FAIL  ") + what)
	if not cond:
		fails += 1


func frames(n: int) -> void:
	for i in n:
		await process_frame


func secs(t: float) -> void:
	await main.get_tree().create_timer(t).timeout


func _initialize() -> void:
	_run()


## Put the player on the floor of a cell, clear of the walkway cross.
func stand(fac, c: Vector2i, off := Vector3(2.0, 0, 2.0)) -> void:
	var p = main.player
	p.global_position = fac.to_global(Vector3(c.x * 12.0, 0.05, c.y * 12.0) + off)
	p.velocity = Vector3.ZERO


func _run() -> void:
	Engine.set_meta("fast_test", true)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await frames(10)
	var p = main.player
	main.term.run("LEAVE_CHECKPOINT")
	var stop: Dictionary = main.route[0][0]
	stop.theme = "LAB"
	stop.rooms = 20
	p.global_position = Vector3(0, 1.3, 0)
	main.term.run("ROUTE_TO " + stop.letter)
	while main.busy:
		await process_frame
	var lvl = main.level
	var fac = lvl.facility
	var hz = lvl.hazards
	check(hz != null and hz.breaker != null, "every station has a main breaker")
	main.term.run("VIEW_STATION " + stop.letter)
	check(main.term.out.get_parsed_text().contains("TOXIC GAS"), "VIEW_STATION lists the site's hazards")

	# Habitats.
	lvl.info.theme = "BACKROOMS"
	check(lvl._n("roomba", 4) == 0 and lvl._n("mimic", 3) == 0, "no roombas or mimics in the backrooms")
	lvl.info.theme = "FLESH"
	check(lvl._n("snatcher", 2) >= 5, "the flesh is full of snatchers")
	lvl.info.theme = "LAB"

	# Make sure each room hazard exists in this layout.
	var rooms: Array = fac.layout.cells.filter(func(c): return not fac.kinds[c] in ["start", "pit", "vault", "atrium", "tunnel"] and not hz.flooded.has(c) and not hz.gassed.has(c))
	if hz.gassed.is_empty():
		hz._gas(rooms.pop_back())
	if hz.flooded.is_empty():
		hz._flood(rooms.pop_back())
	if hz.cables.is_empty():
		hz._cable(hz.flooded.keys()[0], Vector3(hz.flooded.keys()[0].x * 12.0, 0, hz.flooded.keys()[0].y * 12.0))
	if hz.steams.is_empty():
		hz._steam_room(rooms.pop_back())
	main.spawn_item("PENNY", p.global_position)   # (nothing)

	# Flood: wading is slow and splashes.
	var wc: Vector2i = hz.cables[0].cell
	stand(fac, wc)
	await frames(4)
	stand(fac, wc)
	await frames(2)
	check(p.wading, "standing in a flooded room means wading")
	check(main.surface_at(p.global_position) == "water", "...and your footsteps splash")
	# Live cable arcs through the water.
	p.hp = 100.0
	var cb: Dictionary = hz.cables[0]
	cb.state = 1
	cb.t = 0.0
	stand(fac, wc)
	await frames(3)
	check(p.hp <= 66.5, "a live cable arcing through the water hurts whoever is wading (hp %d)" % p.hp)

	# Gas: choking without a mask, fine with one.
	var gc: Vector2i = hz.gassed.keys()[0]
	p.hp = 100.0
	p.since_hurt = 0.0
	stand(fac, gc)
	await secs(1.0)
	check(p.hp < 97.0, "toxic gas hurts (hp %d)" % p.hp)
	p.hp = 100.0
	p.slots[1] = {"id": "GAS_MASK", "charge": -1.0}
	stand(fac, gc)
	await secs(0.6)
	check(p.hp >= 99.9, "a gas mask in your pack keeps you breathing")
	p.slots[1] = null
	check(main.get_tree().get_nodes_in_group("pickups").any(func(n): return n.id == "GAS_MASK"), "a gas mask is somewhere on a gassed site")

	# Steam: stand in front of a bursting line.
	var st: Dictionary = hz.steams[0]
	p.hp = 100.0
	var spot: Vector3 = st.at + st.dir * 1.5
	p.global_position = Vector3(spot.x, spot.y - 1.35, spot.z)
	p.velocity = Vector3.ZERO
	st.state = 1
	st.t = 0.0
	await secs(0.5)
	check(p.hp < 95.0, "a burst steam line scalds (hp %d)" % p.hp)
	st.state = 0
	st.t = 99.0
	st.fx.core.emitting = false

	# Power failure: dark site, crawling lift, no cameras, breaker brings it back.
	p.hp = 100.0
	stand(fac, Vector2i.ZERO, Vector3(3.5, 0, 3.5))
	var lights: Array = fac.find_children("*", "Light3D", true, false)
	var lit_before: int = lights.filter(func(l): return l.visible).size()
	hz.power_fail()
	await secs(1.5)
	check(not hz.power and not lvl.powered(), "power failure cuts site power")
	check(lights.filter(func(l): return l.visible).is_empty(), "...every facility light goes out (%d were on)" % lit_before)
	main.term.run("LIST_CAMS")
	check(main.term.out.get_parsed_text().contains("NO SIGNAL"), "...the cameras lose signal")
	check(hz.cables.all(func(c): return c.light.light_energy == 0.0), "...and the live cables go dead")
	hz.restore()
	await secs(4.5)   # the lights come back in a wave out from the breaker
	check(hz.power and lights.filter(func(l): return l.visible).size() == lit_before, "the main breaker brings every light back (%d of %d)" % [lights.filter(func(l): return l.visible).size(), lit_before])

	# Tremor: debris comes down near you.
	stand(fac, Vector2i.ZERO, Vector3(3.5, 0, 3.5))
	var kids: int = fac.get_child_count()
	hz.tremor()
	await secs(5.0)
	check(fac.get_child_count() > kids, "a tremor brings the ceiling down (%d new pieces)" % (fac.get_child_count() - kids))

	# Airdrop: a crate under a flare; prying it open spills supplies.
	p.global_position = lvl.elevator_pos + Vector3(0, 0.5, -6)
	hz.airdrop()
	await secs(3.0)
	var drops: Array = main.get_tree().get_nodes_in_group("scan_targets").filter(func(n): return n.get_meta("scan_name") == "AIRDROP")
	check(drops.size() == 1, "the airdrop lands")
	if drops.size() == 1:
		var before: int = main.get_tree().get_nodes_in_group("pickups").size()
		hz._open_drop(drops[0])
		await frames(3)
		check(main.get_tree().get_nodes_in_group("pickups").size() >= before + 2, "...and holds Bureau supplies")

	# Scanner pulse: finds light up as the wave reaches them, then go back to normal.
	p.equip = {"id": "SCANNER", "charge": -1.0}
	p.global_position = lvl.elevator_pos + Vector3(0, 0.5, -6)
	var bit = main.spawn_item("COPPER_PIPE", p.global_position + Vector3(2, 0.5, 0))
	await secs(0.3)
	p._scan_cd = 0.0
	p._scan()
	await secs(0.6)
	var glowing: bool = bit.find_children("*", "MeshInstance3D", true, false).any(func(m): return m.material_overlay != null)
	check(glowing, "the scan wave lights up scrap it reaches")
	await secs(8.0)
	check(bit.find_children("*", "MeshInstance3D", true, false).all(func(m): return m.material_overlay == null), "...and the highlight wears off")

	# Pause menu + settings.
	main.menu.open()
	check(main.get_tree().paused and main.menu.is_open(), "Esc menu pauses the game")
	var hp_t: float = main.hours
	await frames(10)
	check(main.hours == hp_t, "...time stops while paused")
	main.menu.close()
	check(not main.get_tree().paused, "...and resumes")
	var S = load("res://src/settings.gd")
	var keep: Dictionary = S.v.duplicate()
	S.v.sens = 1.7
	S.save()
	S.v.sens = 1.0
	S.load_file()
	check(is_equal_approx(float(S.v.sens), 1.7), "settings save and load")
	S.v = keep
	S.save()
	print("hazards.gd: %s" % ("ALL PASSED" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails else 0)
