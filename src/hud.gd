# Helmet-visor HUD: curved frame lines, clock + compass, HP ring, battery, text slots.
extends CanvasLayer

const Data = preload("res://src/data.gd")
const Interact = preload("res://src/interact.gd")
const Cracks = preload("res://src/cracks.gd")

const WHITE := Color(0.95, 0.93, 0.88, 0.9)
const ORANGE := Color(1.0, 0.55, 0.15)
const GOLD := Color(0.85, 0.6, 0.2)

var mono := SystemFont.new()
var canvas: Control
var minimap: Control   # clips its drawing to its own square
var alert_l: Label
var quota_l: Label
var right_l: Label
var prompt_l: Label
var feed_l: Label
var big_l: Label
var hold_bar: ColorRect
var flash_r: ColorRect
var blind_r: ColorRect
var fade_r: ColorRect
var visor_fog: TextureRect   # steam condensing on the visor
var night_vision: ColorRect  # the goggles: the scene amplified into grainy green
var visor_cracks: TextureRect   # your visor, cracked by the hits you've taken
var _nv_mat: ShaderMaterial
var _fog := 0.0
var _feed: Array = []
var _alert_t := 0.0
var _scan := ""
var _scan_t := 0.0
var _desc := ""
var _clock := ""
var _code := ""
var _p = null
var _mm_t := 0.0
var _crack_shown := 0


func _ready() -> void:
	layer = 1
	mono.font_names = PackedStringArray(["Menlo", "Consolas", "DejaVu Sans Mono", "monospace"])
	mono.font_weight = 700
	var vignette := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0))
	g.set_color(1, Color(0, 0, 0, 0.75))
	g.add_point(0.55, Color(0, 0, 0, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.05, 1.05)
	vignette.texture = gt
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vignette)
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	night_vision = ColorRect.new()   # first, so the HUD reads on top of it
	_nv_mat = ShaderMaterial.new()
	_nv_mat.shader = Shader.new()
	_nv_mat.shader.code = NV_SHADER
	night_vision.material = _nv_mat
	night_vision.mouse_filter = Control.MOUSE_FILTER_IGNORE
	night_vision.visible = false
	add_child(night_vision)
	move_child(night_vision, 0)
	night_vision.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visor_cracks = TextureRect.new()
	visor_cracks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visor_cracks.stretch_mode = TextureRect.STRETCH_SCALE
	visor_cracks.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	visor_cracks.visible = false
	add_child(visor_cracks)
	visor_cracks.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas = Control.new()
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(canvas)
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.draw.connect(_draw_hud)
	minimap = Control.new()
	minimap.clip_contents = true
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(minimap)
	minimap.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	minimap.offset_left = -315
	minimap.offset_right = -45
	minimap.offset_top = -375
	minimap.offset_bottom = -105
	minimap.draw.connect(func(): if _p != null: _p.main.draw_minimap(minimap, minimap.size / 2.0, minimap.size.x / 2.0 - 1.0))
	alert_l = _label(Control.PRESET_TOP_WIDE, HORIZONTAL_ALIGNMENT_CENTER, 22)
	alert_l.offset_top = 118
	alert_l.add_theme_color_override("font_color", Color(1, 0.35, 0.25))
	quota_l = _label(Control.PRESET_TOP_LEFT, HORIZONTAL_ALIGNMENT_LEFT, 16)
	quota_l.position = Vector2(40, 60)
	right_l = _label(Control.PRESET_TOP_WIDE, HORIZONTAL_ALIGNMENT_RIGHT, 16)
	right_l.offset_top = 60
	right_l.offset_right = -40
	prompt_l = _label(Control.PRESET_CENTER, HORIZONTAL_ALIGNMENT_CENTER, 18)
	prompt_l.offset_left = -500
	prompt_l.offset_right = 500
	prompt_l.offset_top = 40
	prompt_l.offset_bottom = 70
	feed_l = _label(Control.PRESET_BOTTOM_LEFT, HORIZONTAL_ALIGNMENT_LEFT, 15)
	feed_l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	feed_l.offset_left = 40
	feed_l.offset_right = 800
	feed_l.offset_top = -340
	feed_l.offset_bottom = -170
	hold_bar = _rect(Control.PRESET_CENTER, ORANGE)
	hold_bar.offset_top = 76
	hold_bar.offset_bottom = 82
	big_l = _label(Control.PRESET_FULL_RECT, HORIZONTAL_ALIGNMENT_CENTER, 36)
	big_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	visor_fog = TextureRect.new()   # thicker at the edges, a clearer patch in the middle
	var fg := Gradient.new()
	fg.set_color(0, Color(0.88, 0.9, 0.92, 0.55))
	fg.set_color(1, Color(0.92, 0.93, 0.95, 1.0))
	var ft := GradientTexture2D.new()
	ft.gradient = fg
	ft.fill = GradientTexture2D.FILL_RADIAL
	ft.fill_from = Vector2(0.5, 0.5)
	ft.fill_to = Vector2(1.1, 1.1)
	visor_fog.texture = ft
	visor_fog.stretch_mode = TextureRect.STRETCH_SCALE
	visor_fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visor_fog.modulate.a = 0.0
	add_child(visor_fog)
	visor_fog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash_r = _rect(Control.PRESET_FULL_RECT, Color(0.8, 0, 0, 0))
	blind_r = _rect(Control.PRESET_FULL_RECT, Color(1, 0.98, 0.93, 0))   # the observer's flash: a white-out that fades
	fade_r = _rect(Control.PRESET_FULL_RECT, Color(0, 0, 0, 0))
	move_child(big_l, -1)   # cards (death, left behind) read over the fade


