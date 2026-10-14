# What's making a sound right now (the playground, F12), by kind: ambience, creatures, you, the crew,
# items, hazards and events, the facility and stop, the checkpoint, the train, the line, voices, UI, the
# rest of the world.
# A sound's kind is whoever plays it (the first owner found going up from its player). Each row: the
# sound (and take), how many of it, how far the nearest is from your ears (FLAT: not in the world), its
# volume and pitch. Only what you can hear is listed; too far off or too quiet is counted as "silent".
extends PanelContainer

const Sfx = preload("res://src/sfx.gd")
const AMBER := Color(1.0, 0.62, 0.22)
const DIM := Color(0.62, 0.55, 0.45)
const INK := Color(0.95, 0.93, 0.88)
const LINES := 16   # (down to the message feed, no further)
const KINDS := ["AMBIENT", "CREATURES", "YOU", "CREW", "ITEMS", "HAZARDS & EVENTS", "FACILITY & STOP", "CHECKPOINT", "TRAIN", "LINE", "VOICE", "UI", "WORLD"]
const OWNERS := {   # script -> kind (creatures go by their groups)
	"player.gd": "YOU", "viewmodel.gd": "YOU", "puppet.gd": "CREW", "pickup.gd": "ITEMS", "ragdoll.gd": "ITEMS",
	"hazards.gd": "HAZARDS & EVENTS", "site_clock.gd": "HAZARDS & EVENTS", "director.gd": "HAZARDS & EVENTS", "airdrop.gd": "HAZARDS & EVENTS", "weather.gd": "HAZARDS & EVENTS",
	"yard_life.gd": "CHECKPOINT", "shredder.gd": "CHECKPOINT", "train.gd": "TRAIN", "line.gd": "LINE", "line_events.gd": "LINE",
	"level.gd": "FACILITY & STOP", "facility.gd": "FACILITY & STOP", "elevator.gd": "FACILITY & STOP", "door.gd": "FACILITY & STOP", "genset.gd": "FACILITY & STOP"}
const STINGS := ["far_bang", "groan", "pipe_knock", "far_steps", "drip", "far_screech"]   # (main._sound_space's, now and then far off below)

var text: RichTextLabel
var _t := 0.0


func _ready() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.055, 0.05, 0.045, 0.82)
	sb.border_color = Color(AMBER, 0.6)
	sb.border_width_left = 3
	sb.content_margin_left = 12
	sb.content_margin_right = 14
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	add_theme_stylebox_override("panel", sb)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	text = RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.scroll_active = false
	text.autowrap_mode = TextServer.AUTOWRAP_OFF
	text.custom_minimum_size = Vector2(620, 0)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["Consolas", "Menlo", "DejaVu Sans Mono", "monospace"])
	text.add_theme_font_override("normal_font", mono)
	text.add_theme_font_size_override("normal_font_size", 13)
	text.add_theme_color_override("default_color", INK)
	add_child(text)


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0:
		return
	_t = 0.2
	text.text = report()


## Whose sound it is.
static func kind_of(a: Node, name: String) -> String:
	if String(a.bus) == "Ambience" or name.get_slice("#", 0) in STINGS:
		return "AMBIENT"
	if String(a.bus) in ["Voice", "Radio"]:
		return "VOICE"
	var n := a.get_parent()
	while n != null:
		if n.is_in_group("monsters") or n.is_in_group("fauna"):
			return "CREATURES"
		var sc: Script = n.get_script()
		if sc != null and OWNERS.has(sc.resource_path.get_file()):
			return OWNERS[sc.resource_path.get_file()]
		if sc != null and sc.resource_path.get_file() == "main.gd":
			break
		n = n.get_parent()
	return "UI" if not a is AudioStreamPlayer3D else "WORLD"   # (played on the game itself: explosions, shots...)


