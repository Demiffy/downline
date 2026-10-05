# Pure-logic self-check. Run: godot --headless --path . -s tests/check.gd
extends SceneTree

const Terminal = preload("res://src/terminal.gd")
const Facility = preload("res://src/facility.gd")
const Data = preload("res://src/data.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if not cond:
		fails += 1
		printerr("FAIL: " + what)


func _initialize() -> void:
	# Terminal parsing / completion / typo help.
	check(Terminal.parse("  buy fla 2 ") == PackedStringArray(["BUY", "FLA", "2"]), "parse")
	check(Terminal.complete("LEAVE", ["LEAVE_CHECKPOINT", "LIST_LOGS"]) == "LEAVE_CHECKPOINT", "complete unique")
	check(Terminal.complete("SCAN_", ["SCAN_TRAIN", "SCAN_FACILITY"]) == "SCAN_", "complete common prefix")
	check(Terminal.complete("ZZ", ["HELP"]) == "ZZ", "complete no match")
	check(Terminal.complete("FLA", Data.SHOP) == "FLASHLIGHT", "shop shorthand")
	check(Terminal.closest("SCAN_TRIAN", ["SCAN_TRAIN", "HELP"]) == "SCAN_TRAIN", "did-you-mean")
	check(Terminal.closest("XYZZY", ["SCAN_TRAIN", "HELP"]) == "", "no bogus suggestion")

	# Facility layouts: right size, fully connected, deterministic, doors on real links.
	for seed in 40:
		var rooms := 6 + seed % 25
		var l := Facility.gen_layout(seed, rooms, 3)
		check(l.cells.size() == rooms, "room count seed %d" % seed)
		check(str(l) == str(Facility.gen_layout(seed, rooms, 3)), "deterministic seed %d" % seed)
		var seen := {Vector2i.ZERO: true}
		var todo: Array = [Vector2i.ZERO]
		while not todo.is_empty():
			for n in l.links[todo.pop_back()]:
				if not seen.has(n):
					seen[n] = true
					todo.append(n)
		check(seen.size() == rooms, "connected seed %d" % seed)
		for code in l.doors:
			var e: Array = l.doors[code]
			check(l.links[e[0]].has(e[1]) and not e.has(Vector2i.ZERO), "door on link seed %d" % seed)

	# Content sanity.
	for id in Data.ITEMS:
		var d: Dictionary = Data.ITEMS[id]
		check(d.has("name") and d.has("size") and d.has("res"), "item fields " + id)
		if Data.kind(id) == "scrap":
			check(not d.res.is_empty(), "scrap yields something " + id)
	check(Data.res_text({"copper": 3, "plastic": 1}) == "3 CU, 1 PLA", "res_text order")

	print("check.gd: %s" % ("ALL PASSED" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails else 0)
