# Light in the facility's haze (art.gd hanging_lamp's cone, the dust you carry): a few hanging lamps
# from across their rooms, then your flashlight beam with the dust in it. Needs a window.
# Run: tests/run.sh 300 --path . -s tests/shaft_shots.gd -- <dir> playground [THEME]
extends SceneTree

var main
var pg
var out := ""


func _initialize() -> void:
	_run()


func snap(name: String) -> void:
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "/" + name + ".png")
	print("shot ", name)


func _run() -> void:
	out = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	while pg == null:
		for c in main.get_children():
			if c.get_script() != null and c.get_script().resource_path.ends_with("playground.gd"):
				pg = c
		await process_frame
	while not pg._ready_done:
		await process_frame
	pg.strip.visible = false
	main.hud.visible = false
	await create_timer(1.0).timeout
	var cones: Array = main.level.facility.find_children("Cone", "SpotLight3D", true, false)
	print("cones: ", cones.size())
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.current = true
	var k := 0
	for c in cones.slice(0, 3):
		var at: Vector3 = (c as Node3D).global_position
		var fac = main.level.facility
		var o: Vector3 = fac.to_global(Vector3(fac.cell_at(at).x * fac.CELL, 0, fac.cell_at(at).y * fac.CELL))
		cam.look_at_from_position(at + Vector3(3.5, -0.6, 3.5), Vector3(at.x, at.y - 1.4, at.z))
		await create_timer(0.6).timeout   # (the facility shows lamps near the camera: it looks every 0.25 s)
		await snap("lamp_%d" % k)
		k += 1
	main.hud.visible = true
	cam.current = false
	main.player.cam.current = true
	main.player.light_on = true
	await create_timer(1.5).timeout
	await snap("beam_dust")
	quit()