## Image intensifier: brightness pulled up hard (the dark goes grey-green, lit things bloom), grain,
## faint scan lines and a round eyepiece.
const NV_SHADER := """
shader_type canvas_item;
uniform sampler2D screen: hint_screen_texture, filter_linear_mipmap;
uniform float t = 0.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	vec3 c = textureLod(screen, SCREEN_UV, 0.6).rgb;
	float l = dot(c, vec3(0.3, 0.59, 0.11));
	l = 1.0 - exp(-l * 16.0);
	float g = hash(floor(SCREEN_UV * vec2(640.0, 360.0)) + floor(t * 30.0));
	l = l * 0.88 + g * 0.14;
	vec2 d = (SCREEN_UV - 0.5) * vec2(1.7, 1.0);
	float eye = smoothstep(0.82, 0.5, length(d));
	float scan = 0.95 + 0.05 * sin(SCREEN_UV.y * 1100.0);
	COLOR = vec4(vec3(0.3, 1.0, 0.42) * l * eye * scan, 1.0);
}
"""


func _label(preset: int, align: int, size: int) -> Label:
	var l := Label.new()
	add_child(l)
	l.set_anchors_and_offsets_preset(preset)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", mono)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", WHITE)
	l.add_theme_constant_override("outline_size", 5)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	return l


func _rect(preset: int, c: Color) -> ColorRect:
	var r := ColorRect.new()
	add_child(r)
	r.set_anchors_and_offsets_preset(preset)
	r.color = c
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Steam on the visor: rises fast, clears over a couple of seconds.
func fog_visor(amount: float) -> void:
	_fog = maxf(_fog, clampf(amount, 0.0, 1.0))


func _process(delta: float) -> void:
	_fog = move_toward(_fog, 0.0, delta * 0.45)
	visor_fog.modulate.a = lerpf(visor_fog.modulate.a, _fog * 0.85, minf(1.0, delta * 10.0))
	_alert_t -= delta
	alert_l.visible = _alert_t > 0.0
	_scan_t -= delta
	for f in _feed:
		f[1] -= delta
	_feed = _feed.filter(func(f): return f[1] > 0.0)
	var lines := PackedStringArray()
	for f in _feed:
		lines.append(f[0])
	feed_l.text = "\n".join(lines)
	right_l.text = _desc + ("\n\n" + _scan if _scan_t > 0.0 else "")
	canvas.queue_redraw()
	_mm_t -= delta
	if _mm_t <= 0.0:   # (the map moves smoothly enough at 20 frames a second, and costs a third as much)
		_mm_t = 0.05
		minimap.queue_redraw()


