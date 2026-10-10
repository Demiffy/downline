# Auto-updater: checks GitHub Releases for a newer .pck on launch, downloads it into
# user://updates/, and loads it with ProjectSettings.load_resource_pack() so it overrides
# every built-in resource.  Falls back silently to the current version on any failure.
#
# Boot order:  updater.tscn (_ready)  -→  check version  -→  maybe download  -→  main.tscn
#
# The remote version.json (attached to each GitHub Release) looks like:
#   {"version": "abc1234", "pck_url": "https://github.com/Demiffy/downline/releases/download/vabc1234/Downline.pck"}
extends Control

const REPO := "Demiffy/downline"
const VERSION_URL := "https://github.com/%s/releases/latest/download/version.json" % REPO
const UPDATE_DIR := "user://updates"
const PCK_PATH := "user://updates/Downline.pck"
const VER_PATH := "user://updates/version.txt"      # remembers which version the cached pck is
const TIMEOUT := 8.0   # seconds before giving up on the network
const AMBER := Color(1.0, 0.62, 0.22)
const DIM := Color(0.62, 0.55, 0.45)
const INK := Color(0.95, 0.93, 0.88)
const SOOT := Color(0.055, 0.05, 0.045)

var _bar: ProgressBar
var _label: Label
var _sub: Label
var _http: HTTPRequest
var _dl: HTTPRequest
var _remote_ver := ""
var _pck_url := ""
var _gave_up := false


func _ready() -> void:
	# ── load a previously-downloaded update pck if it matches or is newer ──
	_load_cached_pck()

	# ── minimal UI: centred status + progress bar ──
	var bg := ColorRect.new()
	bg.color = SOOT
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(vb)
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["Menlo", "Consolas", "DejaVu Sans Mono", "monospace"])
	mono.font_weight = 700

	_label = Label.new()
	_label.text = "CHECKING FOR UPDATES..."
	_label.add_theme_font_override("font", mono)
	_label.add_theme_font_size_override("font_size", 22)
	_label.add_theme_color_override("font_color", INK)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_label)

	_sub = Label.new()
	_sub.text = "build %s" % _current_version()
	_sub.add_theme_font_override("font", mono)
	_sub.add_theme_font_size_override("font_size", 14)
	_sub.add_theme_color_override("font_color", DIM)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_sub)

	var spacer := Control.new()
	spacer.custom_minimum_size.y = 18
	vb.add_child(spacer)

	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(360, 14)
	_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_bar.max_value = 1.0
	_bar.value = 0.0
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.08)
	sb.corner_radius_top_left = 3
	sb.corner_radius_top_right = 3
	sb.corner_radius_bottom_left = 3
	sb.corner_radius_bottom_right = 3
	_bar.add_theme_stylebox_override("background", sb)
	var sf := StyleBoxFlat.new()
	sf.bg_color = AMBER
	sf.corner_radius_top_left = 3
	sf.corner_radius_top_right = 3
	sf.corner_radius_bottom_left = 3
	sf.corner_radius_bottom_right = 3
	_bar.add_theme_stylebox_override("fill", sf)
	_bar.show_percentage = false
	vb.add_child(_bar)
	_bar.visible = false

	# ── version check ──
	_http = HTTPRequest.new()
	_http.timeout = TIMEOUT
	add_child(_http)
	_http.request_completed.connect(_on_version_check)
	var err := _http.request(VERSION_URL)
	if err != OK:
		_skip("no internet")


func _current_version() -> String:
	# version.gd is always available (either built-in or from a loaded update pck)
	return load("res://src/version.gd").BUILD


func _load_cached_pck() -> void:
	if not FileAccess.file_exists(PCK_PATH):
		return
	# read what version the cached pck belongs to
	var cached_ver := ""
	if FileAccess.file_exists(VER_PATH):
		var f := FileAccess.open(VER_PATH, FileAccess.READ)
		if f:
			cached_ver = f.get_as_text().strip_edges()
	if cached_ver == "" or cached_ver == _current_version():
		if cached_ver == _current_version():
			return   # already running this version's code from the embedded pck
		# unknown version tag but a pck exists: try loading it anyway
	# load the update pck; its resources override the built-in ones
	ProjectSettings.load_resource_pack(PCK_PATH, true)


func _on_version_check(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if code != 200:
		_skip("offline")
		return
	var json = JSON.parse_string(body.get_string_from_utf8())
	if json == null or typeof(json) != TYPE_DICTIONARY:
		_skip("bad version file")
		return
	_remote_ver = str(json.get("version", ""))
	_pck_url = str(json.get("pck_url", ""))
	if _remote_ver == "" or _pck_url == "":
		_skip("incomplete version file")
		return

	# already up to date?
	var local := _current_version()
	var cached_ver := ""
	if FileAccess.file_exists(VER_PATH):
		var f := FileAccess.open(VER_PATH, FileAccess.READ)
		if f:
			cached_ver = f.get_as_text().strip_edges()

	if _remote_ver == local or _remote_ver == cached_ver:
		_skip("up to date")
		return

	# ── download the new pck ──
	_label.text = "UPDATING..."
	_sub.text = "%s  →  %s" % [local, _remote_ver]
	_bar.visible = true
	_bar.value = 0.0
	DirAccess.make_dir_recursive_absolute(UPDATE_DIR)
	_dl = HTTPRequest.new()
	_dl.timeout = 120.0
	_dl.download_file = ProjectSettings.globalize_path(PCK_PATH)
	add_child(_dl)
	_dl.request_completed.connect(_on_download_done)
	var err := _dl.request(_pck_url)
	if err != OK:
		_skip("download failed to start")


func _process(_delta: float) -> void:
	if _dl != null and _dl.get_body_size() > 0:
		_bar.value = float(_dl.get_downloaded_bytes()) / float(_dl.get_body_size())


func _on_download_done(_result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if code != 200 and code != 302 and code != 301:
		_skip("download failed (HTTP %d)" % code)
		return
	if not FileAccess.file_exists(PCK_PATH):
		_skip("download didn't save")
		return
	# stamp the version so we know what's cached
	var f := FileAccess.open(VER_PATH, FileAccess.WRITE)
	if f:
		f.store_string(_remote_ver)
	# load the fresh pck over the running resources
	ProjectSettings.load_resource_pack(PCK_PATH, true)
	_bar.value = 1.0
	_label.text = "UPDATED TO %s" % _remote_ver
	_sub.text = "starting..."
	# brief pause so the player sees it worked, then launch the game
	get_tree().create_timer(0.8).timeout.connect(_launch)


func _skip(reason: String) -> void:
	if _gave_up:
		return
	_gave_up = true
	_sub.text = reason if reason != "up to date" else "build %s" % _current_version()
	_launch()


func _launch() -> void:
	get_tree().change_scene_to_file("res://main.tscn")
