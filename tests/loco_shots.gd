# The loco's stack and the brake shoes: idle smoke, the black gout as the throttle opens, working hard
# (sparks up the stack now and then), and sparks off the wheels braking, by day. Needs a window.
# Run: tests/run.sh 120 --path . -s tests/loco_shots.gd -- <dir> playground
extends SceneTree

var main
var pg
var out := ""
var _v := 0.0


func _initialize() -> void:
	_run()


func snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "/" + name + ".png")
	print("shot ", name)


## Runs the train's speed by `accel` m/s² for `secs` (main eases it toward 0 each frame, there being
## no trip: that only adds to the slowing).
func drive(accel: float, secs: float) -> void:
	var left := secs
	while left > 0.0:
		var a := Time.get_ticks_usec()
		await process_frame
		var d := (Time.get_ticks_usec() - a) / 1000000.0
		_v = maxf(0.0, _v + accel * d)
		main.train.speed = _v
		left -= d


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
	for c in pg._pages["SITES"].find_children("*", "Button", true, false):   # (out in the open)
		if (c as Button).text == "DESERT":
			c.pressed.emit()
	for i in 6:
		await process_frame
	while not pg._ready_done or main.busy:
		await process_frame
	main.hud.visible = false
	pg.strip.visible = false
	main.hours = 11.0
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.current = true
	var t: Node3D = main.train
	t.notch = 0
	cam.look_at_from_position(t.to_global(Vector3(11.6, 5.0, -13.0)), t.to_global(Vector3(11.6, 6.0, 0.0)))
	await drive(0.0, 4.0)
	await snap("0_idle")
	t.notch = 8
	await drive(0.0, 1.2)
	await snap("1_gout")
	for k in 3:
		await drive(0.0, 0.8)
		await snap("2_working_%d" % k)
	_v = 16.0
	t.notch = 0
	await drive(0.0, 2.0)
	cam.look_at_from_position(t.to_global(Vector3(12.5, 0.9, -5.5)), t.to_global(Vector3(12.5, 0.4, -0.78)))
	await drive(-2.1, 1.5)
	await snap("3_braking")
	quit()
