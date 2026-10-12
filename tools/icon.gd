# Renders the game's mark (src/mark.gd) to a PNG for the exports' application/icon: the Windows
# export turns it into the .exe's .ico, the macOS export into the .app's .icns.
# Run: godot --headless --path . -s tools/icon.gd -- build/icon.png
extends SceneTree

func _initialize() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "build/icon.png"
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	var err: int = preload("res://src/mark.gd").image(1024).save_png(out)
	print("icon: %s (%s)" % [out, error_string(err)])
	quit(err)
