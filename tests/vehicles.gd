# The checkpoint's lorries and forklifts over ten minutes (at 5x): no two ever overlap (their bodies,
# without the margin they keep), none drives through one of the yard's people, and none gets stuck
# (each keeps getting round its legs).
# Run: tests/run.sh 200 --headless --path . -s tests/vehicles.gd
extends SceneTree

var main
var fails := 0


func _initialize() -> void:
	_run()


func check(ok: bool, what: String) -> void:
	print(("ok    " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _run() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	var a := Time.get_ticks_msec()
	while Time.get_ticks_msec() - a < 8000:
		await process_frame
	main.player.global_position = Vector3(0, 0.1, 75)   # (on the office steps, out of everyone's way)
	var yl: Node = main.level.find_child("YardLife", true, false)
	check(yl._vehicles.size() == 5, "five vehicles (%d)" % yl._vehicles.size())
	Engine.time_scale = 5.0
	var legs := {}
	var last_leg := {}
	var worst := 0.0
	var crashes := 0
	var hits := 0
	var sim := 0.0
	var stuck := {}
	while sim < float(OS.get_environment("SIM") if OS.get_environment("SIM") != "" else "600"):
		await physics_frame
		sim += main.get_physics_process_delta_time()
		var vs: Array = yl._vehicles
		if int(sim / 60.0) != int((sim - main.get_physics_process_delta_time()) / 60.0):
			printerr("sim %.0f s, real %d ms, delta %.3f" % [sim, Time.get_ticks_msec(), main.get_process_delta_time()])
		for v in vs:
			if last_leg.get(v.id, -1) != v.leg:
				legs[v.id] = legs.get(v.id, 0) + 1
				last_leg[v.id] = v.leg
				stuck[v.id] = 0.0
			stuck[v.id] = stuck.get(v.id, 0.0) + main.get_physics_process_delta_time()
			worst = maxf(worst, stuck[v.id])
		for i in vs.size():
			for j in range(i + 1, vs.size()):
				var oa: Array = yl._outline(vs[i], vs[i].node.position, vs[i].yaw)
				var ob: Array = yl._outline(vs[j], vs[j].node.position, vs[j].yaw)
				oa[3] -= 0.15
				oa[4] -= 0.15
				ob[3] -= 0.15
				ob[4] -= 0.15
				if yl._overlap(oa, ob):
					crashes += 1
					if crashes < 2:
						print("   crash at sim %.1f s: %d and %d at %s" % [sim, vs[i].id, vs[j].id, vs[i].node.position])
						for x in [vs[i], vs[j]]:
							print("      id %d leg %d s %.1f/%.1f v %.2f wait %.1f blocked_by %d turn %.2f yaw %.2f pos %s" % [x.id, x.leg, x.s, x.legs[x.leg].len, x.v, x.wait, x.blocked_by, yl._turniness(x), x.yaw, x.node.position])
			for w in yl._people:
				if w.sit:
					continue
				var o: Array = yl._outline(vs[i], vs[i].node.position, vs[i].yaw)
				o[3] -= 0.2
				o[4] -= 0.2
				if yl._overlap(o, yl._box2(w.node.position, 0.0, 0.25, 0.25, 0.0)):
					hits += 1
	Engine.time_scale = 1.0
	for x in yl._vehicles:
		print("   end: id %d %s leg %d s %.1f/%.1f v %.2f wait %.1f blocker %d by %d turn %.2f pos %s yaw %.2f" % [x.id, x.kind, x.leg, x.s, x.legs[x.leg].len, x.v, x.wait, x.blocker, x.blocked_by, yl._turniness(x), x.node.position, x.yaw])
	check(crashes == 0, "no two vehicles ever overlap (%d frames did)" % crashes)
	check(hits == 0, "nobody walked through by a vehicle (%d frames)" % hits)
	for v in yl._vehicles:
		check(legs.get(v.id, 0) >= 6, "vehicle %d (%s) kept going: %d legs in 10 min" % [v.id, v.kind, legs.get(v.id, 0)])
	check(worst < 120.0, "none stuck on one leg for 2 minutes (longest %.0f s)" % worst)
	print("vehicles.gd: " + ("ALL PASSED" if fails == 0 else "%d FAILED" % fails))
	quit()
