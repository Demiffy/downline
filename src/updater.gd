# The launcher (run/main_scene): before the game proper is loaded, fetch a newer pack if GitHub
# has one, and run that instead of the one shipped next to the exe.
#
#   1. a pack downloaded last time (user://updates) that's newer than the exe's own, made for this
#      exe, and still matches its checksum, is loaded over the shipped one;
#   2. version.json from the latest GitHub Release says what's out: if it's newer, its pack is
#      downloaded (to a .part file, checked against its sha256, then renamed) and loaded too;
#   3. main.tscn. Nothing of the game has been loaded until here, so all of it comes from the
#      newest pack.
# All the while the intro (src/intro.gd) plays, the update check as lines of its boot log.
# Offline, a slow network, a bad download: the game starts as it is. Esc skips a download, any
# key hurries the intro. A build that needs a new exe (another Godot, or BASE bumped in
# version.gd) isn't downloaded: the player is told to get the full zip. Running from the project
# ("dev") or with `-- --no-update` there's no update check; headless, straight to the game.
# `-- --update-url=<url>` reads another version.json; `-- --intro` plays the full intro.
#
# version.json (tools/export.sh writes it):
#   {"version": "abc1234", "seq": 412, "base": 1, "godot": "4.7.2",
#    "pck_url": ".../releases/download/vabc1234/Downline.pck", "sha256": "...", "size": 1014420}
extends Control

const LATEST := "https://github.com/Demiffy/downline/releases/latest/download/version.json"
const RELEASES := "github.com/Demiffy/downline/releases"
const DIR := "user://updates"
const META := "user://updates/current.json"   # the pack in DIR: {file, version, seq, base, sha256}
const CHECK_TIMEOUT := 6.0
const STALL := 20.0   # a download that hasn't moved in this long is given up on
const SEEN := "user://updates/intro_seen.txt"   # the build the full intro last played for
const Intro = preload("res://src/intro.gd")

var _sounds := 0   # the sound library: 1 its script loading, 2 its sounds being made, 0 done (or not begun)
var _sfx: Script

var _base := 0          # the exe's pack (version.gd as shipped)
var _seq := 0           # what's running now: the shipped pack, or an update loaded over it
var _build := ""
var _check: HTTPRequest
var _dl: HTTPRequest
var _want := {}         # the version.json being downloaded
var _part := ""
var _moved := 0
var _still := 0.0
var _settled := false
var _started := false
var _intro


func _ready() -> void:
	preload("res://src/mark.gd").apply()   # (the window's icon)
	# (not cached: once an update is loaded, the game reads its own version.gd)
	var shipped: Script = ResourceLoader.load("res://src/version.gd", "", ResourceLoader.CACHE_MODE_IGNORE)
	_base = shipped.BASE
	_seq = shipped.SEQ
	_build = shipped.BUILD
	if DisplayServer.get_name() == "headless":
		_go.call_deferred()
		return
	var dev := _build == "dev" or "--no-update" in OS.get_cmdline_user_args()
	if not dev:
		_tidy()
		_load_cached()
	_intro = Intro.new()
	_intro.full = "--intro" in OS.get_cmdline_user_args() or not FileAccess.file_exists(SEEN) 		or FileAccess.get_file_as_string(SEEN).strip_edges() != _build
	add_child(_intro)
	_intro.done.connect(_go)
	_intro.line("head", "RAILNET FIELD SERVICE OS  4.7", "", false)
	_intro.line("head", "(C) BUREAU OF RECLAIMED MATERIALS", "", false)
	_intro.line("", "", "", false)
	_intro.line("mem", "MEMORY CHECK", "%dK OK" % int(OS.get_memory_info().get("physical", 0) / 1024))
	_intro.line("gpu", "VIDEO", RenderingServer.get_video_adapter_name().to_upper().left(34))
	_intro.line("radio", "RADIO", "OK" if AudioServer.get_input_device_list().size() > 1 else "NO MICROPHONE")
	_intro.line("track", "TRACK CIRCUIT", "OK")
	_intro.line("dispatch", "CONTACTING DISPATCH", null)
	_intro.line("build", "BUILD %s %s" % [_build, OS.get_name().to_upper()], null)
	if dev:
		_intro.status("dispatch", "DEV BUILD: NOT CHECKED")
		_settle()
		return
	_check = HTTPRequest.new()
	_check.timeout = CHECK_TIMEOUT
	add_child(_check)
	_check.request_completed.connect(_on_checked)
	var url := LATEST
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--update-url="):   # (testing: a version.json served from somewhere else)
			url = a.trim_prefix("--update-url=")
	if _check.request(url) != OK:
		_offline()


