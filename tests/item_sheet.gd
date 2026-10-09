# Every item's model on a turntable: four views each (front, side, back, from above), framed to its
# size, against a plain sky, its id underneath. Contact sheets of 6 items. Needs a window.
# Run: tests/run.sh 300 --path . -s tests/item_sheet.gd -- <out_dir> [ID ...]
extends SceneTree

const Data = preload("res://src/data.gd")
const Items = preload("res://src/items.gd")

const CELL := 260
const PER_SHEET := 6
const VIEWS := [Vector2(0.35, -0.3), Vector2(1.9, -0.25), Vector2(3.5, -0.3), Vector2(0.8, -1.2)]   # (yaw, pitch)

var out := "user://items"
var vp: SubViewport
var cam: Camera3D
var label: Label
var holder: Node3D


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	var only: Array = args.slice(1)
	_run(only)


func _setup() -> void:
	vp = SubViewport.new()
	vp.size = Vector2i(CELL, CELL)
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.68, 0.82)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.78, 0.85)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.6, 0)
	sun.light_energy = 1.3
	vp.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(-0.3, 2.8, 0)
	fill.light_energy = 0.45
	vp.add_child(fill)
	cam = Camera3D.new()
	cam.fov = 35.0
	vp.add_child(cam)
	holder = Node3D.new()
	vp.add_child(holder)
	label = Label.new()
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(0.05, 0.05, 0.08))
	label.position = Vector2(6, CELL - 22)
	vp.add_child(label)


## The visual bounds of everything under n, in n's space.
func _bounds(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or not mi.visible:
			continue
		var xf: Transform3D = n.global_transform.affine_inverse() * mi.global_transform
		var b: AABB = xf * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _run(only: Array) -> void:
	_setup()
	await process_frame
	var ids: Array = only if not only.is_empty() else Data.ITEMS.keys()
	var sheet: Image = null
	var n := 0
	var sheet_i := 0
	var listing := PackedStringArray()
	for id in ids:
		for c in holder.get_children():
			c.free()
		var m: Node3D = Items.build(id)
		holder.add_child(m)
		await process_frame
		var b := _bounds(m)
		var centre := b.get_center()
		var r := maxf(b.size.length() * 0.5, 0.03)
		var dist := r / tan(deg_to_rad(cam.fov * 0.5)) * 1.15
		if sheet == null:
			sheet = Image.create(CELL * VIEWS.size(), CELL * PER_SHEET, false, Image.FORMAT_RGB8)
		label.text = "%s  %.2f x %.2f x %.2f" % [id, b.size.x, b.size.y, b.size.z]
		for v in VIEWS.size():
			var yaw: float = VIEWS[v].x
			var pitch: float = VIEWS[v].y
			var dir := Vector3(sin(yaw) * cos(pitch), -sin(pitch), cos(yaw) * cos(pitch))
			cam.look_at_from_position(centre + dir * dist, centre, Vector3.UP if absf(pitch) < 1.4 else Vector3.FORWARD)
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var img := vp.get_texture().get_image()
			img.convert(Image.FORMAT_RGB8)
			sheet.blit_rect(img, Rect2i(0, 0, CELL, CELL), Vector2i(v * CELL, n * CELL))
		listing.append("%d.%d %s" % [sheet_i, n, id])
		n += 1
		if n == PER_SHEET:
			sheet.save_png("%s/items_%02d.png" % [out, sheet_i])
			sheet = null
			n = 0
			sheet_i += 1
	if sheet != null:
		sheet.save_png("%s/items_%02d.png" % [out, sheet_i])
	FileAccess.open(out + "/listing.txt", FileAccess.WRITE).store_string("\n".join(listing))
	print("sheets: %d" % (sheet_i + 1))
	quit(0)
