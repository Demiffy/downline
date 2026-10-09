# Save and continue a run. One run on disk (user://run.save), written by whoever runs the world
# (solo, or the host): on arriving anywhere, every two minutes, and on SAVE & QUIT. Game over
# deletes it.
#
# What's kept: the shift's state (credits, quota, route, upgrades, the clock...), where we are (the
# stop and its seed, so the same site is rebuilt), every item aboard the train and every item left
# at the stop (scrap, tools, photos pinned up, bodies), which supply crates are open, the crew's
# pockets by name, and every photo taken this run. Creatures and hazards come back fresh from the
# seed; events that already happened today don't happen again.
#
# Saves carry over game updates: user:// stays the same from build to build, any older save
# version loads (every field read with a default), and whatever the new build no longer has (an
# item, an upgrade, a kind of site) is left out instead of breaking the load. Bump VERSION when
# the format changes, and keep reading the old one in _read / restore.
extends RefCounted

const Data = preload("res://src/data.gd")
const VERSION := 2
const PATH := "user://run.save"


static func exists(path := PATH) -> bool:
	return FileAccess.file_exists(path) and peek(path) != {}


## The save's header for the title screen: {"assignment", "where", "credits", "crew"}; {} if none.
static func peek(path := PATH) -> Dictionary:
	var d := _read(path)
	if d.is_empty():
		return {}
	var st: Dictionary = d.get("state", {})
	var stop: Dictionary = d.get("stop", {})
	return {"assignment": st.get("assignment", 0), "credits": st.get("credits", 0),
		"where": "CHECKPOINT" if stop.get("theme", "CHECKPOINT") == "CHECKPOINT" else "STATION %s" % stop.get("letter", "?"),
		"hours": st.get("hours", 8.0), "crew": d.get("crew", {}).keys()}


static func delete(path := PATH) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var d = f.get_var()
	if not (d is Dictionary) or int(d.get("version", 0)) < 1 or not d.has("state") or not d.has("stop"):
		return {}
	return d   # (an older version loads too: restore reads every field with a default)


# --- writing ----------------------------------------------------------------------------------

static func capture(main) -> Dictionary:
	var net = main.net
	var items := []
	for p in main.get_tree().get_nodes_in_group("pickups"):
		if p.is_queued_for_deletion() or not p.is_inside_tree():
			continue
		var frame := ""
		var base: Transform3D
		var at: Transform3D = p.global_transform
		if p.id == "REMAINS" and "parts" in p and not p.parts.is_empty():   # (a ragdoll: where its body lies)
			var b = p.parts.get("pelvis", p.parts.values()[0])
			at = Transform3D(Basis(Vector3.UP, b.global_rotation.y), b.global_position + Vector3(0, 0.15, 0))
		if main.train.is_ancestor_of(p) or main.train.contains(at.origin):
			frame = "T"
			base = main.train.global_transform
		elif main.level != null and main.level.is_ancestor_of(p):
			frame = "L"
			base = main.level.global_transform
		else:
			continue
		var xf: Transform3D = base.affine_inverse() * at
		items.append({"id": p.id, "charge": p.charge, "extra": net.extra_to_wire(p.extra), "frame": frame,
			"pos": xf.origin, "rot": xf.basis.get_rotation_quaternion(), "pin": p.has_node("Tack"), "no_possess": p.has_meta("no_possess"),
			"who": p.get_meta("who", "")})
	var pl = main.player
	var mine := {"slots": pl.slots.map(func(it): return net.item_to_wire(it) if it != null else null),
		"equip": net.item_to_wire(pl.equip) if pl.equip != null else null,
		"hp": pl.hp if not pl.dead else 100.0, "helmet": pl.helmet_charge, "sel": pl.sel}
	var opened := []
	if main.level != null and main.level.facility != null:
		var fac = main.level.facility
		for c in fac.supplies:   # (supply crates and the vault's deposit boxes)
			if is_instance_valid(c) and c.get_meta("opened", false):
				opened.append(fac.to_local(c.global_position))
	return {
		"version": VERSION,
		"saved_at": Time.get_datetime_string_from_system(),
		"state": main.net_state(),
		"stop": main.stop,
		"seed": main.level_seed,
		"cp_value": main._cp_value,
		"rank_paid": main._rank_bonus_paid,
		"gate_open": main.at_checkpoint and main.level != null and main.level.gate_light != null and main.level.gate_light.light_color.g > 0.5,
		"orders": main._orders.duplicate(),
		"items": items,
		"player": mine,
		"crew": main.crew_pockets.duplicate(true),
		"crates": opened,
		"vault_open": main.level != null and main.level.facility != null and main.level.facility.vault_code != "" and main.level.facility.doors[main.level.facility.vault_code].get_meta("open"),
		"photos": main.photo_log.map(func(e): return net.extra_to_wire(e)),
	}


static func write(main, path := PATH) -> bool:
	var d := capture(main)
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_var(d)
	f.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path))   # (never half a save)
	return true


# --- reading ----------------------------------------------------------------------------------

