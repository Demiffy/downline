# Does the microphone keep delivering after it's restarted? Needs a window and a microphone.
extends SceneTree
func _initialize() -> void:
	_run()
func _run() -> void:
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 20: await process_frame
	load("res://src/settings.gd").v.mic_test = true
	var v = main.net.voice
	if v._mic == null:
		print("no microphone input here")
		quit(0)
		return
	await create_timer(1.5).timeout
	var a: int = v.fed
	await create_timer(2.0).timeout
	print("before: %d buffers in 2 s" % (v.fed - a))
	v._restart_mic()
	await create_timer(0.5).timeout
	var b: int = v.fed
	await create_timer(2.0).timeout
	print("after a restart: %d buffers in 2 s (restarts %d)" % [v.fed - b, v.mic_restarts])
	quit(0)
