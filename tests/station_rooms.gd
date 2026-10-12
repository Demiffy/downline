# Inside the station building (station.gd): each room from under its ceiling looking down (the
# layout: is every doorway clear?), and as you walk in; the platform's benches. Builds a stop through the playground.
# Needs a window. Run: tests/run.sh 300 --path . -s tests/station_rooms.gd -- <dir> playground
extends SceneTree

const Station = preload("res://src/station.gd")

var main
var pg
var out := ""
var cam: Camera3D


func _initialize() -> void:
	_run()


func shot(name: String, from: Vector3, at: Vector3, fov := 70.0) -> void:
	cam.fov = fov
	cam.global_position = from
	if absf((at - from).normalized().y) > 0.99:
		cam.look_at(at, Vector3(0, 0, -1))
	else:
		cam.look_at(at)
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
	for c in pg._pages["SITES"].find_children("*", "Button", true, false):
		if (c as Button).text == "DESERT":
			c.pressed.emit()
	for i in 6:
		await process_frame
	while not pg._ready_done or main.busy:
		await process_frame
	main.hours = 12.0
	main.hud.visible = false
	pg.strip.visible = false
	cam = Camera3D.new()
	main.add_child(cam)
	cam.current = true
	var lamp := OmniLight3D.new()   # (a flashlight's worth)
	lamp.omni_range = 12.0
	lamp.light_energy = 1.2
	cam.add_child(lamp)
	var lv: Node3D = main.level
	var c: Vector3 = lv.to_global(Vector3(lv._station_x, 0, Station.Z1 + Station.DEEP / 2.0))   # the building's middle
	var f := Station.TOP
	for i in 30:
		await process_frame
	# From under the ceiling, looking down: the hall, the office (-x), the waiting room (+x).
	for rm in [["hall", 0.0, 3.0], ["office", -6.0, 3.0], ["waiting", 6.0, 3.0]]:
		await shot("top_" + rm[0], c + Vector3(rm[1], f + 3.55, 0.01), c + Vector3(rm[1], f, 0), 100.0)
	# Walking in: the hall from the platform door and from the back door, each side room from its door.
	await shot("in_hall_from_platform", c + Vector3(0, f + 1.6, -3.4), c + Vector3(0, f + 1.0, 3.0))
	await shot("in_hall_from_back", c + Vector3(0, f + 1.6, 3.4), c + Vector3(0, f + 1.0, -3.0))
	await shot("in_office", c + Vector3(-2.4, f + 1.6, 1.8), c + Vector3(-7.5, f + 0.9, 0.0))
	await shot("in_waiting", c + Vector3(2.4, f + 1.6, 1.8), c + Vector3(7.5, f + 0.9, 0.0))
	await shot("in_office_back", c + Vector3(-8.4, f + 1.6, -3.2), c + Vector3(-3.0, f + 0.9, 2.0))
	await shot("in_waiting_back", c + Vector3(8.4, f + 1.6, -3.2), c + Vector3(3.0, f + 0.9, 2.0))
	# The platform's benches, from the track side: backs to the building, facing you.
	var pb: Vector3 = lv.to_global(Vector3(11.5, 0, Station.Z1))
	await shot("platform_benches", pb + Vector3(0, f + 1.4, -3.4), pb + Vector3(0, f + 0.4, 0))
	quit()