# --- drawing -------------------------------------------------------------------------

func _arc_y(x: float, w: float, y0: float, sag: float) -> float:
	var u := (x - w / 2) / (w / 2)
	return y0 + sag * (1.0 - u * u)


func _text(pos: Vector2, s: String, size: int, c: Color, align := HORIZONTAL_ALIGNMENT_CENTER, width := -1.0) -> void:
	canvas.draw_string_outline(mono, pos, s, align, width, size, 4, Color(0, 0, 0, 0.7))
	canvas.draw_string(mono, pos, s, align, width, size, c)


func _draw_hud() -> void:
	var sz := canvas.size
	var w := sz.x
	var h := sz.y
	# Visor frame: top and bottom curves.
	var top := PackedVector2Array()
	var bot := PackedVector2Array()
	for i in 65:
		var x := w * i / 64.0
		top.append(Vector2(x, _arc_y(x, w, 8, 34)))
		bot.append(Vector2(x, h - _arc_y(x, w, 8, 34)))
	canvas.draw_polyline(top, WHITE, 2.0, true)
	canvas.draw_polyline(bot, WHITE, 2.0, true)
	# Clock + compass.
	_text(Vector2(0, 66), _clock, 22, WHITE, HORIZONTAL_ALIGNMENT_CENTER, w)
	if _p != null:
		var heading := fposmod(-rad_to_deg(_p.rotation.y), 360.0)
		var cx := w / 2
		var span := 240.0
		for deg in range(0, 360, 15):
			var d := fposmod(deg - heading + 180.0, 360.0) - 180.0
			if absf(d) > 60.0:
				continue
			var x := cx + d / 60.0 * span / 2
			var big := deg % 45 == 0
			canvas.draw_line(Vector2(x, 76), Vector2(x, 76 + (10 if big else 5)), WHITE, 1.5)
			if big:
				var names := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
				_text(Vector2(x - 20, 104), names[deg / 45], 13 if deg % 90 else 16, WHITE, HORIZONTAL_ALIGNMENT_CENTER, 40)
		canvas.draw_line(Vector2(cx - span / 2, 76), Vector2(cx + span / 2, 76), Color(WHITE, 0.5), 1.0)
		_hp_ring(Vector2(96, h - 112))
		_slots(w, h)
	_text(Vector2(0, h - 18), _code, 18, WHITE, HORIZONTAL_ALIGNMENT_CENTER, w)
	if _p != null and _p.main.net.active and _p.main.net.started:
		_crew(Vector2(28, quota_l.position.y + quota_l.get_combined_minimum_size().y + 26))   # under the quota, however long it runs
	if bool(load("res://src/settings.gd").v.get("show_fps", false)):   # top right, small
		var fps := Engine.get_frames_per_second()
		_text(Vector2(w - 230, 30), "%d FPS  %.1f ms" % [fps, 1000.0 / maxf(fps, 1.0)], 14, Color(WHITE, 0.75), HORIZONTAL_ALIGNMENT_RIGHT, 190)
	# Crosshair.
	canvas.draw_arc(sz / 2, 4.0, 0, TAU, 16, Color(1, 1, 1, 0.75), 1.5)


