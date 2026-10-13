# Age on the facility's walls (grime.gd): rust streaks, water stains, peeling paint, in a few rooms of
# the playground's facility, lights up (BRIGHT). Needs a window.
# Run: tests/run.sh 150 --path . -s tests/grime_wall_shots.gd -- <dir> playground
extends SceneTree

var main
var pg
var out := ""


func _initialize() -> void:
	_run()


func snap(name: String) -> void:
	for i in 30:
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
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.current = true
	var lamp := OmniLight3D.new()   # (a work lamp by the camera, so the walls show whatever the room's lights are)
	lamp.omni_range = 14.0
	lamp.light_energy = 1.4
	cam.add_child(lamp)
	if OS.get_cmdline_user_args().has("acne"):   # the bare walls, the old bias and the new
		for d in fac.find_children("*", "Decal", true, false): d.visible = false
		lamp.visible = false
		var ds: Array = fac.find_children("*", "Decal", true, false).filter(func(d): return d.get_meta("grime", "") == "rust")
		var lights: Array = main.find_children("*", "Light3D", true, false).filter(func(l): return not l is DirectionalLight3D)
		for b in [[0.02, 0.0], [0.06, 0.6]]:
			for l in lights:
				l.shadow_bias = b[0]
				l.shadow_normal_bias = b[1]
			for j in 3:
				var d: Decal = ds[j * ds.size() / 3]
				cam.look_at_from_position(d.global_position + d.global_transform.basis.y * 3.5 + Vector3(0, -0.8, 0), d.global_position + Vector3(0, -0.8, 0))
				await snap("bias_%s_%d" % [b[0], j])
		quit()
		return
	for kind in ["rust", "stain", "peel"]:
		var ds: Array = fac.find_children("*", "Decal", true, false).filter(func(d): return d.get_meta("grime", "") == kind)
		print(kind, " ", ds.size())
		for j in 2:
			var d: Decal = ds[j * ds.size() / 2]
			var n: Vector3 = d.global_transform.basis.y
			var at: Vector3 = d.global_position
			cam.look_at_from_position(at + n * 3.5 + Vector3(0, -0.3, 0), at)
			await snap("%s_%d" % [kind, j])
	quit()
