# The suit's grime (suit.gd set_grime): clean, muddy, snowy, wet, bloody and all of it, front and
# back, then the muddy one and the snowy one mid-stride. Needs a window.
# Run: tests/run.sh 120 --path . -s tests/grime_shots.gd -- <dir>
extends SceneTree

const Suit = preload("res://src/suit.gd")
const A = preload("res://src/art.gd")

var cam: Camera3D
var out := ""


func snap(name: String, from: Vector3, at: Vector3, fov := 30.0) -> void:
	cam.fov = fov
	cam.look_at_from_position(from, at)
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "/" + name + ".png")
	print("shot ", name)


func _initialize() -> void:
	_run()


func _run() -> void:
	out = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out)
	var w := Node3D.new()
	root.add_child(w)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.3, 0.31, 0.33)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.7, 0.72)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var we := WorldEnvironment.new()
	we.environment = env
	w.add_child(we)
	var d := DirectionalLight3D.new()
	d.rotation = Vector3(-0.8, 0.7, 0)
	d.light_energy = 1.3
	w.add_child(d)
	A.box(w, Vector3(10, 0.1, 6), Vector3(0, -0.05, 0), "concrete", Color(0.55, 0.55, 0.55), false, 1.0)
	cam = Camera3D.new()
	w.add_child(cam)
	cam.current = true
	var gs := [Color(0, 0, 0, 0), Color(0.5, 0, 0, 0), Color(1, 0, 0, 0), Color(0, 0.6, 0, 0), Color(0, 0, 1, 0), Color(0, 0, 0, 0.6), Color(0.6, 0.3, 0.6, 0.5)]
	var figs := []
	for i in gs.size():
		var f := Node3D.new()
		w.add_child(f)
		f.position = Vector3((i - (gs.size() - 1) / 2.0) * 0.9, 0, 0)
		figs.append(Suit.standing(f))
		await process_frame
		Suit.set_grime(f, gs[i])
	await snap("row_front", Vector3(0, 1.1, -6.6), Vector3(0, 0.95, 0))
	await snap("row_back", Vector3(0, 1.2, 6.6), Vector3(0, 0.95, 0))
	await snap("row_close_legs", Vector3(-0.9, 0.6, -2.4), Vector3(-0.9, 0.45, 0))
	await snap("row_close_top", Vector3(-0.2, 2.4, -1.6), Vector3(-0.45, 1.4, 0))
	for k in [2, 3]:   # mid-stride: the grime stays on the cloth
		var p: Dictionary = figs[k]
		p.thigh_l.rotation = Vector3(-0.6, 0, 0)
		p.shin_l.rotation = Vector3(0.5, 0, 0)
		p.thigh_r.rotation = Vector3(0.4, 0, 0)
		p.shin_r.rotation = Vector3(1.0, 0, 0)
	await snap("stride", Vector3(2.2, 0.9, -2.0), Vector3(-0.5, 0.6, 0), 34.0)
	quit()
