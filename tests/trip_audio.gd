# Rides one trip in real time with the mix recorded off Master: prints each second's peak and loudness
# (and how many samples clipped) with where the train was, and saves the whole trip as a .wav.
# Needs a window and an audio device. Run: tests/run.sh 200 --path . -s tests/trip_audio.gd -- <out.wav> [inside|outside]
extends SceneTree
func _initialize() -> void:
	_run()
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 30:
		await process_frame
	main.hud.visible = false
	if args.size() > 1 and args[1] == "outside":
		main.player.global_position = main.train.to_global(Vector3(-4, 1.3, 3.2))   # (out on the flatcar)
	main.term.run("LEAVE_CHECKPOINT")
	var rec := AudioEffectRecord.new()
	AudioServer.add_bus_effect(0, rec)
	main.term.run("ROUTE_TO " + main.route[0][0].letter)
	while not main.line.riding:
		await process_frame
	rec.set_recording_active(true)
	var marks := []
	var t0 := Time.get_ticks_msec()
	while main.busy:
		await process_frame
		marks.append([(Time.get_ticks_msec() - t0) / 1000.0, main.line.s, main.line.v, main.line.dark, main.train.notch])
	rec.set_recording_active(false)
	var w := rec.get_recording()
	w.save_to_wav(args[0] if args.size() > 0 else "user://trip.wav")
	var d := w.data   # 16-bit stereo
	var rate := w.mix_rate
	var n := d.size() / 4
	var sec := 0
	while sec * rate < n:
		var pk := 0.0
		var sq := 0.0
		var clip := 0
		var m := mini(rate, n - sec * rate)
		for i in m:
			var j: int = (sec * rate + i) * 4
			var v := maxf(absf(d.decode_s16(j)), absf(d.decode_s16(j + 2))) / 32768.0
			pk = maxf(pk, v)
			sq += v * v
			if v > 0.99:
				clip += 1
		var at = marks[mini(marks.size() - 1, marks.bsearch_custom(float(sec), func(a, b): return a[0] < b))]
		print("t=%3d s=%5.0f v=%4.1f dark=%.2f notch=%d  peak=%5.1f dB rms=%5.1f dB clipped=%d" % [sec, at[1], at[2], at[3], at[4], linear_to_db(pk), linear_to_db(sqrt(sq / m)), clip])
		sec += 1
	quit()
