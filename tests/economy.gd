# The economy's rules: the quota's size (by assignment and crew), the Bureau's replacement fees
# and the debt they can run up, the crew wipe recall, the shredder's diverter banking the surplus,
# the bonded stock (its bales, STOCK SELL / SUBMIT), and all of it kept in a save.
# Run: tests/run.sh 120 --headless --path . -s tests/economy.gd
extends SceneTree

const Save = preload("res://src/save.gd")

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
	# The quota: more each assignment, climbing faster later on, a third again for each extra hand.
	var q1: int = main.quota_units(1, 1, 1.0)
	var q3: int = main.quota_units(3, 1, 1.0)
	var q5: int = main.quota_units(5, 1, 1.0)
	check(q1 == 7 and q3 == 17 and q5 == 33, "the quota climbs: 7, 17, 33 units at assignments 1, 3, 5 (%d, %d, %d)" % [q1, q3, q5])
	check(q5 - q3 > q3 - q1, "...faster the further the run goes")
	var crew4: int = main.quota_units(1, 4, 1.0)
	check(crew4 == 14, "a crew of four is asked for about twice as much (%d)" % crew4)
	check(main.quota_units(1, 1, 0.1) == 2, "never fewer than two units")
	main.term.run("LEAVE_CHECKPOINT")
	check(main.assignment == 1 and main.crew_size == 1, "an assignment is issued, sized for the crew (%d)" % main.crew_size)
	for r in main.Data.RES:
		check(main.quota[r] >= 4 and main.quota[r] <= 10, "...%s quota %d within the roll" % [r, main.quota[r]])
	# The shredder's diverter: SELL pays everything; BANK keeps whatever's past the quota.
	main.departed = false
	main.quota = {"steel": 2, "copper": 2, "rubber": 5, "plastic": 2}
	main.submitted = {}
	main.bank = {}
	main.prices = {"steel": 3.0, "copper": 5.0, "rubber": 4.0, "plastic": 2.0}
	var c0: int = main.credits
	main.shred_item("STEEL_INGOT")
	check(main.submitted.steel == 3 and main.credits == c0 + 9 and main.bank.is_empty(), "SELL: a steel ingot counts and pays 9 (%d, +%d)" % [main.submitted.steel, main.credits - c0])
	main.toggle_divert()
	check(main.divert_bank, "the diverter turns to BANK")
	var dial: Node3D = main.level.shredder._dial
	await create_timer(0.4).timeout
	check(absf(dial.rotation.x + 0.75) < 0.05 and main.level.shredder._lamps.BANK.emission_energy_multiplier > 1.0, "...its handle and the BANK lamp follow")
	c0 = main.credits
	main.shred_item("STEEL_INGOT")
	check(main.submitted.steel == 3 and main.bank.get("steel", 0) == 3 and main.credits == c0, "BANK: past the quota, a steel ingot goes to stock unpaid")
	main.shred_item("COPPER_INGOT")
	check(main.submitted.copper == 2 and main.bank.get("copper", 0) == 1 and main.credits == c0 + 10, "...a copper ingot fills the quota first (2 paid), the rest banked (1)")
	check(main._banked_now == 4, "the shift report counts 4 units banked")
	main.bank["rubber"] = 9
	main._stock_changed()
	await frames(2)
	var bales: int = main.level._stock_root.get_child_count()
	check(bales == 5, "the bonded store shows the stock in bales: 1 steel, 1 copper, 3 rubber (%d)" % bales)
	check(main._board_text().contains("DIVERTER: BANK") and main._board_text().contains("BONDED STOCK: 3 STL, 1 CU, 9 RUB"), "the readout shows the diverter and the stock")
	# STOCK: sell it at today's price, or put it toward the quota.
	c0 = main.credits
	main.term.run("STOCK SELL STEEL")
	check(not main.bank.has("steel") and main.credits == c0 + 9, "STOCK SELL STEEL: 3 units for 9 credits")
	main.submitted.plastic = 2
	main.term.run("STOCK SUBMIT RUBBER")
	check(main.submitted.rubber == 5 and main.bank.rubber == 4, "STOCK SUBMIT RUBBER: 5 to the quota, 4 left in stock")
	check(main._quota_met(), "...and with it the quota's met")
	main.term.run("STOCK SUBMIT ALL")
	check(main.bank.rubber == 4, "...nothing more goes in once the quota doesn't need it")
	# The save keeps all of it.
	var st: Dictionary = main.net_state()
	var keep := {"bank": main.bank.duplicate(), "divert": main.divert_bank}
	main.bank = {}
	main.divert_bank = false
	Save._apply_state(main, st)
	check(main.bank == keep.bank and main.divert_bank == keep.divert, "a saved run keeps the stock and the diverter")
	# Replacements: the Bureau charges each one, dearer each time, into debt if need be.
	main.credits = 10
	main._lost_from = main.stats.lost
	main.fees = 0
	check(main.replacement_fee() == 40, "a replacement costs 40")
	main.died_world(Vector3(0, 1, 0), 0.0, "Tester")
	check(main.credits == -30 and main.fees == 40, "...docked from the account, into debt (%d)" % main.credits)
	check(main.replacement_fee() == 60, "...the next one costs 60")
	check(main._quota_text().begins_with("IN DEBT: 30 CR"), "the visor shows the debt")
	main.term.run("BUY MEDKIT")
	check(main.credits == -30, "nothing can be bought in debt")
	for i in 6:
		main.died_world(Vector3(0, 1, 0), 0.0, "Tester")
	check(main.replacement_fee() == 140, "...capped at 140")
	# A whole crew lost at a stop: the train's recalled.
	main.at_checkpoint = false
	main.hours = 12.0
	main._down = {}
	var mate := Node3D.new()
	mate.add_to_group("players")
	main.add_child(mate)
	main.died_world(Vector3(0, 1, 0), 0.0, "Tester")
	check(main.hours < 14.0, "one of two lost: an hour gone, no recall (%.1f)" % main.hours)
	main.died_world(Vector3(0, 1, 0), 0.0, "Mate")
	check(absf(main.hours - (main.depart_hour() - main.WIPE_RECALL)) < 0.01, "both lost: the Bureau recalls the train, half an hour left (%.2f)" % main.hours)
	mate.free()
	main.at_checkpoint = true
	main.report.show_report([1, "CHECKPOINT   12:00", 4, 40, 120, 2, 2, "B", 100, 4])
	await frames(5)
	check(main.report._card != null, "the shift report takes the fees and the stock")
	print("economy.gd: %s" % ("ALL PASSED" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails else 0)
