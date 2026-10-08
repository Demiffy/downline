# Voice playback on one machine: frames "arrive" from a crewmate standing a few metres away and
# must come out of the Voice bus (measured at the bus meter), from the very first game (the Net hub
# is made after main, so voice.main has to be set late; once it wasn't, and nobody heard anybody).
# Run: tests/run.sh 120 --headless --path . -s tests/voice_play.gd
extends SceneTree

const Voice = preload("res://src/voice.gd")
const Puppet = preload("res://src/puppet.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	print(("ok    " if cond else "FAIL  ") + what)
	if not cond:
		fails += 1


func _initialize() -> void:
	_run()


func _run() -> void:
	Engine.set_meta("fast_test", true)
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame
	var v = main.net.voice
	check(v.main == main, "the voice knows the game it's in")
	var pup := Puppet.new()
	pup.main = main
	pup.net = main.net
	pup.peer = 99
	pup.display_name = "TALKY"
	main.add_child(pup)
	v.attach_puppet(99, pup)
	var bus := AudioServer.get_bus_index("Voice")
	var peak := -200.0
	var phase := 0.0
	for k in 120:   # 2.4 s of a 300 Hz tone, at the pace it's spoken
		var f := PackedFloat32Array()
		for i in Voice.FRAME:
			f.append(sin(phase) * 0.4)
			phase += TAU * 300.0 / Voice.RATE
		v.receive(99, Voice.packet(k, f))
		await create_timer(0.02).timeout
		peak = maxf(peak, AudioServer.get_bus_peak_volume_left_db(bus, 0))
	await create_timer(1.0).timeout
	var pp: Dictionary = v._peers[99]
	check(pp.db > -10.0, "a crewmate in the same room is heard at full level (%.1f dB)" % pp.db)
	check(pp.frames == 120 and pp.queue.is_empty(), "every frame went to their voice player (%d, %d left over)" % [pp.frames, pp.queue.size()])
	check(pp.player.playing, "their voice player is playing")
	# A bumpy line: frames arriving in swapped pairs, every ninth one lost. It still plays through.
	for k in 120:
		var j := 200 + (k ^ 1)   # (out of order)
		if j % 9 == 0:
			await create_timer(0.02).timeout
			continue
		var f := PackedFloat32Array()
		f.resize(Voice.FRAME)
		f.fill(0.2)
		v.receive(99, Voice.packet(j, f))
		await create_timer(0.02).timeout
	await create_timer(0.5).timeout
	check(pp.frames_in.is_empty(), "a bumpy line: out-of-order frames sorted, lost ones covered, nothing stuck (%d left)" % pp.frames_in.size())
	check(pp.delay > Voice.START_AT or pp.delay == Voice.START_AT, "...the jitter buffer adapts (%d frames)" % pp.delay)
	print("(Voice bus peak %.1f dB; the headless audio driver does not always mix)" % peak)
	print("voice_play.gd: %s" % ("ALL PASSED" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails else 0)