## The crew down the left edge: a lit dot for whoever's talking, a cross for the dead; your own
## mic underneath (level, or how to talk).
func _crew(at: Vector2) -> void:
	var net = _p.main.net
	var ids: Array = net.roster.keys()
	ids.sort()
	var y := at.y
	for id in ids:
		var me: bool = id == net.me()
		var pup = null if me else net.puppets.get(id)
		var talking: bool = net.voice.speaking if me else (pup != null and is_instance_valid(pup) and pup.speaking)
		var down: bool = _p.dead if me else (pup != null and is_instance_valid(pup) and pup.dead)
		var c := Color(0.55, 1.0, 0.55) if talking else (Color(WHITE, 0.45) if down else Color(WHITE, 0.75))
		if down:
			canvas.draw_line(at + Vector2(-5, y - at.y - 9), at + Vector2(5, y - at.y + 1), c, 2.0)
			canvas.draw_line(at + Vector2(5, y - at.y - 9), at + Vector2(-5, y - at.y + 1), c, 2.0)
		else:
			canvas.draw_circle(Vector2(at.x, y - 4), 4.5 if talking else 3.0, c)
		_text(Vector2(at.x + 14, y), net.name_of(id) + ("  (you)" if me else ""), 14, c, HORIZONTAL_ALIGNMENT_LEFT)
		if not me and not down:   # is their voice getting through? (what you'd want to know when you can't hear someone)
			var vp: Dictionary = net.voice._peers.get(id, {})
			var fresh: bool = Time.get_ticks_msec() - int(vp.get("last_rx", 0)) < 800
			var note := ""
			var nc := Color(WHITE, 0.5)
			if fresh:
				var db: float = vp.get("db", 0.0)
				note = "voice in" if db > -10.0 else ("muffled" if db > -60.0 else "blocked by walls")
				nc = Color(0.55, 1.0, 0.55, 0.7) if db > -10.0 else Color(1.0, 0.75, 0.3, 0.8)
			elif talking:
				note = "talking, no audio arriving"
				nc = Color(1, 0.45, 0.35, 0.85)
			if note != "":
				_text(Vector2(at.x + 150, y), note, 11, nc, HORIZONTAL_ALIGNMENT_LEFT)
		y += 20
	var v = net.voice
	var Settings = load("res://src/settings.gd")
	y += 4
	if not bool(Settings.v.get("mic_on", true)):
		_text(Vector2(at.x - 4, y), "MIC OFF", 12, Color(1, 0.45, 0.35, 0.8), HORIZONTAL_ALIGNMENT_LEFT)
	else:
		if _p.transmitting():
			_text(Vector2(at.x - 4, y - 16), "RADIO" + ("  [ON AIR]" if v.speaking else ""), 12, Color(1.0, 0.75, 0.3, 0.9), HORIZONTAL_ALIGNMENT_LEFT)
		var ptt: bool = int(Settings.v.get("voice_mode", 0)) == 1
		_text(Vector2(at.x - 4, y), "HOLD V TO TALK" if ptt and not v.speaking else "MIC", 12, Color(WHITE, 0.6), HORIZONTAL_ALIGNMENT_LEFT)
		if not ptt or v.speaking:
			var bx := at.x + 30
			canvas.draw_rect(Rect2(bx, y - 9, 70, 6), Color(WHITE, 0.25), false, 1.0)
			canvas.draw_rect(Rect2(bx, y - 9, 70 * clampf(v.level, 0.0, 1.0), 6), Color(0.55, 1.0, 0.55, 0.85) if v.speaking else Color(WHITE, 0.5))


func _hp_ring(c: Vector2) -> void:
	var r := 46.0
	for i in 24:
		var a0 := TAU * i / 24.0
		canvas.draw_arc(c, r, a0, a0 + TAU / 48.0, 4, WHITE, 4.0)
	var st: float = _p.stamina / _p.max_stamina
	var n := int(round(st * 20))
	for i in n:
		var a0 := -PI / 2 + TAU * i / 20.0
		canvas.draw_arc(c, r - 9, a0, a0 + TAU / 40.0, 4, ORANGE, 4.0)
	_text(c + Vector2(-50, 11), "%d" % int(ceil(_p.hp)), 30, WHITE, HORIZONTAL_ALIGNMENT_CENTER, 100)
	# Battery of the held tool.
	var it = _p.slots[_p.sel]
	if it != null and it.charge >= 0.0:
		var frac: float = it.charge / _p.main.charge_max(it.id)
		var bx := c + Vector2(70, -30)
		canvas.draw_rect(Rect2(bx, Vector2(22, 40)), WHITE, false, 2.0)
		canvas.draw_rect(Rect2(bx + Vector2(7, -4), Vector2(8, 4)), WHITE)
		for i in 4:
			if frac > i / 4.0:
				canvas.draw_rect(Rect2(bx + Vector2(4, 31 - i * 9), Vector2(14, 6)), WHITE)
	if _p.main.has_upgrade("HEADLAMP") or _p.main.has_upgrade("NIGHT_VISION"):   # the helmet cell, under the ring
		var cell: float = _p.helmet_charge / _p.helmet_max()
		var on: bool = _p.headlamp_on or _p.nv_on
		var at := c + Vector2(-46, 62)
		canvas.draw_rect(Rect2(at, Vector2(92, 7)), Color(WHITE, 0.35), false, 1.0)
		canvas.draw_rect(Rect2(at + Vector2(1, 1), Vector2(90 * cell, 5)), ORANGE if on else Color(WHITE, 0.6))
		_text(at + Vector2(-34, 21), "HELMET  [T] LAMP  [N] NV" if cell > 0.0 else "HELMET CELL FLAT", 11, Color(WHITE, 0.6), HORIZONTAL_ALIGNMENT_CENTER, 160)
	if _p.equip != null:
		var ex := c + Vector2(102, -2)
		canvas.draw_rect(Rect2(ex, Vector2(28, 28)), WHITE, false, 2.0)
		_text(ex + Vector2(0, 20), Data.ITEMS[_p.equip.id].name.left(1), 18, WHITE, HORIZONTAL_ALIGNMENT_CENTER, 28)


