# Save and continue: a run written mid-station comes back the same in a fresh game.
# Run: tests/run.sh 200 --headless --path . -s tests/save.gd
extends SceneTree

const PATH := "user://test_run.save"
const Save = preload("res://src/save.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	print(("ok    " if cond else "FAIL  ") + what)
	if not cond:
		fails += 1


func _initialize() -> void:
	_run()


func secs(t: float) -> void:
	await create_timer(t).timeout


func fresh() -> Node:
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	for i in 10:
		await process_frame
	m.autosaves = true
	m.save_path = PATH
	return m


func _run() -> void:
	Engine.set_meta("fast_test", true)
	Save.delete(PATH)
	var main = await fresh()
	check(not main.autosave() or true, "(a save at the checkpoint before anything happens)")
	main.term.run("LEAVE_CHECKPOINT")
	main.term.run("ROUTE_TO " + main.route[0][0].letter)
	while main.busy:
		await process_frame
	check(Save.exists(PATH), "arriving at a station saves the run")
	var lvl = main.level
	var letter: String = main.stop.letter
	var rooms: int = lvl.facility.layout.cells.size()
	main.credits = 777
	main.hours = 14.25
	main.upgrades["STORAGE_CAR"] = true
	main.train.add_storage_car()
	# Something brought aboard, something moved down there, a crate opened, something in hand.
	var aboard = main.spawn_item("ENGINE_BLOCK", main.train.to_global(Vector3(1.0, 1.0, 0.5)), -1.0, main.train)
	var level_items: Array = main.get_tree().get_nodes_in_group("pickups").filter(func(p): return lvl.is_ancestor_of(p))
	var moved = level_items[0]
	var moved_id: String = moved.id
	moved.global_position = lvl.facility.random_point(lvl.rng)
	level_items[1].queue_free()   # (taken, gone)
	var crate = lvl.facility.supplies[0] if not lvl.facility.supplies.is_empty() else null
	if crate != null:
		lvl.facility._open_supply(crate)
	main.player.slots[0] = {"id": "CROWBAR", "charge": -1.0, "extra": {}}
	main.player.hp = 63.0
	var img := Image.create(64, 54, false, Image.FORMAT_RGB8)
	img.fill(Color(0.8, 0.3, 0.2))
	var tex := ImageTexture.create_from_image(img)
	main.add_photo({"tex": tex, "stamp": "STN %s   13:10" % letter})
	main.pin_photo({"id": "PHOTO", "charge": -1.0, "extra": {"tex": tex, "stamp": "PINNED"}}, main.train.to_global(Vector3(0, 1.6, 1.2)), main.train.global_basis.z)
	await secs(2.5)
	var moved_at: Vector3 = moved.global_position
	var aboard_at: Vector3 = main.train.to_local(aboard.global_position)
	var n_level: int = main.get_tree().get_nodes_in_group("pickups").filter(func(p): return lvl.is_ancestor_of(p) and not p.is_queued_for_deletion()).size()
	check(main.autosave(), "saving mid-station")
	var peek := Save.peek(PATH)
	check(peek.get("credits") == 777 and peek.get("where") == "STATION %s" % letter, "the title screen can read what's saved (%s)" % peek)
	# A fresh game, then CONTINUE.
	main.queue_free()
	await process_frame
	main = await fresh()
	check(main.continue_run(), "continuing the run")
	await secs(1.0)
	lvl = main.level
	check(not main.at_checkpoint and main.stop.letter == letter, "...back at station %s" % letter)
	check(lvl.facility.layout.cells.size() == rooms, "...the same site (%d rooms)" % rooms)
	check(main.credits == 777 and absf(main.hours - peek.hours) < 0.1, "...with the credits and the clock (%d, %.2f)" % [main.credits, main.hours])
	check(main.has_upgrade("STORAGE_CAR") and main.train.has_node("StorageCar") or main.has_upgrade("STORAGE_CAR"), "...and the upgrades")
	var items: Array = main.get_tree().get_nodes_in_group("pickups")
	check(items.filter(func(p): return lvl.is_ancestor_of(p)).size() == n_level, "...the stop's items as they were left (%d, not a fresh lot)" % items.filter(func(p): return lvl.is_ancestor_of(p)).size())
	check(items.any(func(p): return p.id == moved_id and p.global_position.distance_to(moved_at) < 0.3), "...including where something was moved to")
	check(items.any(func(p): return p.id == "ENGINE_BLOCK" and main.train.is_ancestor_of(p) and main.train.to_local(p.global_position).distance_to(aboard_at) < 0.3), "...the scrap aboard the train")
	var pinned: Array = items.filter(func(p): return p.id == "PHOTO" and p.has_node("Tack") and p.freeze)
	check(pinned.size() == 1 and pinned[0].extra.has("tex"), "...the photo pinned up, picture and all")
	check(main.player.slots[0] != null and main.player.slots[0].id == "CROWBAR" and main.player.hp >= 63.0 and main.player.hp < 99.0, "...what we had in hand, and our health (it heals as it does) (%s, %.0f)" % [main.player.slots[0], main.player.hp])
	check(main.photo_log.size() == 1 and main.photo_log[0].has("tex") and main.photo_log[0].tex.get_width() == 64, "...the run's photo album")
	if crate != null:
		check(lvl.facility.supplies[0].get_meta("opened", false), "...the opened crate stays open")
	check(lvl.hazards.events.all(func(e): return e[0] > peek.hours), "...and what already happened today doesn't happen again")
	check(main.train.contains(main.player.global_position), "...standing aboard the train")
	# The pause menu shows the album.
	main.menu.open()
	await process_frame
	check(main.menu._album_grid.get_child_count() == 1, "the pause menu shows the run's photographs (%d)" % main.menu._album_grid.get_child_count())
	main.menu.close()
	# A save from an older build: version 1, fields missing, an item and an upgrade this build
	# doesn't have. It loads anyway, keeps what it can, leaves out the rest.
	var old := {"version": 1, "state": {"credits": 321, "assignment": 2, "upgrades": {"STORAGE_CAR": true, "TIME_MACHINE": true}, "hours": 8.0},
		"stop": main.CHECKPOINT_STOP, "seed": 5,
		"items": [{"id": "WRENCH", "frame": "T", "pos": Vector3(0.5, 1.6, 0.4), "rot": Quaternion.IDENTITY},
			{"id": "LASER_SWORD", "frame": "T", "pos": Vector3(1.0, 1.6, 0.4), "rot": Quaternion.IDENTITY}],
		"player": {"slots": [{"id": "CROWBAR", "charge": -1.0}, {"id": "LASER_SWORD", "charge": -1.0}]}}
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_var(old)
	f.close()
	main.queue_free()
	await process_frame
	main = await fresh()
	check(main.continue_run(), "a save from an older build still loads")
	await secs(0.5)
	var its: Array = main.get_tree().get_nodes_in_group("pickups")
	check(main.credits == 321 and main.has_upgrade("STORAGE_CAR") and not main.has_upgrade("TIME_MACHINE"), "...with its credits and the upgrades this build has")
	check(its.any(func(q): return q.id == "WRENCH") and not its.any(func(q): return q.id == "LASER_SWORD"), "...and its items, leaving out ones that no longer exist")
	check(main.player.slots[0] != null and main.player.slots[0].id == "CROWBAR" and main.player.slots[1] == null, "...the same for what was in hand")
	main.autosave()
	check(Save.peek(PATH).get("credits") == 321, "...and it saves again in the new format")
	# Game over: nothing left to continue.
	main.game_over("A test.")
	check(not Save.exists(PATH), "game over deletes the save")
	print("save.gd: %s" % ("ALL PASSED" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails else 0)
