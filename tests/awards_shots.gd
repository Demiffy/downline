# The shift report's commendations (main.awards, report._show_slip): a crew of three with made-up
# tallies, the report shown, the slip slid in beside it. Also prints the awards picked for a crew of
# one. Needs a window. Run: tests/run.sh 120 --path . -s tests/awards_shots.gd -- <dir>
extends SceneTree

var main


func _initialize() -> void:
	_run()


func wait(secs: float) -> void:
	var a := Time.get_ticks_msec()
	while Time.get_ticks_msec() - a < secs * 1000.0:
		await process_frame


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await wait(10.0)
	main.player.shift = {"scrap": 14, "value": 212.0, "walked": 2410.0, "hurt": 85.0, "died": 0, "talk": 95.0, "loud": 2.0, "emotes": 1, "toys": 0, "thrown": 2, "jumps": 40}
	print("solo: ", main.awards())
	main.crew_shift = {
		"OSEI": {"scrap": 3, "value": 40.0, "walked": 380.0, "hurt": 160.0, "died": 2, "talk": 260.0, "loud": 31.0, "emotes": 12, "toys": 9, "thrown": 7, "jumps": 3},
		"KOVAC": {"scrap": 9, "value": 130.0, "walked": 1900.0, "hurt": 20.0, "died": 1, "talk": 12.0, "loud": 0.0, "emotes": 0, "toys": 1, "thrown": 14, "jumps": 8},
	}
	print("crew: ", main.awards())
	main._report()
	await wait(7.5)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "/report_awards.png")
	quit()
