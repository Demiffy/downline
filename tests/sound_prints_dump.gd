# Every sound print as the game builds it (every take) written to WAV, to set beside the tool's own
# rebuild (tools/sound_print.py writes name_rebuild.wav). Also times the building.
# Run: godot --headless --path . -s tests/sound_prints_dump.gd -- <dir> [names...]
extends SceneTree
const Sfx = preload("res://src/sfx.gd")
const Prints = preload("res://src/sound_prints.gd")


func _initialize() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var only: Array = OS.get_cmdline_user_args().slice(1)
	var t0 := Time.get_ticks_msec()
	var secs := 0.0
	for s in Prints.P:
		if not only.is_empty() and not s in only:
			continue
		var n: int = Prints.P[s].size()
		for k in n:
			var st: AudioStreamWAV = Sfx.stream("%s#%d" % [s, k] if Sfx._has_takes(s) else s)
			st.save_to_wav(out + "/" + (s if n == 1 else "%s@%d" % [s, k]) + "_game.wav")
			secs += st.get_length()
	print("built %.1f s of sound in %d ms" % [secs, Time.get_ticks_msec() - t0])
	quit()
