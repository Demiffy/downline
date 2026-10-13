# Your flashlight outside at night (player.gd's spot): in clear air, rain, snow and a sandstorm,
# the beam showing in what's in the air. Needs a window.
# Run: tests/run.sh 200 --path . -s tests/beam_shots.gd -- <dir> playground
extends SceneTree

var main
var pg
var out := ""


func _initialize() -> void:
	_run()


func snap(name: String) -> void:
	for i in 8:
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
	for c in pg._pages["SITES"].find_children("*", "Button", true, false):
		if (c as Button).text == "DESERT":
			c.pressed.emit()
	for i in 6:
		await process_frame
	while not pg._ready_done or main.busy:
		await process_frame
	pg.strip.visible = false
	var lv = main.level
	var p = main.player
	p.global_position = lv.to_global(Vector3(20, lv.ground_y(20, 55) + 0.3, 55))
	p.rotation.y = 0.6
	p.head.rotation.x = -0.15
	p.slots[0] = {"id": "FLASHLIGHT", "charge": main.charge_max("FLASHLIGHT"), "extra": {}}
	p.sel = 0
	main.hours = 23.0
	await create_timer(0.5).timeout
	p.light_on = true
	for w in ["CLEAR", "RAIN", "STORM", "SANDSTORM", "BLIZZARD"]:
		main.stop.weather = w
		await create_timer(2.5).timeout
		await snap("beam_%s" % w.to_lower())
	quit()
