# Every item in hand: first person (the lower right of the screen) and held by a crewmate (side
# on), on the lit checkpoint yard. Contact sheets of 12 per page. Needs a window.
# Run: tests/run.sh 900 --path . -s tests/hand_sheet.gd -- <out_dir> [ID ...]
extends SceneTree

const Data = preload("res://src/data.gd")
const Puppet = preload("res://src/puppet.gd")

const W := 400
const H := 300
const FW := 480
const FH := 232
const COLS := 4
const ROWS := 3

var main
var out := "user://hands"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	_run(args.slice(1))


func frames(n: int) -> void:
	for i in n:
		await process_frame


func grab() -> Image:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	return img


func _run(only: Array) -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await frames(30)
	for n in main.get_children():
		if n.has_method("_show_title"):
			n.queue_free()
	main.hud.visible = false
	var p = main.player
	p.set_physics_process(false)
	p.frozen = true
	p.global_position = Vector3(-6.0, 0.06, 8.0)
	p.rotation.y = PI / 2.0   # looking along -x
	p.head.rotation.x = -0.1
	var pup := Puppet.new()
	pup.main = main
	pup.net = main.net
	pup.peer = 77
	pup.display_name = "CREW"
	main.add_child(pup)
	var pup_at := Vector3(-8.1, 0.06, 8.0)
	var ids: Array = only if not only.is_empty() else Data.ITEMS.keys().filter(func(i): return Data.kind(i) != "photo" or true)
	var fp: Image = null
	var tp: Image = null
	var n := 0
	var page := 0
	var font_note := PackedStringArray()
	for id in ids:
		p.slots[0] = {"id": id, "charge": 100.0, "extra": {}}
		p.sel = 0
		p.light_on = false
		pup.set_pose(["W", pup_at, PI, -0.3, 1.8, id, false, false, false, false, main.level_serial, true])
		await frames(25)
		var img := await grab()
		if OS.has_environment("HS_DEBUG"):
			img.save_png("%s/full_%s.png" % [out, id])
			for mi in main.find_children("*", "MeshInstance3D", true, false):
				if mi.is_visible_in_tree() and mi.mesh != null and not p.is_ancestor_of(mi) and (mi.global_transform * mi.mesh.get_aabb()).get_center().distance_to(p.cam.global_position) < 1.5:
					print("NEAR ", id, " ", mi.get_path(), " ", mi.mesh.get_class(), " ", mi.global_position)
		var vs := img.get_size()
		if fp == null:
			fp = Image.create(FW * COLS, FH * ROWS, false, Image.FORMAT_RGB8)
			tp = Image.create(W * COLS, H * ROWS, false, Image.FORMAT_RGB8)
		var c := img.get_region(Rect2i(vs.x / 8, vs.y / 4, vs.x * 7 / 8, vs.y * 3 / 4))
		c.resize(FW, FH)
		fp.blit_rect(c, Rect2i(0, 0, FW, FH), Vector2i((n % COLS) * FW, (n / COLS) * FH))
		# The crewmate, close and side on, without our own hand in the way.
		p.arm.visible = false
		await frames(3)
		img = await grab()
		p.arm.visible = true
		var cam: Camera3D = root.get_viewport().get_camera_3d()
		var sp := cam.unproject_position(pup.global_position + Vector3(0, 1.1, 0))
		var half := Vector2i(int(vs.y * 0.28 * 4.0 / 3.0), int(vs.y * 0.28))
		var rect := Rect2i(Vector2i(sp) - half, half * 2).intersection(Rect2i(Vector2i.ZERO, vs))
		var c2 := img.get_region(rect)
		c2.resize(W, H)
		tp.blit_rect(c2, Rect2i(0, 0, W, H), Vector2i((n % COLS) * W, (n / COLS) * H))
		font_note.append("%d.%d %s" % [page, n, id])
		n += 1
		if n == COLS * ROWS:
			fp.save_png("%s/fp_%02d.png" % [out, page])
			tp.save_png("%s/crew_%02d.png" % [out, page])
			fp = null
			n = 0
			page += 1
	if fp != null:
		fp.save_png("%s/fp_%02d.png" % [out, page])
		tp.save_png("%s/crew_%02d.png" % [out, page])
	FileAccess.open(out + "/listing.txt", FileAccess.WRITE).store_string("\n".join(font_note))
	print("pages: %d" % (page + 1))
	quit(0)
