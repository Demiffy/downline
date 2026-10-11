# The launcher (run/main_scene): before the game proper is loaded, fetch a newer pack if GitHub
# has one, and run that instead of the one shipped next to the exe.
#
#   1. a pack downloaded last time (user://updates) that's newer than the exe's own, made for this
#      exe, and still matches its checksum, is loaded over the shipped one;
#   2. version.json from the latest GitHub Release says what's out: if it's newer, its pack is
#      downloaded (to a .part file, checked against its sha256, then renamed) and loaded too;
#   3. main.tscn. Nothing of the game has been loaded until here, so all of it comes from the
#      newest pack.
# Offline, a slow network, a bad download: the game starts as it is. Esc skips the wait.
# A build that needs a new exe (another Godot, or BASE bumped in version.gd) isn't downloaded:
# the player is told to get the full zip. Running from the project ("dev"), headless, or with
# `-- --no-update`, it goes straight to the game. `-- --update-url=<url>` reads another version.json.
#
# version.json (tools/export_windows.sh writes it):
#   {"version": "abc1234", "seq": 412, "base": 1, "godot": "4.7.2",
#    "pck_url": ".../releases/download/vabc1234/Downline.pck", "sha256": "...", "size": 1014420}
extends Control

const LATEST := "https://github.com/Demiffy/downline/releases/latest/download/version.json"
const RELEASES := "github.com/Demiffy/downline/releases"
const DIR := "user://updates"
const META := "user://updates/current.json"   # the pack in DIR: {file, version, seq, base, sha256}
const CHECK_TIMEOUT := 6.0
const STALL := 20.0   # a download that hasn't moved in this long is given up on
const AMBER := Color(1.0, 0.62, 0.22)
const DIM := Color(0.62, 0.55, 0.45)
const INK := Color(0.95, 0.93, 0.88)
const SOOT := Color(0.055, 0.05, 0.045)

var _base := 0          # the exe's pack (version.gd as shipped)
var _seq := 0           # what's running now: the shipped pack, or an update loaded over it
var _build := ""
var _check: HTTPRequest
var _dl: HTTPRequest
var _want := {}         # the version.json being downloaded
var _part := ""
var _moved := 0
var _still := 0.0
var _started := false
var _title: Label
var _sub: Label
var _bar: ProgressBar


func _ready() -> void:
	# (not cached: once an update is loaded, the game reads its own version.gd)
	var shipped: Script = ResourceLoader.load("res://src/version.gd", "", ResourceLoader.CACHE_MODE_IGNORE)
	_base = shipped.BASE
	_seq = shipped.SEQ
	_build = shipped.BUILD
	if _build == "dev" or DisplayServer.get_name() == "headless" or "--no-update" in OS.get_cmdline_user_args():
		_start.call_deferred()
		return
	_ui()
	_tidy()
	_load_cached()
	_sub.text = "BUILD %s" % _build
	_check = HTTPRequest.new()
	_check.timeout = CHECK_TIMEOUT
	add_child(_check)
	_check.request_completed.connect(_on_checked)
	var url := LATEST
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--update-url="):   # (testing: a version.json served from somewhere else)
			url = a.trim_prefix("--update-url=")
	if _check.request(url) != OK:
		_start()


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel"):
		_start()


