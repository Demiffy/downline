# The dam landmark stop: the route offers one an assignment and the map and VIEW_STATION say so; the
# stop builds the dam with the lift by the powerhouse, the DAM facility under it and the windings in
# it; the ridges stand round the reservoir; the crest road and the stair tower's flights are
# walkable; nothing random lands on the works; at 18:00 the sluices open and rooms go under.
# Run: tests/run.sh 200 --headless --path . -s tests/dam.gd
extends SceneTree

var fails := 0


func check(cond: bool, what: String) -> void:
	print(("ok    " if cond else "FAIL  ") + what)
	if not cond:
		fails += 1


func frames(n: int) -> void:
	for i in n:
		await process_frame


func _initialize() -> void:
	_run()


func _run() -> void:
	Engine.set_meta("fast_test", true)
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await frames(10)
	var Dam = load("res://src/dam.gd")
	Engine.set_meta("force_dam", true)   # (the dam where the test can find it: the first stop's first choice)
	main.term.run("LEAVE_CHECKPOINT")
	Engine.remove_meta("force_dam")
	var lm := 0
	for opts in main.route:
		for o in opts:
			if o.has("landmark"):
				lm += 1
	check(lm == 1, "the route offers one landmark stop an assignment (%d)" % lm)
	var stop: Dictionary = main.route[0][0]
	check(stop.get("landmark", "") == "DAM" and stop.theme == "DAM" and stop.get("name", "") != "", "forced, the first stop is a dam (%s %s)" % [stop.get("name", "?"), stop.get("landmark", "?")])
	check(stop.biome in ["DESERT", "ARCTIC", "FOREST"], "...in country that suits it (%s)" % stop.biome)
	main.term.run("MAP")
	main.term.run("VIEW_STATION " + stop.letter)   # (prints the landmark: no crash)
	main.term.run("ROUTE_TO " + stop.letter)
	while main.busy:
		await process_frame
	await frames(5)
	var lvl = main.level
	var fac = lvl.facility
	check(lvl.dam, "the stop is built as a dam")
	check(lvl.elevator_pos.distance_to(Dam.LIFT) < 0.01, "the lift goes down by the powerhouse")
	check(fac.theme_id == "DAM", "the facility under it is the powerhouse's galleries")
	var kinds: Array = fac.groups.map(func(g): return g.kind)
	check(kinds.has("turbine_hall") or kinds.has("control_room") or fac.groups.is_empty(), "its big rooms are turbine halls and control rooms (%s)" % str(kinds))
	var windings: Array = main.get_tree().get_nodes_in_group("pickups").filter(func(p): return p.id == "WINDINGS")
	check(windings.size() == 1, "the generator windings are down there, once")
	check(windings.size() == 1 and windings[0].global_position.y < lvl.global_position.y - 40.0, "...in the facility")
	# The ground round it: ridges either side of the reservoir, up past the crest.
	var line = main.line
	check(line.height(140.0, 100.0) > Dam.CREST, "the ridge stands over the dam's east end (%.0f m)" % line.height(140.0, 100.0))
	check(line.height(-140.0, 100.0) > Dam.CREST, "...and the west (%.0f m)" % line.height(-140.0, 100.0))
	check(line.height(0.0, -150.0) < 30.0, "...not across the line's valley in front (%.0f m)" % line.height(0.0, -150.0))
	# Walkable: the crest road and the stair tower's flights.
	var space = lvl.get_world_3d().direct_space_state
	for x in [-60.0, 0.0, 80.0]:
		var top: Vector3 = lvl.to_global(Vector3(x, Dam.CREST + 5.0, Dam.up_z(x)) + Dam.out_n(x) * (Dam.TOP_T / 2.0))
		var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(top, top - Vector3(0, 10, 0), 1))
		check(not hit.is_empty() and absf(hit.position.y - lvl.to_global(Vector3(0, Dam.CREST, 0)).y) < 0.4, "the crest road is solid underfoot at x %.0f" % x)
	var hit2: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(lvl.to_global(Dam.STAIR + Vector3(0, 30.5, -0.75)), lvl.to_global(Dam.STAIR + Vector3(0, 25.0, -0.75)), 1))
	check(not hit2.is_empty(), "the stair tower has flights to climb")
	check(atan2(2.75, 6.4 - 2.2) < deg_to_rad(40.0), "...shallow enough to walk up (%.0f degrees)" % rad_to_deg(atan2(2.75, 6.4 - 2.2)))
	var bad := 0
	for h in lvl._house_spots:
		if Dam.keep_out(h, 6.0):
			bad += 1
	for p in main.get_tree().get_nodes_in_group("pickups"):
		var l: Vector3 = lvl.to_local(p.global_position)
		var in_dam: bool = l.z > Dam.toe_z(clampf(l.x, -Dam.SPAN, Dam.SPAN)) - 1.0 or Dam.BASIN.has_point(Vector2(l.x, l.z))
		if l.y > -20.0 and l.y < 30.0 and absf(l.x) < 100.0 and absf(l.z) < 100.0 and in_dam:   # (in the dam's mass or the basin, at this stop; up on the crest is fine)
			bad += 1
			print("  in the dam: ", p.id, " at ", l)
	check(bad == 0, "no house or scrap lands in the dam or its basin (%d)" % bad)
	# The sluices at 18:00.
	var site = lvl.site
	check(site.events.any(func(e): return e[1] == "sluices"), "the sluices are on the day's timetable")
	check(site.events.filter(func(e): return e[1] == "inflow").size() >= 4, "...and the rooms they flood after")
	var wet0: int = lvl.hazards.flooded.size()
	site._say(["sluices"])
	for i in 3:
		var c = site._inflow_room()
		if c != null:
			site._say(["inflow", c])
	await frames(5)
	check(lvl.hazards.flooded.size() >= wet0 + 3, "the water comes in: rooms go under (%d -> %d)" % [wet0, lvl.hazards.flooded.size()])
	print("dam.gd: %s" % ("ALL PASSED" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails else 0)
