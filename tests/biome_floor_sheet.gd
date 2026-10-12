# A sheet per biome of what you walk on: the ground and rock textures flat (as tinted on the line),
# then the real thing in the playground rebuilt as that biome: the ground at your feet, and the view.
# Needs a window. Run: tests/run.sh 400 --path . -s tests/biome_floor_sheet.gd -- <dir> playground
extends SceneTree

const A = preload("res://src/art.gd")
const Data = preload("res://src/data.gd")
const W := 640
const H := 400

var main
var pg


func _initialize() -> void:
	_run()


func press(page: String, label: String) -> void:
	for c in pg._pages[page].find_children("*", "Button", true, false):
		if (c as Button).text == label:
			c.pressed.emit()
	for i in 6:
		await process_frame
	while not pg._ready_done or main.busy:
		await process_frame


func grab() -> Image:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.resize(W, H)
	return img


## A texture as a flat swatch: tiled 3x, tinted.
func swatch(kind: String, tint: Color) -> Image:
	var t: Image = A.texture(kind).get_image()
	t.decompress()
	t.convert(Image.FORMAT_RGBA8)
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	var tw := t.get_width()
	var th := t.get_height()
	var scale := 3.0 * tw / W
	for y in H:
		for x in W:
			var c := t.get_pixel(int(x * scale) % tw, int(y * scale) % th)
			img.set_pixel(x, y, Color(c.r * tint.r, c.g * tint.g, c.b * tint.b))
	return img


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
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
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.fov = 70
	for b in Data.BIOMES:
		await press("SITES", b)
		main.hours = 12.0
		for i in 90:
			await process_frame
		main.hud.visible = false
		pg.strip.visible = false
		var bio: Dictionary = Data.BIOMES[b]
		var sheet := Image.create(W * 2, H * 2, false, Image.FORMAT_RGBA8)
		sheet.blit_rect(swatch(bio.ground, Color.WHITE), Rect2i(0, 0, W, H), Vector2i(0, 0))
		sheet.blit_rect(swatch(bio.rock, bio.rock_tint), Rect2i(0, 0, W, H), Vector2i(W, 0))
		var lv = main.level   # (out in the open country beside the station, away from its buildings)
		var gy := func(x: float, z: float) -> float: return lv.ground_y(x, z)
		var at := Vector3(10.0, 0.0, 55.0)
		at.y = gy.call(at.x, at.z)
		var look := Vector3(10.0, 0.0, 61.0)
		look.y = gy.call(look.x, look.z)
		cam.current = true
		cam.global_position = lv.to_global(at + Vector3(0, 1.7, 0))
		cam.look_at(lv.to_global(look))
		var close := await grab()
		var far := Vector3(-30.0, 0.0, 140.0)
		far.y = gy.call(far.x, far.z)
		cam.global_position = lv.to_global(at + Vector3(0, 3.0, 0))
		cam.look_at(lv.to_global(far + Vector3(0, 2.0, 0)))
		var wide := await grab()
		close.convert(Image.FORMAT_RGBA8)
		wide.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(close, Rect2i(0, 0, W, H), Vector2i(0, H))
		sheet.blit_rect(wide, Rect2i(0, 0, W, H), Vector2i(W, H))
		sheet.save_png(out + "/" + b.to_lower() + ".png")
		print("sheet ", b)
		cam.current = false
		main.player.cam.current = true
	quit()
