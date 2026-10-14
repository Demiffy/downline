# Images that come out the same every time, kept as files (assets/textures/<name>.png) so they aren't
# drawn pixel by pixel in the middle of play: the surfaces' textures, the walls' grime, the visor's
# cracks, blood. Each is drawn by its own code here, once, by tools/textures/bake.gd; the game then
# reads the file and carries on exactly as if it had drawn it (mipmaps and all, done after, as before).
# A name with no file yet (a new kind) is just drawn, as it always was.
extends RefCounted

const DIR := "res://assets/textures/"
static var bake_to := ""   # (tools/textures/bake.gd: draw everything, and write it here)


static func image(name: String, draw: Callable) -> Image:
	var path := DIR + name + ".png"
	if bake_to == "" and ResourceLoader.exists(path):
		var t: Texture2D = load(path)
		var img := t.get_image()
		if img.get_format() != Image.FORMAT_RGBA8 and img.get_format() != Image.FORMAT_RGB8:
			img.convert(Image.FORMAT_RGBA8)
		return img
	var drawn: Image = draw.call()
	if bake_to != "":
		drawn.save_png(bake_to.path_join(name + ".png"))
	return drawn