func _process(delta: float) -> void:
	if _dl == null or _started:
		return
	var got := _dl.get_downloaded_bytes()
	var total := maxi(_dl.get_body_size(), int(_want.get("size", 0)))
	if total > 0:
		_bar.value = float(got) / total
		_sub.text = "%s  >  %s     %.1f / %.1f MB     ESC TO SKIP" % [_build, _want.version, got / 1048576.0, total / 1048576.0]
	if got != _moved:
		_moved = got
		_still = 0.0
	else:
		_still += delta
		if _still > STALL:
			_fail("download stalled")


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
	if _started:
		return
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_start()   # offline, or no release yet
		return
	var j = JSON.parse_string(body.get_string_from_utf8())
	if typeof(j) != TYPE_DICTIONARY or not j.has_all(["version", "seq", "base", "godot", "pck_url", "sha256", "size"]):
		_start()
		return
	if int(j.seq) <= _seq:
		_start()   # up to date (or this exe is newer than the release)
		return
	var engine := "%d.%d.%d" % [Engine.get_version_info().major, Engine.get_version_info().minor, Engine.get_version_info().patch]
	if int(j.base) != _base or str(j.godot) != engine:
		_title.text = "BUILD %s IS OUT" % j.version
		_sub.text = "IT NEEDS THE FULL DOWNLOAD:  %s\nSTARTING THIS ONE IN A MOMENT" % RELEASES
		get_tree().create_timer(5.0).timeout.connect(_start)
		return
	_want = j
	DirAccess.make_dir_recursive_absolute(DIR)
	_part = DIR.path_join("Downline-%d.pck.part" % int(j.seq))
	DirAccess.remove_absolute(_part)
	_title.text = "UPDATING"
	_bar.visible = true
	_dl = HTTPRequest.new()
	_dl.download_file = _part
	_dl.use_threads = true
	add_child(_dl)
	_dl.request_completed.connect(_on_downloaded)
	if _dl.request(str(j.pck_url)) != OK:
		_fail("couldn't start the download")


func _on_downloaded(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if _started:
		return
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_fail("download failed (%d)" % code)
		return
	if not FileAccess.file_exists(_part) or FileAccess.get_sha256(_part) != str(_want.sha256):
		_fail("download was damaged")
		return
	var file := "Downline-%d.pck" % int(_want.seq)
	var path := DIR.path_join(file)
	DirAccess.remove_absolute(path)
	if DirAccess.rename_absolute(_part, path) != OK or not ProjectSettings.load_resource_pack(path, true):
		_fail("couldn't install the update")
		return
	var f := FileAccess.open(META, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"file": file, "version": str(_want.version), "seq": int(_want.seq),
			"base": int(_want.base), "sha256": str(_want.sha256)}))
		f.close()
	_seq = int(_want.seq)
	_build = str(_want.version)
	_bar.value = 1.0
	_title.text = "UPDATED"
	_sub.text = "BUILD %s" % _build
	_dl.queue_free()
	_dl = null
	get_tree().create_timer(0.6).timeout.connect(_start)


func _fail(why: String) -> void:
	if _dl:
		_dl.cancel_request()
		_dl.queue_free()
		_dl = null
	DirAccess.remove_absolute(_part)
	_title.text = "UPDATE FAILED"
	_sub.text = "%s: STARTING BUILD %s" % [why.to_upper(), _build]
	get_tree().create_timer(2.0).timeout.connect(_start)


func _start() -> void:
	if _started:
		return
	_started = true
	print("DOWNLINE build %s (#%d)" % [_build, _seq])
	if _check:
		_check.cancel_request()
	if _dl:
		_dl.cancel_request()
		DirAccess.remove_absolute(_part)
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
		if f != keep and f != "current.json":
			d.remove(f)   # (fails harmlessly on one that's in use)


func _ui() -> void:
	var bg := ColorRect.new()
	bg.color = SOOT
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 10)
	add_child(vb)
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["Consolas", "Menlo", "DejaVu Sans Mono", "monospace"])
	mono.font_weight = 700
	_title = Label.new()
	_title.text = "CHECKING FOR UPDATES"
	_sub = Label.new()
	for l: Label in [_title, _sub]:
		l.add_theme_font_override("font", mono)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(l)
	_title.add_theme_font_size_override("font_size", 22)
	_title.add_theme_color_override("font_color", INK)
	_sub.add_theme_font_size_override("font_size", 13)
	_sub.add_theme_color_override("font_color", DIM)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(360, 10)
	_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_bar.max_value = 1.0
	_bar.show_percentage = false
	_bar.visible = false
	for k in ["background", "fill"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = AMBER if k == "fill" else Color(1, 1, 1, 0.08)
		sb.set_corner_radius_all(2)
		_bar.add_theme_stylebox_override(k, sb)
	vb.add_child(_bar)
