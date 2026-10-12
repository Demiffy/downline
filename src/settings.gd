# Player settings, kept in user://settings.cfg. Static so anything can read them (player reads sens/fov/bob).
# The screen that changes them is settings_ui.gd (the pause menu's and the title screen's).
extends RefCounted

const PATH := "user://settings.cfg"
const DEFAULTS := {
	# game
	"fov": 80.0, "crosshair": true, "hud_opacity": 1.0, "show_fps": false, "skip_intro": false,
	# controls
	"sens": 1.0, "invert_y": false, "crouch_toggle": false, "sprint_toggle": false, "binds": {},
	# video
	"window_mode": 0, "vsync": true, "fps_cap": 0, "brightness": 1.0,
	"quality": 2, "render_scale": 1.0, "shadows": 2, "ssao": true, "glow": true, "fog": 1, "aa": 1,
	# audio
	"vol_master": 1.0, "vol_world": 1.0, "vol_ambience": 1.0, "voice_vol": 1.0,
	"out_device": "Default", "in_device": "Default",
	"mic_on": true, "voice_mode": 0, "voice_gate": 0.008, "mic_gain": 1.0, "mic_test": false,   # voice: 0 open mic, 1 push-to-talk
	# accessibility
	"head_bob": true, "shake": 1.0, "flash": 1.0,
	# your crew look (suit.gd LOOK): suit colour, helmet colour, marking, visor, pack, gloves, boots,
	# tape, helmet style, chest kit, wear
	"look_suit": 0, "look_helmet": 0, "look_mark": 0, "look_visor": 0, "look_pack": 0, "look_gloves": 0,
	"look_boots": 0, "look_trim": 0, "look_style": 0, "look_chest": 0, "look_wear": 0,
	# remembered
	"player_name": "", "last_ip": "127.0.0.1", "last_port": 24565,
}
const WINDOW_MODES := ["WINDOWED", "FULLSCREEN", "EXCLUSIVE FULLSCREEN"]
const FPS_CAPS := [0, 30, 60, 90, 120, 144, 165, 240]   # 0: no cap
const QUALITY := ["LOW", "MEDIUM", "HIGH", "ULTRA", "CUSTOM"]
const SHADOWS := ["LOW", "MEDIUM", "HIGH", "ULTRA"]
const AA := ["OFF", "FXAA", "TAA", "MSAA 4X"]
# What each quality preset sets: render scale, shadows, ambient occlusion, glow, fog, anti-aliasing.
const PRESETS := [
	{"render_scale": 0.67, "shadows": 0, "ssao": false, "glow": false, "fog": 0, "aa": 1},
	{"render_scale": 0.85, "shadows": 1, "ssao": false, "glow": true, "fog": 1, "aa": 1},
	{"render_scale": 1.0, "shadows": 2, "ssao": true, "glow": true, "fog": 1, "aa": 1},
	{"render_scale": 1.0, "shadows": 3, "ssao": true, "glow": true, "fog": 2, "aa": 2},
]
# The keys you can rebind, in the order the settings list them: action, name, default key.
const BINDABLE := [
	["move_forward", "MOVE FORWARD", KEY_W], ["move_back", "MOVE BACK", KEY_S],
	["move_left", "MOVE LEFT", KEY_A], ["move_right", "MOVE RIGHT", KEY_D],
	["sprint", "SPRINT", KEY_SHIFT], ["crouch", "CROUCH", KEY_CTRL], ["jump", "JUMP", KEY_SPACE],
	["interact", "USE / PRY", KEY_E], ["drop", "DROP ITEM", KEY_Q], ["drop_equip", "DROP EQUIPMENT", KEY_C],
	["scan", "SCAN", KEY_F], ["headlamp", "HEADLAMP", KEY_T], ["night_vision", "NIGHT VISION", KEY_N],
	["push_to_talk", "PUSH TO TALK", KEY_V], ["emote", "EMOTE WHEEL (HOLD)", KEY_G],
]
static var v := DEFAULTS.duplicate(true)


static func load_file(path := PATH) -> void:
	var cf := ConfigFile.new()
	if cf.load(path) != OK:
		return
	for k in DEFAULTS:
		v[k] = cf.get_value("settings", k, DEFAULTS[k])
	if is_equal_approx(float(v.voice_gate), 0.02):   # the old default shut out quiet microphones
		v.voice_gate = DEFAULTS.voice_gate
	if not cf.has_section_key("settings", "window_mode"):   # (from before there were three)
		v.window_mode = 1 if bool(cf.get_value("settings", "fullscreen", false)) else 0
	if not cf.has_section_key("settings", "render_scale"):   # (only a preset back then)
		v.quality = clampi(int(v.quality), 0, 2)
		use_preset(int(v.quality))
	if typeof(v.binds) != TYPE_DICTIONARY:
		v.binds = {}
	v.mic_test = false   # (never left listening to yourself from last time)


static func save() -> void:
	var cf := ConfigFile.new()
	for k in v:
		cf.set_value("settings", k, v[k])
	cf.save(PATH)


static func look() -> Array:
	var out := []
	for slot in load("res://src/suit.gd").LOOK:
		out.append(int(v.get("look_" + slot, 0)))
	return out


