# The train terminal. Commands are registered by main.gd as (name, min_args, usage, Callable).
# TAB completes, UP/DOWN walks history, typos get "Did you mean ...?".
# ponytail: full-screen overlay instead of an in-world screen; move to a SubViewport on the monitor later.
extends CanvasLayer

const Sfx = preload("res://src/sfx.gd")

signal closed

var out: RichTextLabel
var input: LineEdit
var commands := {}       # NAME -> {"args": int, "usage": String, "fn": Callable}
var history: Array[String] = []
var hist_i := 0
var confirm := Callable()  # pending YES/NO action
var booted := false
var _typed := 0.0


func _ready() -> void:
	layer = 5
	visible = false
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Menlo", "Consolas", "DejaVu Sans Mono", "monospace"])
	var bg := ColorRect.new()
	bg.color = Color(0.01, 0.03, 0.02, 0.96)
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 40)
	out = RichTextLabel.new()
	out.bbcode_enabled = true
	out.scroll_following = true
	out.size_flags_vertical = Control.SIZE_EXPAND_FILL
	out.visible_characters = 0
	out.add_theme_font_override("normal_font", font)
	out.add_theme_font_size_override("normal_font_size", 18)
	out.add_theme_color_override("default_color", Color(0.4, 1.0, 0.55))
	box.add_child(out)
	input = LineEdit.new()
	input.placeholder_text = "type a command   (TAB completes, UP/DOWN history, ESC leaves)"
	input.add_theme_font_override("font", font)
	input.add_theme_font_size_override("font_size", 18)
	input.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7))
	box.add_child(input)
	input.text_submitted.connect(_submit)
	input.gui_input.connect(_key)


func add(name: String, min_args: int, usage: String, fn: Callable) -> void:
	commands[name] = {"args": min_args, "usage": usage, "fn": fn}


func open() -> void:
	visible = true
	input.grab_focus()
	if not booted:
		booted = true
		say("BRM RAILNET OS v1.3   (c) Bureau of Reclaimed Materials")
		say("Your productivity is appreciated. Your safety is estimated.")
		say("Type HELP for a list of commands.\n")


func close() -> void:
	if not visible:
		return
	visible = false
	input.release_focus()
	closed.emit()


func say(text: String) -> void:
	out.append_text(text + "\n")


func error(text: String) -> void:
	say("[color=#ff6a5a]%s[/color]" % text)
	Sfx.play(self, "error", null, -8.0)


func clear() -> void:
	out.clear()
	out.visible_characters = 0


func _process(delta: float) -> void:
	var total := out.get_total_character_count()
	if out.visible_characters < total:
		_typed += delta * 900.0
		var n := int(_typed)
		_typed -= n
		out.visible_characters = mini(out.visible_characters + n, total)
		if n > 0 and randf() < 0.25:
			Sfx.play(self, "key", null, -20.0)


func _submit(line: String) -> void:
	input.clear()
	if line.strip_edges() == "":
		return
	history.append(line)
	hist_i = history.size()
	say("> " + line.replace("[", "[lb]"))
	run(line)


func run(line: String) -> void:
	var a := parse(line)
	if a.is_empty():
		return
	if confirm.is_valid():
		var c := confirm
		confirm = Callable()
		if a[0] in ["YES", "Y"]:
			c.call()
			return
		if a[0] in ["NO", "N"]:
			say("Cancelled.")
			return
	var cmd = commands.get(a[0])
	if cmd == null:
		var guess := closest(a[0], commands.keys())
		error("Command not recognized. " + ("Did you mean %s?" % guess if guess != "" else "Type HELP for a list of commands."))
		return
	if a.size() - 1 < cmd.args:
		error("Incorrect use of parameters. Usage: " + cmd.usage)
		return
	cmd.fn.call(a.slice(1))


func _key(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed):
		return
	match e.keycode:
		KEY_TAB:
			var parts := input.text.split(" ")
			if parts.size() == 1:
				var done := complete(parts[0].to_upper(), commands.keys())
				input.text = done + (" " if commands.has(done) else "")
				input.caret_column = input.text.length()
			input.accept_event()
		KEY_UP:
			hist_i = maxi(0, hist_i - 1)
			if hist_i < history.size():
				input.text = history[hist_i]
				input.caret_column = input.text.length()
			input.accept_event()
		KEY_DOWN:
			hist_i = mini(history.size(), hist_i + 1)
			input.text = history[hist_i] if hist_i < history.size() else ""
			input.caret_column = input.text.length()
			input.accept_event()
		KEY_ESCAPE:
			close()
			input.accept_event()


static func parse(line: String) -> PackedStringArray:
	return line.strip_edges().to_upper().split(" ", false)


## Longest common prefix of every name starting with `word` (unchanged if none match).
static func complete(word: String, names: Array) -> String:
	var hits := names.filter(func(n): return String(n).begins_with(word))
	if hits.is_empty():
		return word
	var p: String = hits[0]
	for h in hits:
		while not String(h).begins_with(p):
			p = p.left(-1)
	return p


static func closest(word: String, names: Array) -> String:
	var best := ""
	var score := 0.45
	for n in names:
		var s := word.similarity(n)
		if s > score:
			score = s
			best = n
	return best
