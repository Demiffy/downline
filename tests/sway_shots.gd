# The train's hanging lamps: at a stand, then 2 s into braking from 30 m/s (swung forward), then 2 s
# into pulling away (swung back), seen side on in the crew car. Needs a window.
# Run: tests/run.sh 120 --path . -s tests/sway_shots.gd -- <dir> playground
extends SceneTree

var main
var pg
var out := ""


func _initialize() -> void:
	_run()


func snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "/" + name + ".png")
	print("shot ", name)


## Runs the line's speed (the train follows it) by `accel` m/s² for `secs`.
func drive(accel: float, secs: float) -> void:
	var left := secs
	while left > 0.0:
		var d: float = await process_frame_delta()
		main.line.v = maxf(0.0, main.line.v + accel * d)
		left -= d


func process_frame_delta() -> float:
	var a := Time.get_ticks_usec()
	await process_frame
	return (Time.get_ticks_usec() - a) / 1000000.0


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
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.current = true
	cam.fov = 60.0
	var t: Node3D = main.train
	cam.look_at_from_position(t.to_global(Vector3(0.5, 2.6, 1.7)), t.to_global(Vector3(0.5, 3.3, -0.3)))
	await drive(0.0, 6.0)   # (settled after the load)
	await snap("0_stand")
	main.line.riding = true   # (no trip: we set its speed ourselves)
	main.line.v = 30.0
	await drive(0.0, 6.0)
	await drive(-2.1, 1.0)
	await snap("1_braking")
	main.line.v = 0.0
	await drive(0.0, 8.0)
	await drive(2.2, 0.9)
	await snap("2_pulling_away")
	await drive(0.0, 0.4)
	await snap("3_swinging")
	quit()
