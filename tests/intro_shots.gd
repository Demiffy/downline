# Frames of the startup intro (src/intro.gd), with a made-up update coming in. Needs a window.
# Run: godot --path . -s tests/intro_shots.gd -- <out_dir>
extends SceneTree

const Intro = preload("res://src/intro.gd")
var out := "user://shots"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	_run()


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("saved ", name)


func wait(secs: float) -> void:
	await create_timer(secs).timeout


func _run() -> void:
	var bg := Control.new()
	root.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var it = Intro.new()
	it.full = true
	bg.add_child(it)
	var ended := [false]
	it.done.connect(func(): ended[0] = true)
	it.line("head", "RAILNET FIELD SERVICE OS  4.7", "", false)
	it.line("head", "(C) BUREAU OF RECLAIMED MATERIALS", "", false)
	it.line("", "", "", false)
	it.line("mem", "MEMORY CHECK", "16760820K OK")
	it.line("gpu", "VIDEO", "AMD RADEON RX 6750 XT")
	it.line("radio", "RADIO", "OK")
	it.line("track", "TRACK CIRCUIT", "OK")
	it.line("dispatch", "CONTACTING DISPATCH", null)
	it.line("build", "BUILD 2fd1522", null)
	await wait(0.08)
	await shot("i0_power")
	await wait(0.2)
	await shot("i1_power")
	await wait(1.6)
	await shot("i2_term")
	it.status("dispatch", "NEW ORDERS: BUILD a1b2c3d")
	it.line("orders", "RECEIVING", null, true, "build")
	it.progress("orders", 0.0, "RECEIVING")
	for i in 10:
		await wait(0.12)
		it.progress("orders", i / 10.0, "RECEIVING %.1f/1.0 MB" % (i / 10.0))
	await shot("i3_download")
	it.status("orders", "INSTALLED", "RECEIVED")
	it.status("build", "READY", "BUILD a1b2c3d")
	it.release()
	await wait(1.2)
	await shot("i4_term_done")
	var t := 0.0
	var k := 0
	for at in [0.35, 0.7, 1.05, 1.4, 1.75, 2.1, 2.6, 3.2]:
		await wait(at - t)
		t = at
		await shot("i5_logo_%d" % k)
		k += 1
	while not ended[0]:
		await process_frame
	print("done after the logo")
	quit()
