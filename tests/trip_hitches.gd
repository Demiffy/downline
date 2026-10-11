# Rides two trips in real time and prints the worst frames (the hitches) on each: the next stop
# is built a slice a frame on the way, so none should be long. Needs a window.
# Run: tests/run.sh 300 --path . -s tests/trip_hitches.gd
extends SceneTree
func _initialize() -> void:
	_run()
func _run() -> void:
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 30:
		await process_frame
	main.hud.visible = false
	main.term.run("LEAVE_CHECKPOINT")
	for trip in 2:
		main.term.run("ROUTE_TO " + main.route[trip][0].letter)
		while not main.line.riding:
			await process_frame
		var worst := []
		var last := Time.get_ticks_usec()
		var frames := 0
		var t0 := Time.get_ticks_msec()
		while main.busy:
			await process_frame
			var now := Time.get_ticks_usec()
			var ms := (now - last) / 1000.0
			last = now
			frames += 1
			worst.append([ms, main.line.s, main.line.v, main.level_building])
		worst.sort_custom(func(a, b): return a[0] > b[0])
		print("TRIP %d: %.1f s, %d frames, avg %.1f ms" % [trip, (Time.get_ticks_msec() - t0) / 1000.0, frames, (Time.get_ticks_msec() - t0) / float(frames)])
		for w in worst.slice(0, 8):
			print("  %.1f ms at s=%.0f v=%.1f building=%s" % w)
	quit()
