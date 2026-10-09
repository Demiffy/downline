# Save and continue a run. One run on disk (user://run.save), written by whoever runs the world
# (solo, or the host): on arriving anywhere, every two minutes, and on SAVE & QUIT. Game over
# deletes it.
#
# What's kept: the shift's state (credits, quota, route, upgrades, the clock...), where we are (the
# stop and its seed, so the same site is rebuilt), every item aboard the train and every item left
# at the stop (scrap, tools, photos pinned up, bodies), which supply crates are open, the crew's
# pockets by name, and every photo taken this run. Creatures and hazards come back fresh from the
# seed; events that already happened today don't happen again.
extends RefCounted

const Data = preload("res://src/data.gd")
const VERSION := 1
const PATH := "user://run.save"


static func exists(path := PATH) -> bool:
	return FileAccess.file_exists(path) and peek(path) != {}


## The save's header for the title screen: {"assignment", "where", "credits", "crew"}; {} if none.
static func peek(path := PATH) -> Dictionary:
	var d := _read(path)
	if d.is_empty():
		return {}
	var st: Dictionary = d.state
	return {"assignment": st.assignment, "credits": st.credits, "where": "CHECKPOINT" if d.stop.theme == "CHECKPOINT" else "STATION %s" % d.stop.letter,
		"hours": st.hours, "crew": d.get("crew", {}).keys()}


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
	if not (d is Dictionary) or d.get("version", 0) != VERSION:
		return {}
	return d


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
			"pos": xf.origin, "rot": xf.basis.get_rotation_quaternion(), "pin": p.has_node("Tack"), "no_possess": p.has_meta("no_possess")})
	var pl = main.player
	var mine := {"slots": pl.slots.map(func(it): return net.item_to_wire(it) if it != null else null),
		"equip": net.item_to_wire(pl.equip) if pl.equip != null else null,
		"hp": pl.hp if not pl.dead else 100.0, "helmet": pl.helmet_charge, "sel": pl.sel}
	var opened := []
	if main.level != null and main.level.facility != null:
		var fac = main.level.facility
		for c in fac.crates:
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
	var st: Dictionary = d.state
	if main.level != null:
		main.level.free()
		main.level = null
	main.level_serial = 0
	main._load_level(d.stop, d.seed)
	_apply_state(main, st)
	main._cp_value = d.cp_value
	main._rank_bonus_paid = d.rank_paid
	if d.gate_open:
		main.level.open_gate()
	main._orders = d.orders.duplicate()
	# The stop is rebuilt from its seed: put back what was there instead of what it starts with.
	var lvl = main.level
	for p in main.get_tree().get_nodes_in_group("pickups"):
		if lvl.is_ancestor_of(p):
			p.free()
	if lvl.facility != null:
		for at in d.crates:
			for c in lvl.facility.crates:
				if is_instance_valid(c) and lvl.facility.to_local(c.global_position).distance_to(at) < 0.05:
					lvl.facility.mark_opened(c)
	if lvl.hazards != null:   # what already happened today doesn't happen again
		lvl.hazards.events = lvl.hazards.events.filter(func(e): return e[0] > main.hours)
	for it in d.items:
		var parent = main.train if it.frame == "T" else lvl
		var xf: Transform3D = parent.global_transform * Transform3D(Basis(it.rot), it.pos)
		var p = main.spawn_item(it.id, xf.origin, it.charge, parent)
		if p == null:
			continue
		if it.id == "REMAINS":
			p.rotation.y = xf.basis.get_euler().y
		else:
			p.global_basis = xf.basis
		p.set_extra(net.wire_to_extra(it.extra))
		if it.get("no_possess", false):
			p.set_meta("no_possess", true)
		if it.get("pin", false) and p.has_method("pin"):
			p.pin()
		elif it.id == "PHOTO":
			p.add_to_group("photos")
	var pl = main.player
	var mine: Dictionary = d.player
	pl.slots = mine.slots.map(func(w): return net.wire_to_item(w) if w != null else null)
	while pl.slots.size() < 7:
		pl.slots.append(null)
	pl.equip = net.wire_to_item(mine.equip) if mine.equip != null else null
	pl.sel = mine.get("sel", 0)
	pl.hp = mine.hp
	pl.helmet_charge = mine.helmet
	pl.global_position = main.train.to_global(Vector3(-2.0, 1.3, 0.0))
	pl.velocity = Vector3.ZERO
	main.crew_pockets = d.crew.duplicate(true)
	main.photo_log = d.photos.map(func(w): return net.wire_to_extra(w))
	if not main._orders.is_empty():
		main._dispatch_handcar.call_deferred()
	return true


static func _apply_state(main, st: Dictionary) -> void:
	main.credits = st.credits
	main.assignment = st.assignment
	main.quota = st.quota
	main.submitted = st.submitted
	main.prices = st.prices
	main.route = st.route
	main.taken = st.taken
	main.stage = st.stage
	main.departed = st.departed
	main.hours = st.hours
	main.warned = st.warned
	main.logs_unlocked = st.logs
	main.stats = st.stats
	main.payload_rank = st.rank
	main._letter = st.letter
	for u in st.upgrades:
		if not main.upgrades.has(u):
			main.upgrades[u] = true
			match u:
				"BETTER_BOOTS": main.player.max_stamina = main.player.MAX_STAMINA * 2.0
				"STORAGE_CAR": main.train.add_storage_car()
				"DIGITAL_CLOCK": main.train.add_digital_clock()
