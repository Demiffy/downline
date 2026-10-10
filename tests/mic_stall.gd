# The microphone keeps delivering after the game freezes for a few seconds (as when a station is
# built while you're in a crew). Needs a window and a microphone; reads only how much arrives.
# Run: tests/run.sh 60 --path . -s tests/mic_stall.gd [-- nowatch]
extends SceneTree

func _initialize() -> void:
	_run()

func _count(v, secs: float) -> int:
	var got := 0
	var end := Time.get_ticks_msec() + int(secs * 1000)
	while Time.get_ticks_msec() < end:
		await process_frame
		got += v._capture.get_frames_available() if v._capture else 0
	return got

func _run() -> void:
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 20: await process_frame
	var Settings = load("res://src/settings.gd")
	Settings.v.mic_test = true
	var v = main.net.voice
	if v._mic == null:
		print("no microphone input here")
		quit(0)
		return
	var watch: bool = not "nowatch" in OS.get_cmdline_user_args()
	if not watch:
		v.set_process(false)   # (the old behaviour: nothing restarts it; we drain it ourselves)
		v._mic.play()
	var before := 0
	for k in 60:
		await process_frame
		if not watch:
			before += v._capture.get_frames_available()
			v._capture.clear_buffer()
	var fed0: int = v.raw_level * 0.0 + v.mic_restarts
	print("mic playing %s, frames before the freeze (only counted without the watchdog): %d" % [v._mic.playing, before])
	OS.delay_msec(3000)   # a station being built
	var after := 0
	for k in 90:
		await process_frame
		if not watch:
			after += v._capture.get_frames_available()
			v._capture.clear_buffer()
	await create_timer(1.0).timeout
	var fed: int = 0
	if watch:
		var n0: int = v._capture.get_frames_available()
		print("watchdog restarts: %d" % v.mic_restarts)
		var lvl0: float = v.raw_level
		await create_timer(1.0).timeout
		print("mic playing %s, raw level now %.4f, buffers fed %d, restarts %d" % [v._mic.playing, v.raw_level, v.fed, v.mic_restarts])
	else:
		print("frames after the freeze: %d" % after)
	quit(0)
