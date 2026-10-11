# The sky through a day and its weathers, out at a station and through the train's window
# (rain on the glass), and a lightning strike. Needs a window.
# Run: godot --path . -s tests/sky_shots.gd -- <out_dir>
extends SceneTree

var out := "user://shots"
var main


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	_run()


func shot(name: String, frames := 30) -> void:
	for i in frames:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("saved ", name)


func _run() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame
	main.term.run("LEAVE_CHECKPOINT")
	main.term.run("ROUTE_TO " + main.route[0][0].letter)
	while main.busy:
		await process_frame
	main.hud.visible = false
	var p = main.player
	p.frozen = true
	main.stop.biome = "DESERT"
	# Outside, beside the train, looking along it and up at the sky.
	p.global_position = main.train.global_position + Vector3(14.0, 0.5, -9.0)
	p.look_at(main.train.global_position + Vector3(-6.0, 3.0, 0.0))
	p.rotation.x = 0.0
	p.rotation.z = 0.0
	p.head.rotation.x = 0.28
	for c in [["dawn", "CLEAR", 8.2], ["noon", "CLEAR", 13.0], ["overcast", "OVERCAST", 14.0], ["rain", "RAIN", 12.0],
			["dusk", "CLEAR", 18.6], ["night", "CLEAR", 22.5], ["acid", "ACID_RAIN", 11.0], ["storm", "STORM", 16.0]]:
		main.stop.weather = c[1]
		main.hours = c[2]
		main.weather._next = 999.0
		await shot("k_" + c[0], 40)
	main.stop.weather = "STORM"
	main.hours = 20.5
	await shot("k_storm_dark", 20)
	main.weather.strike([-55.0, 40.0, 0.5])
	await shot("k_storm_bolt", 3)
	# Aboard, at a window, in the rain.
	main.stop.weather = "RAIN"
	main.hours = 12.0
	p.global_position = main.train.global_position + Vector3(-1.2, 1.2, 1.4)
	p.rotation.y = 0.0
	p.head.rotation.x = 0.0
	p.look_at(p.global_position + Vector3(0, 0, 1))
	p.rotation.x = 0
	await shot("k_window_rain", 200)
	quit()