func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey or e is InputEventMouseButton or e is InputEventJoypadButton) or not e.is_pressed():
		return
	if e.is_action_pressed("ui_cancel") and _dl != null:
		_fail("skipped")   # (Esc during a download: play this build)
	elif _intro:
		_intro.hurry()


func _process(delta: float) -> void:
	if _sounds > 0:
		_sounds_tick()
	if _dl == null or _settled:
		return
	var got := _dl.get_downloaded_bytes()
	var total := maxi(_dl.get_body_size(), int(_want.get("size", 0)))
	if total > 0:
		_intro.progress("orders", float(got) / total, "RECEIVING %.1f/%.1f MB" % [got / 1048576.0, total / 1048576.0])
	if got != _moved:
		_moved = got
		_still = 0.0
	else:
		_still += delta
		if _still > STALL:
			_fail("stalled")


## Last time's update, if it's still the newest thing we have and nothing's wrong with it.
func _load_cached() -> void:
	var m := _meta()
	if m.is_empty() or int(m.seq) <= _seq or int(m.base) != _base:
		return
	var path := DIR.path_join(m.file)
	if not FileAccess.file_exists(path) or FileAccess.get_sha256(path) != m.sha256:
		return
	if ProjectSettings.load_resource_pack(path, true):
		_seq = int(m.seq)
		_build = m.version


func _on_checked(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if _settled:
		return
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_offline()   # no network, or no release yet
		return
	var j = JSON.parse_string(body.get_string_from_utf8())
	if typeof(j) != TYPE_DICTIONARY or not j.has_all(["version", "seq", "base", "godot", "pck_url", "sha256", "size"]):
		_offline()
		return
	if int(j.seq) <= _seq:
		_intro.status("dispatch", "NO NEW ORDERS")   # up to date (or this exe is newer than the release)
		_settle()
		return
	var engine := "%d.%d.%d" % [Engine.get_version_info().major, Engine.get_version_info().minor, Engine.get_version_info().patch]
	if int(j.base) != _base or str(j.godot) != engine:
		_intro.status("dispatch", "BUILD %s IS OUT" % j.version)
		_intro.line("full", "NEEDS THE FULL DOWNLOAD", RELEASES, true, "build")
		_settle()
		return
	_want = j
	_intro.status("dispatch", "NEW ORDERS: BUILD %s" % j.version)
	_intro.line("orders", "RECEIVING", null, true, "build")
	_intro.progress("orders", 0.0, "RECEIVING")
	_intro.full = true
	DirAccess.make_dir_recursive_absolute(DIR)
	_part = DIR.path_join("Downline-%d.pck.part" % int(j.seq))
	DirAccess.remove_absolute(_part)
	_dl = HTTPRequest.new()
	_dl.download_file = _part
	_dl.use_threads = true
	add_child(_dl)
	_dl.request_completed.connect(_on_downloaded)
	if _dl.request(str(j.pck_url)) != OK:
		_fail("couldn't start")


func _on_downloaded(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if _settled:
		return
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_fail("HTTP %d" % code)
		return
	if not FileAccess.file_exists(_part) or FileAccess.get_sha256(_part) != str(_want.sha256):
		_fail("damaged")
		return
	var file := "Downline-%d.pck" % int(_want.seq)
	var path := DIR.path_join(file)
	DirAccess.remove_absolute(path)
	if DirAccess.rename_absolute(_part, path) != OK or not ProjectSettings.load_resource_pack(path, true):
		_fail("couldn't install")
		return
	var f := FileAccess.open(META, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"file": file, "version": str(_want.version), "seq": int(_want.seq),
			"base": int(_want.base), "sha256": str(_want.sha256)}))
		f.close()
	_seq = int(_want.seq)
	_build = str(_want.version)
	_dl.queue_free()
	_dl = null
	_intro.status("orders", "INSTALLED", "RECEIVED")
	_settle()