static func use_preset(q: int) -> void:
	v.quality = q
	if q < PRESETS.size():
		for k in PRESETS[q]:
			v[k] = PRESETS[q][k]


## After one of the preset's own settings is changed by hand: which preset it now matches, if any.
static func match_preset() -> void:
	for q in PRESETS.size():
		var same := true
		for k in PRESETS[q]:
			if not is_equal_approx(float(v[k]), float(PRESETS[q][k])):
				same = false
		if same:
			v.quality = q
			return
	v.quality = PRESETS.size()   # CUSTOM


## Window, audio, renderer, environment; the player and HUD read their own values live.
static func apply(main: Node) -> void:
	if DisplayServer.get_name() != "headless":
		var mode: int = [DisplayServer.WINDOW_MODE_WINDOWED, DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN][clampi(int(v.window_mode), 0, 2)]
		if DisplayServer.window_get_mode() != mode and not (mode == DisplayServer.WINDOW_MODE_WINDOWED and DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MAXIMIZED):
			DisplayServer.window_set_mode(mode)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if v.vsync else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = FPS_CAPS[clampi(int(v.fps_cap), 0, FPS_CAPS.size() - 1)]
	for bus in [["Master", "vol_master"], ["World", "vol_world"], ["Ambience", "vol_ambience"]]:
		var i := AudioServer.get_bus_index(bus[0])
		if i >= 0:
			AudioServer.set_bus_volume_db(i, linear_to_db(maxf(float(v[bus[1]]), 0.0001)))
			AudioServer.set_bus_mute(i, float(v[bus[1]]) <= 0.001)
	var outs := AudioServer.get_output_device_list()
	var want_out: String = v.out_device if v.out_device in outs else "Default"
	if AudioServer.output_device != want_out:
		AudioServer.output_device = want_out
	var ins := AudioServer.get_input_device_list()
	var want_in: String = v.in_device if v.in_device in ins else "Default"
	if AudioServer.input_device != want_in:
		AudioServer.input_device = want_in
	if main == null:
		return
	var vp: Viewport = main.get_viewport()
	var scale := clampf(float(v.render_scale), 0.5, 1.0)
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if scale < 0.99 else Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = scale
	var sh := clampi(int(v.shadows), 0, 3)
	vp.positional_shadow_atlas_size = [1024, 2048, 4096, 8192][sh]
	RenderingServer.directional_shadow_atlas_set_size([2048, 4096, 4096, 8192][sh], true)
	var soft: int = [RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW, RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM, RenderingServer.SHADOW_QUALITY_SOFT_HIGH][sh]
	RenderingServer.directional_soft_shadow_filter_set_quality(soft)
	RenderingServer.positional_soft_shadow_filter_set_quality(soft)
	var aa := clampi(int(v.aa), 0, 3)
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if aa == 1 else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.use_taa = aa == 2
	vp.msaa_3d = Viewport.MSAA_4X if aa == 3 else Viewport.MSAA_DISABLED
	var fog := clampi(int(v.fog), 0, 2)
	RenderingServer.environment_set_volumetric_fog_volume_size([48, 64, 128][fog], [48, 64, 96][fog])
	if main.env:
		main.env.ssao_enabled = bool(v.ssao)
		main.env.glow_enabled = bool(v.glow)
		main.env.volumetric_fog_temporal_reprojection_enabled = fog >= 1
		main.env.tonemap_exposure = 1.1 * float(v.brightness)
	if main.player and main.player.cam:
		main.player.cam.fov = float(v.fov)
	if main.hud and main.hud.has_method("set_opacity"):
		main.hud.set_opacity(float(v.hud_opacity))


## The keys: the defaults, with whatever's been rebound over them. ({"k": physical keycode} or {"m": mouse button})
static func apply_binds() -> void:
	for b in BINDABLE:
		var action: String = b[0]
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action)
		InputMap.action_add_event(action, bind_event(action))


static func bind_event(action: String) -> InputEvent:
	var b = v.binds.get(action, null)
	if typeof(b) == TYPE_DICTIONARY and b.has("m"):
		var m := InputEventMouseButton.new()
		m.button_index = int(b.m)
		return m
	var e := InputEventKey.new()
	if typeof(b) == TYPE_DICTIONARY and b.has("k"):
		e.physical_keycode = int(b.k)
	else:
		for d in BINDABLE:
			if d[0] == action:
				e.physical_keycode = d[2]
	return e


## What's on the key, for screens and prompts ("E", "MOUSE 4").
static func key_name(action: String) -> String:
	var e := bind_event(action)
	if e is InputEventMouseButton:
		return {MOUSE_BUTTON_LEFT: "LEFT CLICK", MOUSE_BUTTON_RIGHT: "RIGHT CLICK", MOUSE_BUTTON_MIDDLE: "MIDDLE CLICK",
			MOUSE_BUTTON_XBUTTON1: "MOUSE 4", MOUSE_BUTTON_XBUTTON2: "MOUSE 5"}.get(e.button_index, "MOUSE %d" % e.button_index)
	var k: int = (e as InputEventKey).physical_keycode
	var shown := DisplayServer.keyboard_get_label_from_physical(k) if DisplayServer.get_name() != "headless" else k
	return OS.get_keycode_string(shown if shown != KEY_NONE else k).to_upper()
