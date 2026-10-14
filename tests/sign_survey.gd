# Every sign and piece of world text at a stop: whether painted text has something behind it all the
# way across (or hangs off its plate, a wall's end, a doorway), and a photo of each square on, lit as
# the game lights it beside fullbright, eight to a contact sheet. Needs a window. Nothing is merged
# (Engine meta "no_merge"), so every plate and wall behind a sign is there to test against.
# Run: tests/run.sh 900 --path . -s tests/sign_survey.gd -- <out_dir> checkpoint
#      tests/run.sh 900 --path . -s tests/sign_survey.gd -- <out_dir> station <THEME> <BIOME> [LANDMARK|-] [below|above|all]
# Writes <out_dir>/index.txt (every sign: sheet, slot, how much of it hangs off, text, where it's made)
# and <out_dir>/sheet_NN.png.
extends SceneTree

var main
var out := "user://signs"
var cam: Camera3D
const W := 300
const H := 169


func _initialize() -> void:
	_run()


func frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0]
	var where: String = args[1] if args.size() > 1 else "checkpoint"
	DirAccess.make_dir_recursive_absolute(out)
	Engine.set_meta("sign_survey", true)
	Engine.set_meta("no_merge", true)
	Engine.set_meta("fast_test", true)
	Engine.set_meta("test_seed", 11)
	var part := "all"
	if where == "station" and args.size() > 4 and args[4] != "-":
		Engine.set_meta("force_landmark", args[4])
	if args.size() > 5:
		part = args[5]
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await frames(10)
	if where == "station":
		main.term.run("LEAVE_CHECKPOINT")
		var stop: Dictionary = main.route[0][0]
		stop.theme = args[2] if args.size() > 2 else "FACTORY"
		stop.biome = args[3] if args.size() > 3 else "DESERT"
		stop.weather = "CLEAR"
		stop.erase("landmark")
		if stop.theme == "DAM":
			stop.landmark = "DAM"
			stop.name = "HOLLOW CREEK"
		stop.rooms = 18
		main.player.global_position = Vector3(0, 1.3, 0)
		main.term.run("ROUTE_TO " + stop.letter)
		while main.busy:
			await process_frame
	Engine.remove_meta("fast_test")
	main.hours = 12.0
	main.hud.visible = false
	main.player.process_mode = Node.PROCESS_MODE_DISABLED
	for n in get_nodes_in_group("monsters"):
		n.queue_free()
	await frames(5)
	cam = Camera3D.new()
	cam.far = 400.0
	root.add_child(cam)
	cam.make_current()
	# Everything that could stand behind a sign: every other mesh's box, in a 4 m grid.
	var grid := {}
	for m: MeshInstance3D in main.find_children("*", "MeshInstance3D", true, false):
		if m.has_meta("paint") or not m.is_visible_in_tree() or m.mesh == null:
			continue
		var bb := m.global_transform * m.get_aabb()
		if bb.size.x > 60.0 or bb.size.z > 60.0 or bb.size.y > 60.0:
			continue   # (the ground: its box is mostly air)
		for gx in range(floori(bb.position.x / 4.0), floori(bb.end.x / 4.0) + 1):
			for gz in range(floori(bb.position.z / 4.0), floori(bb.end.z / 4.0) + 1):
				var k := Vector2i(gx, gz)
				if not grid.has(k):
					grid[k] = []
				grid[k].append(bb.grow(0.006))
	var signs: Array = []
	for n in main.find_children("*", "", true, false):
		if not (n is Node3D) or not (n as Node3D).is_visible_in_tree():
			continue
		if n.has_meta("paint") or (n is Label3D and n.get_parent() != null):
			var y: float = (n as Node3D).global_position.y
			if part == "below" and y > -20.0 or part == "above" and y < -20.0:
				continue
			signs.append(n)
	# Two of each (the same line of code makes the same kind of sign), and every one that hangs off.
	var seen := {}
	var keep: Array = []
	for sg in signs:
		var key: String = sg.get_meta("src", "(Label3D) " + str(sg.get_parent().name))
		seen[key] = seen.get(key, 0) + 1
		if seen[key] <= 2 or (sg.has_meta("paint") and (_check(sg, _size(sg), grid)[0] > 0.0 or _check(sg, _size(sg), grid)[1] > 0.0)):
			keep.append(sg)
	print("sign_survey.gd: %d signs from %d places, %d to photograph" % [signs.size(), seen.size(), keep.size()])
	signs = keep
	var lines := PackedStringArray()
	var bad := 0
	var sheet := Image.create(W * 4 + 6, H * 4 + 6, false, Image.FORMAT_RGB8)
	var sheet_n := 0
	for i in signs.size():
		var s: Node3D = signs[i]
		var size := _size(s)
		var off := 0.0
		var spill := 0.0
		var plate := Vector2.ZERO
		if s.has_meta("paint"):
			var r: Array = _check(s, size, grid)
			off = r[0]
			spill = r[1]
			plate = r[2]
			if off > 0.0 or spill > 0.0:
				bad += 1
		var text: String = String(s.get_meta("paint")) if s.has_meta("paint") else (s as Label3D).text
		var slot := i % 8
		var flag := ("OFF %3d%%" % roundi(off * 100.0)) if off > 0.0 else (("SPILL %2d%%" % roundi(spill * 100.0)) if spill > 0.0 else "")
		lines.append("%02d.%d  %-9s  %-40s  %-22s  %s" % [i / 8, slot, flag, text.replace("\n", " / ").left(40), s.get_meta("src", "(Label3D)"), ("text %.2fx%.2f on %.2fx%.2f" % [size.x, size.y, plate.x, plate.y]) if plate != Vector2.ZERO else ""])
		# Square on: back along its face's normal far enough to take it in, a little to one side.
		var n: Vector3 = s.global_basis.z.normalized()
		var d := clampf(maxf(size.x * 1.1, size.y * 2.4), 0.8, 9.0)
		var at := s.global_position
		cam.global_position = at + n * d + Vector3(0, 0.05, 0)
		if absf(n.dot(Vector3.UP)) > 0.95:
			cam.look_at(at, Vector3.FORWARD)
		else:
			cam.look_at(at, Vector3.UP)
		for lit in [true, false]:
			get_root().debug_draw = Viewport.DEBUG_DRAW_DISABLED if lit else Viewport.DEBUG_DRAW_UNSHADED
			await frames(3)
			await RenderingServer.frame_post_draw
			var img := get_root().get_texture().get_image()
			img.resize(W, H, Image.INTERPOLATE_BILINEAR)
			img.convert(Image.FORMAT_RGB8)
			var cx := (slot % 2) * (W * 2 + 6) + (0 if lit else W)
			var cy := (slot / 2) * H
			sheet.blit_rect(img, Rect2i(0, 0, W, H), Vector2i(cx, cy))
			if off > 0.0 or spill > 0.0:   # (a bar along the top: red, it hangs off into nothing; amber, it spills off its plate)
				sheet.fill_rect(Rect2i(cx, cy, W, 5), Color(1, 0.1, 0.05) if off > 0.0 else Color(1, 0.7, 0.1))
		if slot == 7 or i == signs.size() - 1:
			sheet.save_png("%s/sheet_%02d.png" % [out, sheet_n])
			sheet_n += 1
			sheet.fill(Color.BLACK)
	get_root().debug_draw = Viewport.DEBUG_DRAW_DISABLED
	var f := FileAccess.open(out + "/index.txt", FileAccess.WRITE)
	f.store_string("%d signs, %d hang off or spill off their plate\n%s\n" % [signs.size(), bad, "\n".join(lines)])
	f.close()
	print("sign_survey.gd: %d signs, %d hang off something, %d sheets" % [signs.size(), bad, sheet_n])
	quit(0)