func _slots(w: float, h: float) -> void:
	var n: int = _p.max_slots()
	for i in n:
		var x := w * (0.3 + 0.4 * (i + 0.5) / n)
		var y := h - _arc_y(x, w, 8, 34) - 14
		var it = _p.slots[i]
		var name: String = Data.ITEMS[it.id].name.to_upper() if it != null else "NONE"
		if i == _p.sel:
			var tw := mono.get_string_size("[%s]" % name, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
			canvas.draw_rect(Rect2(x - tw / 2 - 6, y - 17, tw + 12, 22), Color(GOLD, 0.85))
			_text(Vector2(x - 150, y), "[%s]" % name, 15, Color(1, 0.95, 0.85), HORIZONTAL_ALIGNMENT_CENTER, 300)
		else:
			_text(Vector2(x - 150, y), name, 15, WHITE, HORIZONTAL_ALIGNMENT_CENTER, 300)


# --- API used by main / player ------------------------------------------------------------

func set_status(clock_text: String, quota_text: String, code: String) -> void:
	_clock = clock_text
	quota_l.text = quota_text
	_code = code


func msg(text: String) -> void:
	var who = Interact.who_now   # pressed by a crewmate (a shared button running here too): theirs to read
	if who != null and _p != null and who != _p:
		if who.has_method("say"):
			who.say(text)
		return
	for f in _feed:   # the same line again (their own run, and the host's word): just keep it up
		if f[0] == text:
			f[1] = 7.0
			return
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


## The run's memento on the run-over screen: every photo pinned up on the train, laid out like
## prints on a board along the bottom, each a little crooked, with its stamp. Returns the board.
func memento(photos: Array) -> Control:
	if photos.is_empty():
		return null
	var board := Control.new()
	board.name = "Memento"
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(board)
	move_child(board, big_l.get_index())   # under the text, over the fade
	var vw: float = get_viewport().get_visible_rect().size.x
	board.position = Vector2(0, get_viewport().get_visible_rect().size.y - 300.0)
	board.size = Vector2(vw, 280.0)
	var title := _label(Control.PRESET_TOP_WIDE, HORIZONTAL_ALIGNMENT_CENTER, 18)
	title.reparent(board, false)
	title.position = Vector2.ZERO
	title.size = Vector2(vw, 24.0)
	title.text = "PINNED UP ON THE TRAIN THIS RUN"
	title.add_theme_color_override("font_color", GOLD)
	var shown: Array = photos.slice(maxi(0, photos.size() - 10))
	var n := shown.size()
	var w := clampf(1500.0 / n - 16.0, 120.0, 220.0)   # cards shrink to fit, and overlap past ~7
	var h := w * 1.06
	var step := minf(w + 16.0, 1500.0 / n)
	var rng := RandomNumberGenerator.new()
	rng.seed = n * 7919
	for i in n:
		var e: Dictionary = shown[i]
		var card := Control.new()
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		board.add_child(card)
		var x := (i - (n - 1) / 2.0) * step - w / 2.0   # from the middle of the board
		var y := 34.0 + rng.randf_range(0.0, 22.0)
		card.position = Vector2(vw / 2.0 + x, y)
		card.size = Vector2(w, h)
		card.pivot_offset = Vector2(w, h) / 2.0
		card.rotation = deg_to_rad(rng.randf_range(-7.0, 7.0))
		var shadow := ColorRect.new()   # a soft drop shadow
		shadow.color = Color(0, 0, 0, 0.45)
		shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(shadow)
		shadow.position = Vector2(6, 8)
		shadow.size = card.size
		var paper := ColorRect.new()
		paper.color = Color(0.94, 0.93, 0.88)
		paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(paper)
		paper.size = card.size
		var pic := TextureRect.new()
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		card.add_child(pic)
		pic.position = Vector2(w * 0.05, w * 0.05)
		pic.size = Vector2(w * 0.9, w * 0.76)
		if e.has("tex"):
			pic.texture = e.tex
		else:   # no picture came out: a dark, blank print
			var blank := ColorRect.new()
			blank.color = Color(0.12, 0.11, 0.1)
			blank.mouse_filter = Control.MOUSE_FILTER_IGNORE
			pic.add_child(blank)
			blank.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var stamp := Label.new()
		stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stamp.add_theme_font_override("font", mono)
		stamp.add_theme_font_size_override("font_size", int(clampf(w * 0.075, 10.0, 16.0)))
		stamp.add_theme_color_override("font_color", Color(0.2, 0.22, 0.42))
		stamp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stamp.text = e.get("stamp", "")
		card.add_child(stamp)
		stamp.position = Vector2(0, w * 0.83)
		stamp.size = Vector2(w, h - w * 0.83)
		var pin := ColorRect.new()   # the drawing pin
		pin.color = Color(0.8, 0.12, 0.1)
		pin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(pin)
		pin.size = Vector2(10, 10)
		pin.position = Vector2(w / 2.0 - 5.0, 3.0)
	big_l.offset_bottom = -300   # the text sits above the board
	return board


func fade(alpha: float, secs: float) -> void:
	var tw := create_tween()
	tw.tween_property(fade_r, "color:a", alpha, secs)
	if tw.is_running():   # a long frame can finish it before we get here
		await tw.finished


func update_player(p) -> void:
	_p = p
	flash_r.color.a = p.flash * 0.5
	night_vision.visible = p.nv_on and not p.dead
	visor_cracks.visible = p.crack_tier > 0 and not p.dead
	if visor_cracks.visible and _crack_shown != p.crack_tier:
		_crack_shown = p.crack_tier
		visor_cracks.texture = Cracks.texture(p.crack_tier, 1024)
		visor_cracks.modulate.a = 0.0
		create_tween().tween_property(visor_cracks, "modulate:a", 0.75, 0.15)
	if night_vision.visible:
		_nv_mat.set_shader_parameter("t", Time.get_ticks_msec() / 1000.0)
	blind_r.color.a = clampf(p.blind * 1.35, 0.0, 1.0)
	var held = p.slots[p.sel]
	_desc = ""
	if held != null:
		var d: Dictionary = Data.ITEMS[held.id]
		_desc = "[%s]\n-------------------" % d.name
		match Data.kind(held.id):
			"tool": _desc += "\nClick - turn on/off"
			"equip": _desc += "\nClick - equip"
			"disk": _desc += "\nClick on the train - upload"
			"photo": _desc += "\nClick - look at it closely"
			"weapon": _desc += ("\nClick - fire   (%d shells)" % int(held.charge)) if held.id == "SHOTGUN" else "\nClick - swing"
		if d.has("desc"):
			_desc += "\n" + d.desc
		if not d.res.is_empty():
			_desc += "\n-------------------"
			for r in Data.RES:
				if d.res.get(r, 0) > 0:
					_desc += "\n%s - %d" % [r.capitalize(), d.res[r]]
