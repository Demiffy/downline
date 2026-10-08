# Player settings, kept in user://settings.cfg. Static so anything can read them (player reads sens/fov/bob).
extends RefCounted

const PATH := "user://settings.cfg"
const DEFAULTS := {
	"sens": 1.0, "invert_y": false, "fov": 80.0, "head_bob": true,
	"fullscreen": false, "vsync": true, "brightness": 1.0, "quality": 2,   # 0 low, 1 medium, 2 high
	"vol_master": 1.0, "vol_world": 1.0, "vol_ambience": 1.0,
	"mic_on": true, "voice_mode": 0, "voice_gate": 0.02, "mic_gain": 1.0, "voice_vol": 1.0,   # voice: 0 open mic, 1 push-to-talk (V)
	"player_name": "", "last_ip": "127.0.0.1", "last_port": 24565,
}
static var v := DEFAULTS.duplicate()


static func load_file() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	for k in DEFAULTS:
		v[k] = cf.get_value("settings", k, DEFAULTS[k])


static func save() -> void:
	var cf := ConfigFile.new()
	for k in v:
		cf.set_value("settings", k, v[k])
	cf.save(PATH)


## Window, audio buses, renderer quality, environment brightness; the player reads its own values live.
static func apply(main: Node) -> void:
	if DisplayServer.get_name() != "headless":
		var full := DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
		if full != bool(v.fullscreen):
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if v.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if v.vsync else DisplayServer.VSYNC_DISABLED)
	for bus in [["Master", "vol_master"], ["World", "vol_world"], ["Ambience", "vol_ambience"]]:
		var i := AudioServer.get_bus_index(bus[0])
		if i >= 0:
			AudioServer.set_bus_volume_db(i, linear_to_db(maxf(float(v[bus[1]]), 0.0001)))
			AudioServer.set_bus_mute(i, float(v[bus[1]]) <= 0.001)
	if main == null:
		return
	var q := int(v.quality)
	var vp: Viewport = main.get_viewport()
	vp.scaling_3d_scale = [0.67, 0.85, 1.0][q]
	vp.positional_shadow_atlas_size = [1024, 2048, 4096][q]
	if main.env:
		main.env.ssao_enabled = q >= 2
		main.env.glow_enabled = q >= 1
		main.env.volumetric_fog_temporal_reprojection_enabled = q >= 1
		main.env.tonemap_exposure = 1.1 * float(v.brightness)
	if main.player and main.player.cam:
		main.player.cam.fov = float(v.fov)
