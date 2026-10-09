# Scrap-loop depth: heavy items, supply crates, the vault, mezzanines, payload rank.
# Run: godot --headless --path . -s tests/loop.gd
extends SceneTree

var fails := 0


func check(cond: bool, what: String) -> void:
	print(("ok    " if cond else "FAIL  ") + what)
	if not cond:
		fails += 1


func frames(n: int) -> void:
	for i in n:
		await process_frame


func _initialize() -> void:
	_run()


func _run() -> void:
	Engine.set_meta("fast_test", true)
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await frames(10)
	var p = main.player
	main.term.run("LEAVE_CHECKPOINT")
	var stop: Dictionary = main.route[0][0]
	stop.theme = "FACTORY"
	stop.rooms = 24
	p.global_position = Vector3(0, 1.3, 0)
	main.term.run("ROUTE_TO " + stop.letter)
	while main.busy:
		await process_frame
	var fac = main.level.facility
	check(fac.vault_code != "" and fac.doors.has(fac.vault_code), "the facility has a vault behind bulkhead %s" % fac.vault_code)
	var heavy_in_vault: Array = main.get_tree().get_nodes_in_group("pickups").filter(func(n): return n.id in ["ENGINE_BLOCK", "TRANSFORMER", "SAFE_BOX"] and fac.cell_at(n.global_position) == fac.vault_cell)
	check(heavy_in_vault.size() >= 1, "the vault holds a heavy prize")
	# The vault keycard: one per site, well away from the vault; nothing else opens the door.
	var cards: Array = main.get_tree().get_nodes_in_group("pickups").filter(func(n): return n.id == "VAULT_KEYCARD")
	var vault_at: Vector3 = fac.to_global(Vector3(fac.vault_cell.x * fac.CELL, 0, fac.vault_cell.y * fac.CELL))
	check(cards.size() == 1 and cards[0].global_position.distance_to(vault_at) > 12.0, "one vault keycard lies somewhere far from the vault (%d, %.0f m)" % [cards.size(), cards[0].global_position.distance_to(vault_at) if not cards.is_empty() else 0.0])
	main.term.run("OPEN_BULKHEAD " + fac.vault_code)
	check(not fac.doors[fac.vault_code].get_meta("open"), "the terminal can't open the vault")
	var reader = fac.find_children("*", "StaticBody3D", true, false).filter(func(n): return n.has_meta("vault_reader"))
	check(reader.size() == 1, "there's a keycard reader by the vault door")
	if reader.size() == 1:
		p.slots[0] = null
		p.sel = 0
		reader[0].run(p)
		check(not fac.doors[fac.vault_code].get_meta("open"), "...an empty hand at the reader: access denied")
		p.slots[0] = {"id": "VAULT_KEYCARD", "charge": -1.0, "extra": {}}
		reader[0].run(p)
		check(fac.doors[fac.vault_code].get_meta("open") and p.slots[0] == null, "...the keycard in hand: the vault opens (and the card stays in the reader)")
	# Deposit boxes: pry one open, valuables fall out.
	var boxes: Array = fac.supplies.filter(func(b): return b.has_meta("deposit"))
	check(boxes.size() >= 2, "the vault has deposit boxes to pry open (%d)" % boxes.size())
	if not boxes.is_empty():
		var n0: int = main.get_tree().get_nodes_in_group("pickups").filter(func(n): return n.id in ["GOLD_BAR", "CASH_BOX", "BEARER_BONDS"]).size()
		fac._open_deposit(boxes[0])
		await frames(3)
		var n1: int = main.get_tree().get_nodes_in_group("pickups").filter(func(n): return n.id in ["GOLD_BAR", "CASH_BOX", "BEARER_BONDS"]).size()
		check(n1 > n0, "...one pried open: valuables inside (%d -> %d)" % [n0, n1])
	check(fac.kinds.values().has("atrium") == (fac.loot_spots.size() > 0), "mezzanine rooms register their loot spots")
	# Supply crate: opening spawns its contents (or tells you it's empty).
	var crate = null
	for n in fac.find_children("*", "StaticBody3D", true, false):
		if n.has_meta("crate"):
			crate = n.get_parent()
			break
	check(crate != null, "supply crates are placed")
	if crate:
		var before: int = main.get_tree().get_nodes_in_group("pickups").size()
		var tries := 0
		fac._open_supply(crate)
		await frames(3)
		check(crate.get_meta("opened", false), "a supply crate pries open")
		check(main.get_tree().get_nodes_in_group("pickups").size() >= before, "...and anything inside spills out")
	# Heavy: slow, no switching, set down in front.
	p.global_position = main.level.elevator_pos + Vector3(0, 0.3, -6)
	p.slots = [null, null, null, null, null, null]
	var block = main.spawn_item("ENGINE_BLOCK", p.global_position + Vector3(0, 0.5, -1.0))
	await frames(2)
	p._pick(block)
	await frames(2)
	check(p.carrying_heavy(), "you can lift an engine block")
	p._select(p.sel + 1)
	check(p.carrying_heavy(), "...and can't switch slots while carrying it")
	var spare = main.spawn_item("PENNY", p.global_position + Vector3(0, 0.5, -1.0))
	await frames(2)
	p._pick(spare)
	check(is_instance_valid(spare) and not spare.is_queued_for_deletion(), "...or pick anything else up")
	p._drop()
	await frames(5)
	check(not p.carrying_heavy(), "set it down again")
	# Payload rank pays a bonus once you beat the quota's worth.
	main.at_checkpoint = true
	main.assignment = 1
	main.quota = {"steel": 2, "copper": 2, "rubber": 2, "plastic": 2}
	var c0: int = main.credits
	main._cp_value = 0.0
	main._rank_bonus_paid = 0
	main._rank_payload(1000.0)
	check(main.payload_rank == "S" and main.credits == c0 + 150, "payload rank S pays the Bureau bonus (%s, +%d)" % [main.payload_rank, main.credits - c0])
	main._rank_payload(10.0)
	check(main.credits == c0 + 150, "...only once")
	print("loop.gd: %s" % ("ALL PASSED" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails else 0)