## A sign's width and height in metres.
func _size(s: Node3D) -> Vector2:
	if s is MeshInstance3D and (s as MeshInstance3D).mesh is QuadMesh:
		var q: Vector2 = ((s as MeshInstance3D).mesh as QuadMesh).size
		return Vector2(q.x * s.global_basis.x.length(), q.y * s.global_basis.y.length())
	var bb := (s as VisualInstance3D).get_aabb()
	return Vector2(bb.size.x, bb.size.y) * s.global_basis.get_scale().x


## [how much of a painted sign's lettering has nothing behind it, how much is off the plate it's on (the
## smallest thing right behind its middle), that plate's face (w, h)]: points across the lettered middle
## (the image's padding left off), each looked for just behind.
func _check(s: MeshInstance3D, size: Vector2, grid: Dictionary) -> Array:
	var tex: Texture2D = (s.material_override as StandardMaterial3D).albedo_texture
	var pad := 14.0   # (paint.gd: 0.3 of its 48 px)
	var fx := 0.5 - pad / tex.get_width()
	var fy := 0.5 - pad / tex.get_height()
	var n: Vector3 = s.global_basis.z.normalized()
	var ax: Vector3 = s.global_basis.x.normalized()
	var ay: Vector3 = s.global_basis.y.normalized()
	var rx: Vector3 = ax * size.x
	var ry: Vector3 = ay * size.y
	var behind := func(p: Vector3) -> Array:   # every box just behind p
		var hit: Array = []
		for t in [0.004, 0.02, 0.05, 0.12]:
			var q: Vector3 = p - n * t
			for bb: AABB in grid.get(Vector2i(floori(q.x / 4.0), floori(q.z / 4.0)), []):
				if bb.has_point(q) and not bb in hit:
					hit.append(bb)
			if not hit.is_empty():
				return hit
		return hit
	var face_of := func(bb: AABB) -> Vector2: return Vector2(absf(bb.size.dot(ax.abs())), absf(bb.size.dot(ay.abs())))
	var hits: Array = []
	var miss := 0
	for u in [-1.0, -0.5, 0.0, 0.5, 1.0]:
		for v in [-1.0, 0.0, 1.0]:
			var h: Array = behind.call(s.global_position + rx * fx * u * 0.95 + ry * fy * v * 0.9)
			hits.append(h)
			if h.is_empty():
				miss += 1
	# Its plate: a thin panel right behind the middle, not much smaller than the lettering (a rib or a
	# sill it happens to cross isn't one); else whatever's behind the most of it.
	var lettered := Vector2(size.x * fx * 2.0, size.y * fy * 2.0)
	var plate = null
	for bb: AABB in behind.call(s.global_position):
		var f: Vector2 = face_of.call(bb)
		var depth := absf(bb.size.dot(n.abs()))
		if depth < 0.15 and f.x * f.y >= lettered.x * lettered.y * 0.25 and (plate == null or bb.get_volume() < plate.get_volume()):
			plate = bb
	if plate == null:
		var count := {}
		for h: Array in hits:
			for bb: AABB in h:
				count[bb] = count.get(bb, 0) + 1
		for bb in count:
			if plate == null or count[bb] > count[plate]:
				plate = bb
	var spill := 0
	for h: Array in hits:
		if not h.is_empty() and plate != null and not plate in h:
			spill += 1
	return [float(miss) / hits.size(), float(spill) / hits.size(), face_of.call(plate) if plate != null else Vector2.ZERO]
