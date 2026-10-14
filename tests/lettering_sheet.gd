# The game's lettering (glyphs.gd, aged by paint.gd) in every style, every character, on a plain wall
# colour. Headless.
# Run: tests/run.sh 120 --headless --path . -s tests/lettering_sheet.gd -- <out.png>
extends SceneTree

const Paint = preload("res://src/paint.gd")
const LINES := ["ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz", "0123456789 .,:;!?'\"-+=/()[]<>*#%&_ · ° ▲", "B.R.M.  DANGER  440 V  ·  No.7  STRONGROOM 7", "CHECKPOINT  HAZMAT  BRM 207  DANGER 600V  RECLAIMED"]


func _initialize() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://lettering.png"
	var rows: Array = []
	for style in ["stencil", "plate", "type", "chalk"]:
		for l in LINES:
			var tex: ImageTexture = Paint.texture(l, style, Color(0.92, 0.9, 0.84) if style != "type" else Color(0.15, 0.15, 0.2), 48)
			rows.append([style, tex.get_image()])
	var W := 0
	var H := 0
	for r in rows:
		W = maxi(W, r[1].get_width())
		H += r[1].get_height()
	var sheet := Image.create(W + 20, H + 20, false, Image.FORMAT_RGBA8)
	var y := 10
	for r in rows:
		var bg := Color(0.82, 0.78, 0.68) if r[0] == "type" else (Color(0.1, 0.13, 0.11) if r[0] == "chalk" else Color(0.33, 0.35, 0.33))
		var img: Image = r[1]
		img.decompress()
		if img.has_mipmaps():
			img.clear_mipmaps()
		sheet.fill_rect(Rect2i(0, y, W + 20, img.get_height()), bg)
		sheet.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(10, y))
		y += img.get_height()
	sheet.save_png(out)
	print("lettering_sheet.gd: saved ", out)
	quit(0)