func _offline() -> void:
	_intro.status("dispatch", "OFFLINE")
	_settle()


func _fail(why: String) -> void:
	if _dl:
		_dl.cancel_request()
		_dl.queue_free()
		_dl = null
	DirAccess.remove_absolute(_part)
	_intro.status("orders", "FAILED: %s" % why.to_upper(), "RECEIVING")
	_settle()


## Whatever happened with the update, this is the build that runs: the log can finish.
func _settle() -> void:
	if _settled:
		return
	_settled = true
	if _check:
		_check.cancel_request()
	_intro.status("build", "READY", "BUILD %s %s" % [_build, OS.get_name().to_upper()])
	# Now this build's own scripts can be read: its sounds are made here, on the log, before the game
	# (sfx.gd's warm-up, several at once; read on a thread so the screen keeps going meanwhile).
	_intro.line("sounds", "SOUND LIBRARY", null)
	ResourceLoader.load_threaded_request("res://src/sfx.gd")
	_sounds = 1


## The sound library: sfx.gd read in, its warm-up started, its progress on the log; the log finishes
## once every sound is made (cached from last time, that's at once).
func _sounds_tick() -> void:
	if _sounds == 1:
		if ResourceLoader.load_threaded_get_status("res://src/sfx.gd") != ResourceLoader.THREAD_LOAD_LOADED:
			return
		_sfx = ResourceLoader.load_threaded_get("res://src/sfx.gd")
		_sfx.warm()
		_sounds = 2
	var f: float = _sfx.warm_progress()
	if f < 1.0:
		_intro.progress("sounds", f, "SOUND LIBRARY")
	else:
		_intro.status("sounds", "READY", "SOUND LIBRARY")
		_intro.release()
		_sounds = 0


## Into the game, out of a dark screen that lifts off the menu.
func _go() -> void:
	if _started:
		return
	_started = true
	print("DOWNLINE build %s (#%d)" % [_build, _seq])
	if _intro:
		DirAccess.make_dir_recursive_absolute(DIR)
		var f := FileAccess.open(SEEN, FileAccess.WRITE)
		if f:
			f.store_string(_build)
			f.close()
		var layer := CanvasLayer.new()
		layer.layer = 100
		var shade := ColorRect.new()
		shade.color = Intro.SOOT
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(shade)
		shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		get_tree().root.add_child(layer)
		var tw := layer.create_tween()
		tw.tween_interval(0.15)
		tw.tween_property(shade, "modulate:a", 0.0, 0.7)
		tw.tween_callback(layer.queue_free)
	# No one-off sounds while the game builds itself (they blip); the intro's last ring plays on
	# through it, and the menu fades the world in.
	Engine.set_meta("hush", true)
	get_tree().change_scene_to_file("res://main.tscn")


func _meta() -> Dictionary:
	if not FileAccess.file_exists(META):
		return {}
	var m = JSON.parse_string(FileAccess.get_file_as_string(META))
	if typeof(m) != TYPE_DICTIONARY or not m.has_all(["file", "version", "seq", "base", "sha256"]):
		return {}
	return m


## Old packs, half downloads, and the first updater's files.
func _tidy() -> void:
	var keep: String = _meta().get("file", "")
	var d := DirAccess.open(DIR)
	if d == null:
		return
	for f in d.get_files():
		if f != keep and f != "current.json" and f != "intro_seen.txt":
			d.remove(f)   # (fails harmlessly on one that's in use)