## Rebuild the run in `main` (a fresh game at the checkpoint). False if there's nothing to load.
static func restore(main, path := PATH) -> bool:
	var d := _read(path)
	if d.is_empty():
		return false
	var net = main.net
	for p in main.get_tree().get_nodes_in_group("pickups"):   # (the starter kit)
		p.free()
	var st: Dictionary = d.get("state", {})
	var stop: Dictionary = d.get("stop", {}).duplicate()
	if stop.get("theme", "CHECKPOINT") != "CHECKPOINT" and not Data.THEMES.has(stop.get("theme", "")):
		stop = main.CHECKPOINT_STOP   # (a kind of site this build no longer has: back at the checkpoint)
	for k in ["letter", "rooms", "weather", "biome"]:   # (fields a newer build expects)
		if stop.get("theme") != "CHECKPOINT" and not stop.has(k):
			stop[k] = {"letter": "A", "rooms": 12, "weather": "CLEAR", "biome": "DESERT"}[k]
	if main.level != null:
		main.level.free()
		main.level = null
	main.level_serial = 0
	main._load_level(stop, int(d.get("seed", 1)))
	_apply_state(main, st)
	main._cp_value = d.get("cp_value", 0.0)
	main._rank_bonus_paid = d.get("rank_paid", 0)
	if d.get("gate_open", false) and main.level.has_method("open_gate"):
		main.level.open_gate()
	main._orders = d.get("orders", []).filter(func(id): return Data.ITEMS.has(id))
	# The stop is rebuilt from its seed: put back what was there instead of what it starts with.
	var lvl = main.level
	for p in main.get_tree().get_nodes_in_group("pickups"):
		if lvl.is_ancestor_of(p):
			p.free()
	if lvl.facility != null:
		for at in d.get("crates", []):
			for c in lvl.facility.supplies:
				if is_instance_valid(c) and lvl.facility.to_local(c.global_position).distance_to(at) < 0.05:
					lvl.facility.mark_opened(c)
	if d.get("vault_open", false) and lvl.facility != null and lvl.facility.vault_code != "":
		lvl.facility.open_vault()
	if lvl.hazards != null:   # what already happened today doesn't happen again
		lvl.hazards.events = lvl.hazards.events.filter(func(e): return e[0] > main.hours)
	for it in d.get("items", []):
		if not Data.ITEMS.has(it.get("id", "")):
			continue   # (gone from this build)
		var parent = main.train if it.get("frame", "T") == "T" else lvl
		var xf: Transform3D = parent.global_transform * Transform3D(Basis(it.get("rot", Quaternion.IDENTITY)), it.get("pos", Vector3(0, 1.5, 0)))
		var p = main.spawn_item(it.id, xf.origin, it.get("charge", -1.0), parent)
		if p == null:
			continue
		if it.id == "REMAINS":
			p.rotation.y = xf.basis.get_euler().y
		else:
			p.global_basis = xf.basis
		p.set_extra(net.wire_to_extra(it.get("extra", {})))
		if it.get("no_possess", false):
			p.set_meta("no_possess", true)
		if it.get("who", "") != "":
			p.set_meta("who", it.who)
		if it.get("pin", false) and p.has_method("pin"):
			p.pin()
		elif it.id == "PHOTO":
			p.add_to_group("photos")
	var pl = main.player
	var mine: Dictionary = d.get("player", {})
	var known := func(w): return w != null and Data.ITEMS.has(w.get("id", ""))
	pl.slots = mine.get("slots", []).map(func(w): return net.wire_to_item(w) if known.call(w) else null)
	while pl.slots.size() < 7:
		pl.slots.append(null)
	var eq = mine.get("equip")
	pl.equip = net.wire_to_item(eq) if known.call(eq) else null
	pl.sel = clampi(int(mine.get("sel", 0)), 0, 6)
	pl.hp = float(mine.get("hp", 100.0))
	pl.helmet_charge = float(mine.get("helmet", pl.helmet_charge))
	pl.global_position = main.train.to_global(Vector3(-2.0, 1.3, 0.0))
	pl.velocity = Vector3.ZERO
	var pockets: Dictionary = d.get("crew", {}).duplicate(true)
	for who in pockets:
		pockets[who] = pockets[who].filter(func(w): return known.call(w))
	main.crew_pockets = pockets
	main.photo_log = d.get("photos", []).map(func(w): return net.wire_to_extra(w))
	if not main._orders.is_empty():
		main._dispatch_handcar.call_deferred()
	return true


static func _apply_state(main, st: Dictionary) -> void:
	main.credits = int(st.get("credits", main.credits))
	main.assignment = int(st.get("assignment", main.assignment))
	var quota: Dictionary = st.get("quota", {}).duplicate()
	var submitted: Dictionary = st.get("submitted", {}).duplicate()
	for r in Data.RES:   # (every resource has a number, new ones included)
		quota[r] = quota.get(r, 0)
		submitted[r] = submitted.get(r, 0)
	main.quota = quota
	main.submitted = submitted
	for r in Data.RES:   # (prices for every resource, new ones included)
		if not st.get("prices", {}).has(r):
			st["prices"] = st.get("prices", {}).duplicate()
			st.prices[r] = Data.BASE_PRICE[r]
	main.prices = st.get("prices", main.prices)
	main.route = st.get("route", [])
	main.taken = st.get("taken", [])
	main.stage = int(st.get("stage", -1))
	main.departed = bool(st.get("departed", false))
	main.hours = float(st.get("hours", 8.0))
	main.warned = int(st.get("warned", 0))
	main.logs_unlocked = mini(int(st.get("logs", 0)), Data.LOGS.size())
	var stats: Dictionary = main.stats.duplicate()
	stats.merge(st.get("stats", {}), true)
	main.stats = stats
	main.payload_rank = st.get("rank", "-")
	main._letter = int(st.get("letter", 0))
	for u in st.get("upgrades", {}):
		if not Data.UPGRADES.has(u):
			continue   # (gone from this build)
		if not main.upgrades.has(u):
			main.upgrades[u] = true
			match u:
				"BETTER_BOOTS": main.player.max_stamina = main.player.MAX_STAMINA * 2.0
				"STORAGE_CAR": main.train.add_storage_car()
				"DIGITAL_CLOCK": main.train.add_digital_clock()
				"INFIRMARY", "WEATHERVANE": main.train.show_upgrade(u)
