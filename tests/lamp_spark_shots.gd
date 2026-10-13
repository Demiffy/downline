# A failing lamp in the facility (facility.lamp_sparks): the shower of sparks as it dies, caught a
# moment in and a moment later, and the few it spits as it catches. Needs a window.
# Run: tests/run.sh 150 --path . -s tests/lamp_spark_shots.gd -- <dir> playground
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


func wait(secs: float) -> void:
	var a := Time.get_ticks_msec()
	while Time.get_ticks_msec() - a < secs * 1000.0:
		await process_frame


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
	var lamps: Array = fac.flicker.filter(func(l): return is_instance_valid(l) and l.global_position.y > fac.global_position.y + 1.0)
	print("failing lamps ", lamps.size())
	var l: Light3D = lamps[0]
	fac.flicker.clear()   # (held lit: we make it fail ourselves)
	l.light_energy = l.get_meta("base")
	fac._dim_bulb(l)
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.current = true
	var at := l.global_position
	var local: Vector3 = fac.to_local(at)
	var o: Vector3 = fac.to_global(Vector3(roundf(local.x / fac.CELL) * fac.CELL, 0.0, roundf(local.z / fac.CELL) * fac.CELL))   # (the middle of its room)
	var away := Vector3(o.x - at.x, 0, o.z - at.z)
	away = away.normalized() if away.length() > 0.5 else Vector3(1, 0, 0)
	cam.look_at_from_position(at + away * 3.5 + Vector3(0, -at.y + o.y + 1.5, 0), at + Vector3(0, -1.0, 0))
	await wait(1.0)
	fac.lamp_sparks(l, true, cam)
	await wait(0.18)
	await snap("shower_0")
	await wait(0.35)
	await snap("shower_1")
	await wait(1.5)
	fac.lamp_sparks(l, false, cam)
	await wait(0.08)
	await snap("spit")
	quit()
