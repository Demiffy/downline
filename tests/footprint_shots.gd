# Boot prints (footprints.gd) walked across sand, snow and swamp mud, a curving trail each, then
# photographed from behind the walker and close up. Needs a window.
# Run: tests/run.sh 300 --path . -s tests/footprint_shots.gd -- <dir> playground
extends SceneTree

const Footprints = preload("res://src/footprints.gd")

var main
var pg
var out := ""


func _initialize() -> void:
	_run()


func snap(name: String) -> void:
	for i in 4:
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
	var cam := Camera3D.new()
	main.add_child(cam)
	for b in ["DESERT", "ARCTIC", "SWAMP"]:
		for c in pg._pages["SITES"].find_children("*", "Button", true, false):
			if (c as Button).text == b:
				c.pressed.emit()
		for i in 6:
			await process_frame
		while not pg._ready_done or main.busy:
			await process_frame
		main.hours = 11.0
		main.hud.visible = false
		pg.strip.visible = false
		var lv = main.level
		var walker := Node3D.new()
		lv.add_child(walker)
		var fp := Footprints.new()
		var x := 20.0
		var z := 40.0
		if b == "SWAMP":   # (down where it's mud, at the water's edge)
			for i in 400:
				var tx := randf_range(-80, 80)
				var tz := randf_range(20, 80)
				if absf(lv.ground_y(tx, tz) - (lv.water_y + 0.15)) < 0.08:
					x = tx
					z = tz
					break
		var heading := 0.0
		var last := Vector3.ZERO
		for i in 240:   # 12 m of walking, curving
			heading += 0.012
			var v := Vector3(sin(heading), 0, cos(heading)) * 1.4
			x += v.x / 20.0
			z += v.z / 20.0
			var p: Vector3 = lv.to_global(Vector3(x, lv.ground_y(x, z), z))
			walker.global_position = p
			fp.walk(walker, main, 1.0 / 20.0, v, true)
			last = p
		cam.current = true
		var back := Vector3(sin(heading), 0, cos(heading))
		cam.look_at_from_position(last + back * 1.0 + Vector3(0, 1.8, 0), last - back * 3.5)   # (ahead of the walker, looking back down the trail)
		await snap(b.to_lower() + "_trail")
		cam.look_at_from_position(last - back * 2.0 + Vector3(0.4, 1.0, 0), last - back * 3.2)
		await snap(b.to_lower() + "_close")
	quit()
