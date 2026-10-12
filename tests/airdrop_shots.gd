# An airdrop, photographed as it happens: the plane coming over, the crate out of the door, the
# canopy blossoming, coming down swinging, the landing and the chute collapsing, the flare's smoke from
# afar, the crate close up, then pried open. Real time (about 40 s). Needs a window.
# Run: tests/run.sh 200 --path . -s tests/airdrop_shots.gd -- <dir> [hour]
extends SceneTree

var out := ""
var main
var cam: Camera3D


func _initialize() -> void:
	_run()


func shot(name: String, pos: Vector3, at: Vector3) -> void:
	cam.global_position = pos
	cam.look_at(at)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "/" + name + ".png")
	print("shot ", name)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 30:
		await process_frame
	main.hud.visible = false
	main.player.frozen = true
	main.term.run("LEAVE_CHECKPOINT")
	var d: Dictionary = main.route[0][0]
	d.biome = "DESERT"
	d.weather = "CLEAR"
	Engine.set_meta("fast_test", true)
	main.term.run("ROUTE_TO " + d.letter)
	while main.busy:
		await process_frame
	Engine.remove_meta("fast_test")
	cam = Camera3D.new()
	main.add_child(cam)
	cam.current = true
	cam.fov = 60
	cam.far = 3000.0
	var hz = main.level.hazards
	hz.events.clear()
	var lv = main.level
	var land: Vector3 = lv.to_global(hz._drop_spot())
	for i in 60:
		main.hours = float(args[1]) if args.size() > 1 else 11.0
		await process_frame
	if args.size() > 2 and args[2] == "crash":
		Engine.set_meta("force_crash", true)
	main.player.global_position = land + Vector3(-14, 0.5, -14)
	hz.airdrop(lv.to_local(land), 0.6)
	var dr: Node3D = null
	for c in lv.get_children():
		if c.get_script() != null and c.get_script().resource_path.ends_with("airdrop.gd"):
			dr = c
	var eye := land + Vector3(-22, 1.8, -24)
	cam.global_position = eye + Vector3(0, 30, 0)   # (not left at the origin, under the dunes, while it waits)
	while dr._t < dr._over - 6.0:
		await process_frame
	await shot("01_plane_coming", eye, dr.plane.global_position)
	if dr.crash:
		await shot("01b_burning_close", dr.plane.global_position + Vector3(-30, -6, 25), dr.plane.global_position)
		if args.size() > 3:   # (just the plane)
			quit()
			return
	while dr._t < dr._over + 0.6:
		await process_frame
	await shot("02_out_of_the_door", dr.body.global_position + Vector3(-30, -8, -30), dr.body.global_position)
	while dr._t < dr._over + dr.FALL + 0.35:
		await process_frame
	await shot("03_canopy_blossoms", dr.body.global_position + Vector3(-24, -4, -24), dr.body.global_position + Vector3(0, 6, 0))
	while dr.body.position.y > 40.0:
		await process_frame
	await shot("04_coming_down", eye, dr.body.global_position + Vector3(0, 4, 0))
	await shot("04b_under_canopy", dr.body.global_position + Vector3(-8, 2, -8), dr.body.global_position + Vector3(0, 4, 0))
	while dr._phase != "down":
		await process_frame
	for i in 6:
		await process_frame
	await shot("05_landing", land + Vector3(-9, 2.0, -9), land + Vector3(0, 0.5, 0))
	var side := land + Vector3(-dr.heading.z, 0, dr.heading.x) * 16.0 + Vector3(0, 3.0, 0)
	for f in [0.6, 1.5, 2.1, 2.6]:   # the canopy collapsing, from the side
		await create_timer(f - (0.0 if f == 0.6 else [0.6, 1.5, 2.1, 2.6][[0.6, 1.5, 2.1, 2.6].find(f) - 1])).timeout
		await shot("05_collapse_%.1f" % f, side, land + dr.heading * 3.0 + Vector3(0, 2.0, 0))
	await create_timer(2.0).timeout
	await shot("06_chute_down_flare", land + Vector3(-10, 2.5, -8), land + Vector3(0, 0.8, 0))
	await shot("07_smoke_from_afar", land + Vector3(-80, 6, -70), land + Vector3(0, 12, 0))
	await shot("08_crate_close", land + Vector3(-2.6, 1.6, -2.0), land + Vector3(0, 0.5, 0))
	dr._open()
	await create_timer(1.5).timeout
	await shot("09_pried_open", land + Vector3(-2.8, 1.9, -2.2), land + Vector3(0, 0.4, 0))
	await shot("10_open_above", land + Vector3(-1.6, 3.0, -1.4), land + Vector3(0, 0.2, 0))
	if args.size() > 2 and args[2] == "crash":   # (forced: it goes down)
		while not dr._crashed:
			await process_frame
		var at: Vector3 = dr.crash_at
		var from := land + Vector3(0, 3, 0) + Vector3(at.x - land.x, 0, at.z - land.z).normalized() * 120.0
		var t0: float = dr._t
		for f in [0.08, 0.5, 1.5, 4.0, 9.0, 20.0]:   # seconds after it hits
			while dr._t < t0 + f:
				await process_frame
			await shot("11_crash_%04.1f" % f, from, at + Vector3(0, 35, 0))
		var back := Vector3(at.x - land.x, 0, at.z - land.z).normalized()
		await shot("12_crash_from_drop", land - back * 25.0 + Vector3(0, 22, 0), at + Vector3(0, 60, 0))
	quit()
