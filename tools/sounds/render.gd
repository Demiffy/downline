# Renders every sound print (tools/sounds/sound_prints.gd, rebuilt by tools/sounds/sound_print.gd) to WAV,
# take by take, exactly as the game used to build them at startup
# (each take's own dice: seeded by its name; kept off clipping; loops crossfaded end into start). Then
# tools/sound_print.py export turns them into the game's assets/sounds/*.ogg.
# Run: godot --headless --path . -s tools/sounds/render.gd -- <out_dir> [names...]
extends SceneTree
const Prints = preload("res://tools/sounds/sound_prints.gd")
const SoundPrint = preload("res://tools/sounds/sound_print.gd")
const Sfx = preload("res://src/sfx.gd")


func _initialize() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var only: Array = OS.get_cmdline_user_args().slice(1)
	var n_files := 0
	for s in Prints.P:
		if not only.is_empty() and not s in only:
			continue
		var takes: int = Prints.P[s].size()
		var many: bool = Sfx._has_takes(s)   # (footsteps and a few others: four takes even from one print, each its own dice)
		for k in (Sfx._takes(s) if many else 1):
			var rng := RandomNumberGenerator.new()
			rng.seed = hash("%s#%d" % [s, k] if many else s)
			var y := SoundPrint.build(Prints.P[s][k % takes], rng)
			_save(y, s in Sfx.LOOPS, "%s/%s.wav" % [out, s if not many else "%s_%d" % [s, k]])
			n_files += 1
	print("rendered %d files" % n_files)
	quit()


## As the game finished a sound: no peak over 0.9; a loop as it is (already crossfaded).
func _save(y: PackedFloat32Array, loop: bool, path: String) -> void:
	var peak := 0.0
	for v in y:
		peak = maxf(peak, absf(v))
	if peak > 0.9:
		for i in y.size():
			y[i] *= 0.9 / peak
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = SoundPrint.SR
	var b := PackedByteArray()
	b.resize(y.size() * 2)
	for i in y.size():
		b.encode_s16(i * 2, int(clampf(y[i], -1.0, 1.0) * 32000.0))
	w.data = b
	w.save_to_wav(path)

