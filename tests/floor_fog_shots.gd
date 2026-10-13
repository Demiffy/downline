# Fog lying on the facility's lower floor (facility._floor_fog, LOW_FOG): a few B-2 rooms, by the
# room's light and a torch, and the same view a few seconds later (it creeps). Needs a window.
# Run: tests/run.sh 150 --path . -s tests/floor_fog_shots.gd -- <dir> playground
extends SceneTree

var main
var pg
var out := ""


func _initialize() -> void:
	_run()


func snap(name: String, frames := 30) -> void:
	for i in frames:
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
	while not pg._ready_done or main.busy:
		await process_frame
	main.hud.visible = false
	pg.strip.visible = false
	var fac = main.level.facility
	var rooms: Array = fac.lower.keys().filter(func(c): return fac.low_kinds[c] != "pit")
	print("lower rooms ", rooms.size(), " fog volumes ", fac.low_root.find_children("*", "FogVolume", true, false).size())
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.current = true
	var torch := SpotLight3D.new()   # (a torch, as you'd carry one)
	torch.spot_range = 18.0
	torch.spot_angle = 28.0
	torch.light_energy = 3.0
	torch.light_volumetric_fog_energy = 2.0
	cam.add_child(torch)
	for i in mini(3, rooms.size()):
		var c: Vector2i = rooms[i]
		var o: Vector3 = fac.to_global(Vector3(c.x * fac.CELL, -fac.PIT, c.y * fac.CELL))
		cam.look_at_from_position(o + Vector3(-4.5, 1.5, -4.5), o + Vector3(3.0, 0.2, 3.0))
		await snap("room_%d" % i)
	await snap("room_%d_later" % (mini(3, rooms.size()) - 1), 300)
	quit()
