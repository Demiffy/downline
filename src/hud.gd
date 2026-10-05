# Screen overlay: clock, quota, bars, slots, prompts, messages, fades.
extends CanvasLayer

const Data = preload("res://src/data.gd")

const BAR_W := 220.0

var mono := SystemFont.new()
var clock: Label
var alert_l: Label
var quota_l: Label
var right_l: Label
var prompt_l: Label
var feed_l: Label
var big_l: Label
var slots_l: RichTextLabel
var hp_bar: ColorRect
var st_bar: ColorRect
var hold_bar: ColorRect
var flash_r: ColorRect
var fade_r: ColorRect
var _feed: Array = []   # [text, seconds_left]
var _alert_t := 0.0
var _scan := ""
var _scan_t := 0.0
var _desc := ""


func _ready() -> void:
	layer = 1
	mono.font_names = PackedStringArray(["Menlo", "Consolas", "DejaVu Sans Mono", "monospace"])
	clock = _label(Control.PRESET_TOP_WIDE, HORIZONTAL_ALIGNMENT_CENTER, 30)
	clock.offset_top = 10
	alert_l = _label(Control.PRESET_TOP_WIDE, HORIZONTAL_ALIGNMENT_CENTER, 26)
	alert_l.offset_top = 56
	alert_l.add_theme_color_override("font_color", Color(1, 0.35, 0.3))
	quota_l = _label(Control.PRESET_TOP_LEFT, HORIZONTAL_ALIGNMENT_LEFT, 17, true)
	quota_l.position = Vector2(16, 12)
	right_l = _label(Control.PRESET_TOP_WIDE, HORIZONTAL_ALIGNMENT_RIGHT, 17, true)
	right_l.offset_top = 12
	right_l.offset_right = -16
	prompt_l = _label(Control.PRESET_BOTTOM_WIDE, HORIZONTAL_ALIGNMENT_CENTER, 20)
	prompt_l.offset_top = -130
	prompt_l.offset_bottom = -100
	feed_l = _label(Control.PRESET_BOTTOM_LEFT, HORIZONTAL_ALIGNMENT_LEFT, 17)
	feed_l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	feed_l.offset_left = 16
	feed_l.offset_right = 760
	feed_l.offset_top = -300
	feed_l.offset_bottom = -64
	slots_l = RichTextLabel.new()
	add_child(slots_l)
	slots_l.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	slots_l.offset_top = -56
	slots_l.offset_bottom = -16
	slots_l.bbcode_enabled = true
	slots_l.scroll_active = false
	slots_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slots_l.add_theme_font_override("normal_font", mono)
	slots_l.add_theme_font_size_override("normal_font_size", 17)
	hp_bar = _bar(-46, Color(0.95, 0.95, 0.95))
	st_bar = _bar(-28, Color(1, 0.6, 0.15))
	hold_bar = _rect(Control.PRESET_CENTER, Color(1, 0.85, 0.2))
	hold_bar.offset_top = 22
	hold_bar.offset_bottom = 28
	var dot := _rect(Control.PRESET_CENTER, Color(1, 1, 1, 0.7))
	dot.offset_left = -2
	dot.offset_right = 2
	dot.offset_top = -2
	dot.offset_bottom = 2
	big_l = _label(Control.PRESET_FULL_RECT, HORIZONTAL_ALIGNMENT_CENTER, 40)
	big_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	flash_r = _rect(Control.PRESET_FULL_RECT, Color(0.8, 0, 0, 0))
	fade_r = _rect(Control.PRESET_FULL_RECT, Color(0, 0, 0, 0))


func _label(preset: int, align: int, size: int, use_mono := false) -> Label:
	var l := Label.new()
	add_child(l)
	l.set_anchors_and_offsets_preset(preset)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	if use_mono:
		l.add_theme_font_override("font", mono)
	return l


func _rect(preset: int, c: Color) -> ColorRect:
	var r := ColorRect.new()
	add_child(r)
	r.set_anchors_and_offsets_preset(preset)
	r.color = c
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _bar(y: float, c: Color) -> ColorRect:
	var bg := _rect(Control.PRESET_BOTTOM_LEFT, Color(0, 0, 0, 0.5))
	bg.offset_left = 16
	bg.offset_right = 20 + BAR_W
	bg.offset_top = y
	bg.offset_bottom = y + 12
	var bar := _rect(Control.PRESET_BOTTOM_LEFT, c)
	bar.offset_left = 18
	bar.offset_right = 18 + BAR_W
	bar.offset_top = y + 2
	bar.offset_bottom = y + 10
	return bar


func _process(delta: float) -> void:
	_alert_t -= delta
	alert_l.visible = _alert_t > 0.0
	_scan_t -= delta
	var lines := PackedStringArray()
	for f in _feed:
		f[1] -= delta
	_feed = _feed.filter(func(f): return f[1] > 0.0)
	for f in _feed:
		lines.append(f[0])
	feed_l.text = "\n".join(lines)
	right_l.text = _desc + ("\n\n" + _scan if _scan_t > 0.0 else "")


func msg(text: String) -> void:
	_feed.append([text, 7.0])
	if _feed.size() > 6:
		_feed.pop_front()


func alert(text: String) -> void:
	alert_l.text = text
	_alert_t = 7.0


func set_scan(text: String) -> void:
	_scan = text
	_scan_t = 5.0


func set_prompt(text: String, progress: float) -> void:
	prompt_l.text = text
	hold_bar.visible = progress > 0.0
	hold_bar.offset_left = -60
	hold_bar.offset_right = -60 + 120 * clampf(progress, 0.0, 1.0)


func big(text: String) -> void:
	big_l.text = text


func fade(alpha: float, secs: float) -> void:
	var tw := create_tween()
	tw.tween_property(fade_r, "color:a", alpha, secs)
	await tw.finished


func update_player(p) -> void:
	hp_bar.offset_right = hp_bar.offset_left + BAR_W * clampf(p.hp / 100.0, 0.0, 1.0)
	st_bar.offset_right = st_bar.offset_left + BAR_W * p.stamina / p.MAX_STAMINA
	flash_r.color.a = p.flash * 0.5
	var s := "[center]"
	for i in p.max_slots():
		var it = p.slots[i]
		var text := "-"
		if it != null:
			text = Data.ITEMS[it.id].name
			if it.charge >= 0.0:
				text += " %d%%" % int(100.0 * it.charge / Data.ITEMS[it.id].charge)
		if i == p.sel:
			s += "[color=#ffd24a] >%d %s< [/color]" % [i + 1, text]
		else:
			s += "[color=#b0b0b0]  %d %s  [/color]" % [i + 1, text]
	s += "    [color=#7fe0ff]EQUIP: %s[/color]" % (Data.ITEMS[p.equip.id].name if p.equip != null else "-")
	slots_l.text = s
	var held = p.slots[p.sel]
	_desc = ""
	if held != null:
		var d: Dictionary = Data.ITEMS[held.id]
		_desc = d.name.to_upper()
		if not d.res.is_empty():
			_desc += "\nshreds to: " + Data.res_text(d.res)
		if d.has("desc"):
			_desc += "\n" + d.desc
