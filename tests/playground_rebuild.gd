# The playground rebuilds the facility as each theme in turn (F10) without the renderer crashing, and its
# list of sounds playing (F12) names what's playing. Needs a window: the crash was the renderer's (a lamp's
# mask or a mesh's layers changed while one lit the other: build.gd set_cull_mask). Judge it by the log
# too: no "BUG, indexing did not unpair geometries from light". `gd`: the all-GDScript build path.
# Run: tests/run.sh 300 --path . -s tests/playground_rebuild.gd -- playground [gd] [shot.png]
extends SceneTree

var main
var pg


func _initialize() -> void:
	_run()


func _run() -> void:
	if "gd" in OS.get_cmdline_user_args():   # (the all-GDScript build path)
		Engine.set_meta("gd_merge", true)
		Engine.set_meta("gd_geom", true)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	while pg == null:
		await process_frame
		for c in main.get_children():
			if c.get_script() != null and c.get_script().resource_path.ends_with("playground.gd"):
				pg = c
	while not pg._ready_done:
		await process_frame
	var fails := 0
	pg._hotkey(KEY_F12)
	var Sfx = load("res://src/sfx.gd")
	Sfx.play(main, "ding")
	Sfx.play(main, "clank", main.player.global_position + Vector3(3, 1, 0))
	for f in 15:
		await process_frame
	var table: String = pg.sounds.report()
	for want in ["ding", "clank", "FLAT", "m ", "UI", "WORLD", "AMBIENT"]:
		if not want in table:
			print("FAIL  the sounds list shows %s:\n%s" % [want, table])
			fails += 1
	for a in OS.get_cmdline_user_args():
		if String(a).ends_with(".png"):
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(a)
	for i in 6:
		for f in 90:   # (a moment down there: the lamp budgets run, far lamps go out)
			await process_frame
		pg._hotkey(KEY_F10)
		while not pg._ready_done or main.busy:
			await process_frame
		print("rebuilt as %s" % pg.theme)
	for f in 60:
		await process_frame
	print("playground_rebuild.gd: %s" % ("ALL PASSED" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails else 0)
