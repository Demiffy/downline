# Draws every fixed image the game makes (src/baked.gd) and writes each to assets/textures/<name>.png:
# every surface kind art.gd knows, the puddle, the grime (every kind and variant), the visor's cracks
# (every tier), the blood (splats and smears). Then `godot --headless --path . --import`, and the game
# reads them instead of drawing them. Run again after changing how any of them is drawn.
# Run: godot --headless --path . -s tools/textures/bake.gd
extends SceneTree
const Baked = preload("res://src/baked.gd")
const A = preload("res://src/art.gd")
const Grime = preload("res://src/grime.gd")
const Cracks = preload("res://src/cracks.gd")
const Blood = preload("res://src/blood.gd")


func _initialize() -> void:
	Baked.bake_to = ProjectSettings.globalize_path(Baked.DIR)
	DirAccess.make_dir_recursive_absolute(Baked.bake_to)
	for kind in _surface_kinds():
		A.texture(kind)
	var holder := Node3D.new()
	root.add_child(holder)
	A.puddle(holder, Vector3.ZERO, 1.0, 0.0)
	holder.free()
	for k in Grime.KINDS:
		for v in Grime.VARIANTS:
			Grime.texture(k, v)
	for tier in [1, 2, 3]:
		Cracks.image(tier)
	for i in 6:
		Blood._make(i)
	for i in 3:
		Blood._make_smear(i)
	print("baked %d images" % DirAccess.get_files_at(Baked.bake_to).size())
	quit()


## Every kind art.gd's _px draws (its match's names).
func _surface_kinds() -> Array[String]:
	var src := FileAccess.get_file_as_string("res://src/art.gd")
	var body := src.substr(src.find("static func _px("))
	body = body.substr(0, body.find("\nstatic func ", 10))
	var out: Array[String] = []
	var re := RegEx.new()
	re.compile("^\\t\\t((?:\"[a-z_0-9]+\"(?:, )?)+):")
	var word := RegEx.new()
	word.compile("\"([a-z_0-9]+)\"")
	for line in body.split("\n"):
		var m := re.search(line)
		if m:
			for w in word.search_all(m.get_string(1)):
				out.append(w.get_string(1))
	return out
