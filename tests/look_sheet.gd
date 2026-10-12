# Crew looks side by side (suit.gd's options), front, back and three-quarter, then each option list
# on its own (every choice of it on the Bureau's issue), each a sheet. Needs a window.
# Run: tests/run.sh 200 --path . -s tests/look_sheet.gd -- <out_dir> [slot ...]
extends SceneTree

const Suit = preload("res://src/suit.gd")
const A = preload("res://src/art.gd")

var cam: Camera3D
var out := ""


func _initialize() -> void:
	_run()


func row(w: Node3D, looks: Array, names: Array) -> Array:
	var figs := []
	for i in looks.size():
		var f := Node3D.new()
		w.add_child(f)
		f.position = Vector3((i - (looks.size() - 1) / 2.0) * 0.9, 0, 0)
		Suit.standing(f)
		Suit.apply_look(f, looks[i], names[i] if i < names.size() else "EMPLOYEE")
		figs.append(f)
	return figs


func snap(name: String, from: Vector3, at: Vector3, fov: float) -> void:
	cam.fov = fov
	cam.look_at_from_position(from, at)
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "/" + name + ".png")
	print("sheet ", name)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0]
	var only: Array = args.slice(1)
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
	for l in [[Vector3(-0.8, 0.7, 0), 1.3], [Vector3(-0.4, -2.6, 0), 0.6], [Vector3(-0.3, 2.2, 0), 0.5]]:
		var d := DirectionalLight3D.new()
		d.rotation = l[0]
		d.light_energy = l[1]
		w.add_child(d)
	A.box(w, Vector3(14, 0.1, 6), Vector3(0, -0.05, 0), "concrete", Color(0.55, 0.55, 0.55), false, 1.0)
	cam = Camera3D.new()
	w.add_child(cam)
	cam.current = true
	await process_frame
	var sets := {}
	if only.is_empty() or "mixed" in only:
		sets["mixed"] = [[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], [1, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1], [3, 4, 3, 2, 2, 2, 2, 2, 2, 2, 2], [5, 5, 6, 5, 3, 4, 3, 3, 0, 3, 0],
			[7, 8, 8, 4, 4, 5, 4, 4, 1, 4, 1], [10, 9, 7, 3, 1, 0, 1, 0, 2, 0, 2], [13, 11, 4, 1, 0, 3, 0, 2, 0, 1, 1]]
	var lists := Suit.lists()
	for slot in Suit.LOOK:
		if only.is_empty() or slot in only:
			var looks := []
			for i in lists[slot].size():
				var l := []
				l.resize(Suit.LOOK.size())
				l.fill(0)
				l[Suit.LOOK.find(slot)] = i
				looks.append(l)
			sets[slot] = looks
	for name in sets:
		var looks: Array = sets[name]
		var figs := row(w, looks, ["EMPLOYEE", "VASQUEZ", "OKONKWO", "LI", "BRENNAN", "SATO", "ADEYEMI", "NOVAK", "HALL", "RUIZ", "KOVAC", "PARK", "DUBOIS", "ANDERSEN"])
		var span := looks.size() * 0.9
		var d := maxf(4.0, span * 1.25)
		await snap(name + "_front", Vector3(0, 1.1, -d), Vector3(0, 0.95, 0), 28.0)
		await snap(name + "_back", Vector3(0, 1.3, d), Vector3(0, 0.95, 0), 28.0)
		await snap(name + "_34", Vector3(-d * 0.7, 1.4, -d * 0.7), Vector3(0, 0.95, 0), 28.0)
		if name in ["mixed", "style", "mark", "helmet", "visor"]:   # heads, close
			await snap(name + "_heads", Vector3(0, 1.75, -span * 1.0), Vector3(0, 1.65, 0), 28.0)
			await snap(name + "_heads_back", Vector3(0, 1.85, span * 1.0), Vector3(0, 1.65, 0), 28.0)
		for f in figs:
			f.queue_free()
		await process_frame
	quit()