## The table, as shown (tests read it too).
func report() -> String:
	var cam := get_viewport().get_camera_3d()
	var ear: Vector3 = cam.global_position if cam else Vector3.ZERO
	var rows := {}   # kind|name -> [name, count, nearest (-1: flat), loudest dB, pitch, kind, loop, heard]
	var root := get_tree().root
	for a in root.find_children("*", "AudioStreamPlayer", true, false) + root.find_children("*", "AudioStreamPlayer3D", true, false):
		if not a.playing or a.stream_paused or a.stream == null:
			continue
		var name := Sfx.name_of(a.stream)
		if name == "":   # (not one of ours: the voice, the intro's own)
			name = a.stream.resource_path.get_file() if a.stream.resource_path != "" else a.stream.get_class().trim_prefix("AudioStream")
		var kind := kind_of(a, name)
		name = name.replace("#", " #")
		var d := -1.0
		var heard: bool = a.volume_db > -60.0
		if a is AudioStreamPlayer3D:
			d = (a as AudioStreamPlayer3D).global_position.distance_to(ear)
			heard = heard and ((a as AudioStreamPlayer3D).max_distance <= 0.0 or d < (a as AudioStreamPlayer3D).max_distance)
		var loop: bool = a.stream.get("loop") == true or (a.stream is AudioStreamWAV and (a.stream as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_DISABLED)
		var key: String = kind + "|" + name.get_slice(" #", 0) + ("" if heard else "|silent")
		if not rows.has(key):
			rows[key] = [name, 0, d, a.volume_db, a.pitch_scale, kind, loop, heard]
		var r: Array = rows[key]
		r[1] += 1
		if d >= 0.0 and (r[2] < 0.0 or d < r[2]):
			r[0] = name
			r[2] = d
			r[4] = a.pitch_scale
		r[3] = maxf(r[3], a.volume_db)
	var by_kind := {}
	for r in rows.values():
		if not by_kind.has(r[5]):
			by_kind[r[5]] = []
		by_kind[r[5]].append(r)
	var heard_n := 0
	var silent_n := 0
	for r in rows.values():
		if r[7]:
			heard_n += r[1]
		else:
			silent_n += r[1]
	var out := "[color=#%s]SOUNDS PLAYING[/color]  %d heard, %d silent      [color=#%s]F12[/color] hides\n" % [AMBER.to_html(false), heard_n, silent_n, AMBER.to_html(false)]
	out += "[color=#%s]  %-26s %3s %7s %6s %5s[/color]\n" % [DIM.to_html(false), "SOUND", "N", "NEAREST", "DB", "PITCH"]
	var lines := 2
	var left := 0
	for k in KINDS:
		if not by_kind.has(k):
			continue
		var list: Array = by_kind[k].filter(func(r): return r[7])
		list.sort_custom(func(a, b): return a[2] < b[2])   # (flat ones (-1) first, then the nearest)
		var quiet: int = by_kind[k].filter(func(r): return not r[7]).reduce(func(n, r): return n + r[1], 0)
		if list.is_empty():   # (nothing of it you can hear: only in the count of silent ones up top)
			continue
		if lines >= LINES:
			left += list.size()
			continue
		out += "[color=#%s]%s[/color] [color=#%s]%d%s[/color]\n" % [AMBER.to_html(false), k, DIM.to_html(false), list.reduce(func(n, r): return n + r[1], 0), ("  +%d silent" % quiet) if quiet > 0 else ""]
		lines += 1
		for r in list:
			if lines >= LINES:
				left += 1
				continue
			out += "  %-26s %3s %7s %6.1f %5.2f\n" % [(String(r[0]) + (" (loop)" if r[6] else "")).left(26), "x%d" % r[1] if r[1] > 1 else "", "FLAT" if r[2] < 0.0 else "%.1f m" % r[2], r[3], r[4]]
			lines += 1
	if left > 0:
		out += "[color=#%s]... and %d more[/color]" % [DIM.to_html(false), left]
	return out
