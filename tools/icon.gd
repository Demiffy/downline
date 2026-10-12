# Renders the game's mark (src/mark.gd) to a PNG for the exports' application/icon: the Windows
# export turns it into the .exe's .ico; icon_mac.png (the same, inside Apple's margin) the .app's .icns.
# Run: godot --headless --path . -s tools/icon.gd -- build/icon.png
extends SceneTree

func _initialize() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "build/icon.png"
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	var mark = preload("res://src/mark.gd")
	var err: int = mark.image(1024).save_png(out)
	var mac := out.get_base_dir().path_join("icon_mac.png")   # (the .app's: with Apple's margin round the tile)
	err = maxi(err, mark.mac_image(1024).save_png(mac))
	print("icon: %s, %s (%s)" % [out, mac, error_string(err)])
	quit(err)
