# Writes synthesized sounds to WAV files (to compare against recordings).
# Run: tests/run.sh 300 --headless --path . -s tests/sfx_dump.gd -- <out_dir> name [name ...]
extends SceneTree
const Sfx = preload("res://src/sfx.gd")
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	for n in args.slice(1):
		var w = Sfx.stream(n)
		if w is AudioStreamWAV:   # (the synthesized ones: the rest are files already, assets/sounds)
			w.save_to_wav("%s/%s.wav" % [out, n])
	print("dumped %d" % (args.size() - 1))
	quit(0)
