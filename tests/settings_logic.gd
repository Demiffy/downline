# Settings without a screen: rebinding (and swapping a key that's taken), quality presets turning
# CUSTOM and back, an old settings file read the new way, the settings screen built and reset.
# Run: tests/run.sh 60 --headless --path . -s tests/settings_logic.gd
extends SceneTree

const Settings = preload("res://src/settings.gd")
var fails := 0


func check(cond: bool, what: String) -> void:
	print(("ok    " if cond else "FAIL  ") + what)
	if not cond:
		fails += 1


func _initialize() -> void:
	_run()


func _run() -> void:
	var keep := Settings.v.duplicate(true)
	Settings.v = Settings.DEFAULTS.duplicate(true)
	Settings.apply_binds()
	check(InputMap.action_has_event("headlamp", Settings.bind_event("headlamp")) and Settings.key_name("headlamp") == "T", "headlamp is an action, on T")
	# The screen: rebind JUMP to E (USE's key): they swap.
	var Menu = load("res://src/menu.gd")
	var m = Menu.new()
	var ui = load("res://src/settings_ui.gd").new()
	ui.m = m
	root.add_child(ui)
	await process_frame
	ui._bind("jump", {"k": KEY_E})
	check(Settings.key_name("jump") == "E" and Settings.key_name("interact") == "SPACE", "a key that's taken swaps (jump E, use SPACE)")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_E
	check(InputMap.event_is_action(ev, "jump") and not InputMap.event_is_action(ev, "interact"), "the input map follows")
	ui._bind("jump", {"k": KEY_SPACE})
	check(Settings.v.binds.is_empty(), "swapped back to the defaults: nothing custom left (%s)" % str(Settings.v.binds))
	ui._bind("scan", {"m": MOUSE_BUTTON_XBUTTON1})
	check(Settings.key_name("scan") == "MOUSE 4", "a mouse button can be bound (%s)" % Settings.key_name("scan"))
	# Presets.
	Settings.use_preset(0)
	check(Settings.v.render_scale < 0.7 and not Settings.v.ssao, "LOW turns things down")
	Settings.v.ssao = true
	Settings.match_preset()
	check(Settings.QUALITY[Settings.v.quality] == "CUSTOM", "changing one by hand makes it CUSTOM")
	Settings.v.ssao = false
	Settings.match_preset()
	check(Settings.v.quality == 0, "...and back to LOW when it matches again")
	# RESET TAB on controls clears the binds.
	ui._tab = "CONTROLS"
	ui._reset_tab()
	check(Settings.v.binds.is_empty() and Settings.key_name("scan") == "F", "RESET TAB puts the keys back")
	# An old settings file (fullscreen on, quality MEDIUM, no new keys).
	var path := "user://settings_old_test.cfg"
	var cf := ConfigFile.new()
	cf.set_value("settings", "fullscreen", true)
	cf.set_value("settings", "quality", 1)
	cf.set_value("settings", "sens", 1.7)
	cf.save(path)
	Settings.v = Settings.DEFAULTS.duplicate(true)
	Settings.load_file(path)
	check(Settings.v.window_mode == 1 and is_equal_approx(Settings.v.render_scale, 0.85) and is_equal_approx(Settings.v.sens, 1.7), "an old file: fullscreen, MEDIUM's settings, its sensitivity kept")
	DirAccess.remove_absolute(path)
	Settings.v = keep
	Settings.apply_binds()
	ui.queue_free()
	m.free()
	print("settings_logic.gd: ", "ALL PASSED" if fails == 0 else "%d FAILED" % fails)
	quit(1 if fails else 0)
