# A crewmate's remains in the shredder's hopper (main.shred, shredder.refuse): the drive starts, jams,
# throws the body back out over the lip, the Bureau's notice fills the readout, the crew is fined.
# Needs a window. Run: tests/run.sh 150 --path . -s tests/body_shred_shots.gd -- <dir>
extends SceneTree

var main
var out := ""


func _initialize() -> void:
	_run()


func snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "/" + name + ".png")
	print("shot ", name)


func wait(secs: float) -> void:
	var a := Time.get_ticks_msec()
	while Time.get_ticks_msec() - a < secs * 1000.0:
		await process_frame


func _run() -> void:
	out = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await wait(12.0)
	main.hud.visible = false
	var level = main.level
	var hop: AABB = level.hopper
	var body = main.spawn_item("REMAINS", hop.get_center() + Vector3(0, 0.6, 0))
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.current = true
	var sh = level.shredder
	cam.look_at_from_position(level.to_global(Vector3(-5.0, 3.6, sh.LIP_Z - 6.0)), level.to_global(Vector3(0, 2.4, sh.LIP_Z + 1.0)))
	await wait(2.5)
	await snap("0_in_the_hopper")
	var before: int = main.credits
	main.shred()
	await wait(1.25)
	await snap("1_thrown_out")
	await wait(0.6)
	await snap("2_flying")
	cam.look_at_from_position(level.board.global_position + level.board.global_basis.z * 1.6 + Vector3(0, 0.3, 0), level.board.global_position)
	await wait(0.5)
	await snap("3_notice")
	print("credits %d -> %d, body in hopper now: %s" % [before, main.credits, hop.has_point(body.global_position)])
	quit()
