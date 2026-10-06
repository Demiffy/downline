# All game content lives here. Rename/replace freely — this is where "your stuff" goes.
extends RefCounted

const RES := ["steel", "copper", "rubber", "plastic"]
const RES_SHORT := {"steel": "STL", "copper": "CU", "rubber": "RUB", "plastic": "PLA"}
const RES_COLOR := {
	"steel": Color(0.6, 0.63, 0.67),
	"copper": Color(0.82, 0.42, 0.18),
	"rubber": Color(0.13, 0.13, 0.14),
	"plastic": Color(0.25, 0.7, 0.95),
}
# Credits paid per unit when shredded; rerolled every day.
const BASE_PRICE := {"steel": 3.0, "copper": 5.0, "rubber": 4.0, "plastic": 2.0}

# kind defaults to "scrap". res = what the shredder turns it into.
const ITEMS := {
	"BENT_SPRING": {"name": "Bent Spring", "res": {"steel": 2}, "size": Vector3(0.15, 0.3, 0.15)},
	"BROKEN_SPEAKER": {"name": "Broken Speaker", "res": {"plastic": 1, "rubber": 1, "copper": 1, "steel": 2}, "size": Vector3(0.4, 0.5, 0.35)},
	"COOKING_PAN": {"name": "Cooking Pan", "res": {"steel": 2}, "size": Vector3(0.45, 0.08, 0.3)},
	"COPPER_INGOT": {"name": "Copper Ingot", "res": {"copper": 3}, "size": Vector3(0.3, 0.1, 0.12)},
	"COPPER_PIPE": {"name": "Copper Pipe", "res": {"copper": 2}, "size": Vector3(0.08, 0.08, 0.7)},
	"EMPTY_CAN": {"name": "Empty Can", "res": {"steel": 1}, "size": Vector3(0.1, 0.15, 0.1)},
	"HAMMER": {"name": "Hammer", "res": {"plastic": 1, "steel": 2}, "size": Vector3(0.1, 0.06, 0.4)},
	"HAZARD_CONE": {"name": "Hazard Cone", "res": {"plastic": 3}, "size": Vector3(0.35, 0.6, 0.35), "color": Color(1, 0.45, 0.05)},
	"LARGE_SCREW": {"name": "Large Screw", "res": {"steel": 2}, "size": Vector3(0.08, 0.35, 0.08)},
	"MILK_JUG": {"name": "Milk Jug", "res": {"plastic": 2}, "size": Vector3(0.2, 0.3, 0.2), "color": Color(0.92, 0.92, 0.88)},
	"OLD_BOOT": {"name": "Old Boot", "res": {"rubber": 2}, "size": Vector3(0.15, 0.25, 0.32)},
	"OLD_CLOCK": {"name": "Old Clock", "res": {"plastic": 2, "copper": 1, "steel": 1}, "size": Vector3(0.3, 0.3, 0.1)},
	"PENNY": {"name": "Penny", "res": {"copper": 1}, "size": Vector3(0.1, 0.04, 0.1)},
	"RED_COPPER_PAN": {"name": "Red Copper Pan", "res": {"copper": 2, "steel": 1}, "size": Vector3(0.35, 0.08, 0.35)},
	"RUBBER_BAND_BALL": {"name": "Rubber Band Ball", "res": {"rubber": 2}, "size": Vector3(0.18, 0.18, 0.18)},
	"RUBBER_TIRE": {"name": "Rubber Tire", "res": {"rubber": 5}, "size": Vector3(0.6, 0.6, 0.14)},
	"SCISSORS": {"name": "Scissors", "res": {"plastic": 1, "steel": 2}, "size": Vector3(0.08, 0.04, 0.22)},
	"STEEL_INGOT": {"name": "Steel Ingot", "res": {"steel": 3}, "size": Vector3(0.3, 0.1, 0.12)},
	"TOY_DINO": {"name": "Toy Dino", "res": {"plastic": 2}, "size": Vector3(0.2, 0.25, 0.3), "color": Color(0.3, 0.8, 0.3)},
	"TOY_TRUCK": {"name": "Toy Truck", "res": {"plastic": 2, "rubber": 1}, "size": Vector3(0.3, 0.2, 0.2), "color": Color(0.9, 0.8, 0.1)},
	"WATER_BOTTLE": {"name": "Water Bottle", "res": {"plastic": 2, "steel": 1}, "size": Vector3(0.1, 0.3, 0.1)},
	"WATER_POUCH": {"name": "Water Pouch", "res": {"rubber": 3}, "size": Vector3(0.3, 0.1, 0.25)},
	"PUMP_GASKET": {"name": "Pump Gasket", "res": {"rubber": 2}, "size": Vector3(0.3, 0.05, 0.3)},
	"JINGLE_BELLS": {"name": "Jingle Bells", "res": {"copper": 2}, "size": Vector3(0.2, 0.08, 0.2)},
	"TOY_FORKLIFT": {"name": "Toy Forklift", "res": {"plastic": 2, "rubber": 1}, "size": Vector3(0.3, 0.22, 0.18)},
	"CAR_BATTERY": {"name": "Car Battery", "res": {"plastic": 2, "copper": 2}, "size": Vector3(0.3, 0.24, 0.18)},
	"FIRE_EXTINGUISHER": {"name": "Fire Extinguisher", "res": {"steel": 3, "rubber": 1}, "size": Vector3(0.16, 0.5, 0.15)},
	"GAS_CAN": {"name": "Gas Can", "res": {"steel": 3}, "size": Vector3(0.3, 0.35, 0.14)},
	"DESK_FAN": {"name": "Desk Fan", "res": {"plastic": 2, "copper": 2, "steel": 1}, "size": Vector3(0.28, 0.36, 0.2)},
	"ROTARY_PHONE": {"name": "Rotary Phone", "res": {"plastic": 3, "copper": 1}, "size": Vector3(0.24, 0.14, 0.18)},
	"TYPEWRITER": {"name": "Typewriter", "res": {"steel": 4, "plastic": 1}, "size": Vector3(0.4, 0.2, 0.28)},
	"RADIO": {"name": "Old Radio", "res": {"plastic": 2, "copper": 1, "steel": 1}, "size": Vector3(0.34, 0.22, 0.12)},
	"TOOLBOX": {"name": "Toolbox", "res": {"steel": 4}, "size": Vector3(0.45, 0.2, 0.2)},
	"WRENCH": {"name": "Wrench", "res": {"steel": 2}, "size": Vector3(0.06, 0.02, 0.3)},
	"CROWBAR": {"name": "Crowbar", "res": {"steel": 3}, "size": Vector3(0.04, 0.07, 0.68)},
	"LIGHT_BULB": {"name": "Light Bulb", "res": {"copper": 1}, "size": Vector3(0.08, 0.13, 0.08)},
	"GEAR": {"name": "Big Gear", "res": {"steel": 3}, "size": Vector3(0.3, 0.06, 0.3)},
	"VALVE_WHEEL": {"name": "Valve Wheel", "res": {"steel": 2}, "size": Vector3(0.28, 0.08, 0.28)},
	"PADLOCK": {"name": "Padlock", "res": {"steel": 2}, "size": Vector3(0.08, 0.12, 0.04)},
	"CHAIN": {"name": "Chain", "res": {"steel": 3}, "size": Vector3(0.36, 0.06, 0.06)},
	"TEAPOT": {"name": "Teapot", "res": {"steel": 2}, "size": Vector3(0.26, 0.18, 0.16)},
	"COFFEE_MUG": {"name": "Coffee Mug", "res": {"plastic": 1}, "size": Vector3(0.12, 0.09, 0.09)},
	"THERMOS": {"name": "Thermos", "res": {"steel": 2, "plastic": 1}, "size": Vector3(0.1, 0.3, 0.1)},
	"RUBBER_DUCK": {"name": "Rubber Duck", "res": {"rubber": 2}, "size": Vector3(0.12, 0.12, 0.14)},
	"GAS_MASK": {"name": "Gas Mask", "res": {"rubber": 3, "plastic": 1}, "size": Vector3(0.18, 0.2, 0.2)},
	"HARD_HAT": {"name": "Hard Hat", "res": {"plastic": 3}, "size": Vector3(0.26, 0.13, 0.3)},
	"GARDEN_HOSE": {"name": "Garden Hose", "res": {"rubber": 4}, "size": Vector3(0.4, 0.12, 0.4)},
	"BICYCLE_WHEEL": {"name": "Bicycle Wheel", "res": {"steel": 2, "rubber": 2}, "size": Vector3(0.58, 0.58, 0.06)},
	"CIRCUIT_BOARD": {"name": "Circuit Board", "res": {"copper": 2, "plastic": 1}, "size": Vector3(0.24, 0.03, 0.17)},
	"KEYBOARD": {"name": "Keyboard", "res": {"plastic": 3}, "size": Vector3(0.44, 0.04, 0.15)},
	"VHS_TAPE": {"name": "VHS Tape", "res": {"plastic": 2}, "size": Vector3(0.19, 0.03, 0.1)},
	"BUCKET": {"name": "Metal Bucket", "res": {"steel": 2}, "size": Vector3(0.28, 0.28, 0.28)},
	"TIN_ROBOT": {"name": "Tin Robot", "res": {"steel": 2}, "size": Vector3(0.12, 0.25, 0.1)},
	"MOTOR": {"name": "Electric Motor", "res": {"copper": 3, "steel": 2}, "size": Vector3(0.26, 0.2, 0.18)},
	"TRUMPET": {"name": "Trumpet", "res": {"copper": 3}, "size": Vector3(0.45, 0.12, 0.12)},
	"BABY_DOLL": {"name": "Baby Doll", "res": {"plastic": 2}, "size": Vector3(0.15, 0.33, 0.08)},
	"GARDEN_GNOME": {"name": "Garden Gnome", "res": {"plastic": 2}, "size": Vector3(0.13, 0.3, 0.13)},
	"INNER_TUBE": {"name": "Inner Tube", "res": {"rubber": 3}, "size": Vector3(0.44, 0.11, 0.44)},
	"HOT_WATER_BOTTLE": {"name": "Hot Water Bottle", "res": {"rubber": 2}, "size": Vector3(0.17, 0.3, 0.05)},
	"SPRAY_CAN": {"name": "Spray Can", "res": {"steel": 1, "plastic": 1}, "size": Vector3(0.07, 0.2, 0.07)},
	"WIRE_SPOOL": {"name": "Wire Spool", "res": {"plastic": 1, "copper": 3}, "size": Vector3(0.3, 0.3, 0.3)},

	"FLASHLIGHT": {"name": "Flashlight", "kind": "tool", "price": 35, "charge": 200.0, "res": {"plastic": 1, "copper": 1},
		"size": Vector3(0.07, 0.07, 0.3), "color": Color(0.95, 0.8, 0.15), "desc": "Beam light. Click to toggle."},
	"LANTERN": {"name": "Lantern", "kind": "tool", "price": 55, "charge": 285.0, "res": {"copper": 1, "steel": 1},
		"size": Vector3(0.18, 0.3, 0.18), "color": Color(0.9, 0.6, 0.2), "desc": "Lights all around you. Click to toggle."},
	"SCANNER": {"name": "Scanner", "kind": "equip", "price": 90, "res": {},
		"size": Vector3(0.15, 0.2, 0.08), "color": Color(0.2, 0.9, 0.6), "desc": "Equipment. F / middle mouse to scan nearby."},
	"BACKPACK": {"name": "Backpack", "kind": "equip", "price": 80, "res": {},
		"size": Vector3(0.4, 0.5, 0.25), "color": Color(0.35, 0.4, 0.2), "desc": "Equipment. +1 inventory slot."},
	"SCRAPPER_SHELL": {"name": "Scrapper Shell", "res": {"steel": 3, "copper": 3, "rubber": 2, "plastic": 2}, "size": Vector3(0.5, 0.3, 0.5), "color": Color(0.55, 0.45, 0.35), "no_spawn": true},
	"DISK": {"name": "Data Disk", "kind": "disk", "res": {"plastic": 1},
		"size": Vector3(0.14, 0.02, 0.14), "color": Color(0.2, 0.35, 0.8), "desc": "Click inside the train to upload it to the terminal."},
}

# Permanent for the run, bought at the checkpoint (UPGRADES / BUY_UPGRADE).
const UPGRADES := {
	"BETTER_BOOTS": {"price": 215, "desc": "Crew: doubles stamina."},
	"WEATHERVANE": {"price": 150, "desc": "Train: VIEW_STATION shows each stop's weather."},
	"MINIMAP": {"price": 375, "desc": "Crew: HUD minimap underground + MINIMAP terminal map."},
	"STORAGE_CAR": {"price": 250, "desc": "Train: adds a walk-in cargo car behind the crew car."},
	"QUICK_DELIVERY": {"price": 120, "desc": "Train: shop deliveries arrive in seconds, not a minute."},
	"BATTERY_PACK": {"price": 140, "desc": "Crew: flashlights and lanterns last 60% longer."},
	"DIGITAL_CLOCK": {"price": 90, "desc": "Train: a segment display over the front window, with a countdown to departure."},
}

# Lore found on data disks, unlocked in this order. Yours to rewrite.
const LOGS := [
	["WELCOME", "Welcome to the Bureau of Reclaimed Materials.\nYou were selected for your availability.\nYour contract is permanent. Your shifts are not.\nCollect scrap. Meet quota. Be back by midnight.\nThe train does not wait, and neither does the Bureau."],
	["THE_LINE", "The rail line was laid before the collapse to feed the sites below.\nNobody remembers who built the stations.\nThe Bureau inherited the line along with everything under it.\nThe Bureau inherits a lot of things."],
	["SITE_REPORT", "Survey crews mapped seventeen sites before the surveys stopped.\nThe sites change between visits. Rooms are where hallways were.\nThe official explanation is 'subsidence'.\nThe unofficial explanation is not permitted on this terminal."],
	["ROOMBA", "Cleaning units were left running when the staff evacuated.\nThey still patrol. They still detect intruders.\nTheir self-destruct was meant for corporate espionage.\nStep around them. Do not step in front of them. Never in front."],
	["PULSATOR", "Specimen P is blind. It does not need eyes.\nIt hears footsteps, voices, breathing if you are close enough.\nWhen it finds you it swells. When it is done swelling, so are you.\nCrouch. Walk. Do not run unless it already knows."],
	["BULKHEADS", "Security bulkheads seal sections of the site.\nThey answer to the train terminal, not to you.\nThe manual override works. The alarm also works.\nDecide which one you want more."],
	["SHREDDER", "All recovered material is processed at checkpoint.\nPlace scrap in the hopper. Pull the lever.\nThe shredder accepts anything. Please do not test this.\nThe Bureau is not responsible for items, or employees, placed in the hopper."],
	["STATUE", "Crew 4 reported a statue on level two. Crew 5 reported it on level three.\nNobody saw it move. That is the point.\nIt only moves while no one is watching. Keep at least one pair of eyes on it.\nBlinking is technically permitted."],
	["MARIONETTE", "A wooden mannequin, crouched in a corner, head down. Harmless.\nUntil you look at it. Then it stands up, and it runs at you while you watch.\nLook away and it stops wherever it is.\nDo not look at it. Do not look for it. Do not look back."],
	["MIMIC", "Inventory lists 214 barrels on site. Inventory has been wrong before.\nOne of them bites. It strikes when you get close, then runs off on legs to hide again.\nIt is bad at hiding. It picks the middle of hallways.\nIf a barrel is somewhere a barrel would not be, it is not a barrel."],
	["WARDEN", "The site's security unit was upgraded with biological components after funding cuts.\nIt sees only what its searchlight touches.\nStay out of the beam. If it finds you, get up high: it cannot climb.\nYou will hear it long before you see it."],
	["LEVIATHAN", "Survey teams report subsurface movement after 17:00.\nWhen the ground starts shaking, it is listening.\nCrouch. Stop talking. Do not run unless you are under a roof.\nThe train has a roof. The train is recommended."],
	["SNATCHER", "Vents painted yellow are maintenance shafts. Some are occupied.\nAn occupied vent drips.\nEmployees taken by the vents are usually returned, in a different room, minus what they were holding.\nUsually."],
	["SCRAPPER", "A small creature that builds its shell out of discarded material.\nIt startles at footsteps. Approach crouched.\nThe shell is worth more than most of what you will find down there.\nThe Bureau considers this a renewable resource."],
	["GLOE", "Some crews report a small floating light that follows one person around.\nIt does not attack. It does not respond to commands.\nIt seems to like people.\nThis has not been studied, because nobody wants to scare it off."],
	["QUOTA", "Quotas are calculated by the Bureau's allocation engine.\nThe engine considers market demand, site yield, and crew size.\nCrew size is weighted at zero.\nIf you are reading this, your quota has already been raised."],
]


const SHOP := ["FLASHLIGHT", "LANTERN", "SCANNER", "BACKPACK"]

# Facility looks. *_kind = texture from art.gd; band = lower wall stripe.
const THEMES := {
	"FACTORY": {"floor_kind": "concrete", "floor": Color(0.75, 0.7, 0.65), "wall_kind": "concrete", "wall": Color(0.85, 0.8, 0.74),
		"band_kind": "rust", "band": Color(0.9, 0.85, 0.8), "ceil_kind": "metal", "ceiling": Color(0.5, 0.48, 0.45),
		"light": Color(1, 0.72, 0.42), "light_chance": 0.8, "props": 5, "bulkheads": 1, "weight": 4},
	"LAB": {"floor_kind": "tiles", "floor": Color(0.85, 0.85, 0.82), "wall_kind": "tiles", "wall": Color(0.9, 0.92, 0.9),
		"band_kind": "metal", "band": Color(0.55, 0.7, 0.68), "ceil_kind": "concrete", "ceiling": Color(0.9, 0.9, 0.9),
		"light": Color(0.75, 0.95, 1.0), "light_chance": 0.85, "props": 4, "bulkheads": 1, "weight": 3},
	"FLESH": {"floor_kind": "flesh", "floor": Color(0.7, 0.6, 0.6), "wall_kind": "flesh", "wall": Color(0.9, 0.8, 0.8),
		"band_kind": "flesh", "band": Color(0.6, 0.45, 0.45), "ceil_kind": "flesh", "ceiling": Color(0.5, 0.4, 0.4),
		"light": Color(1, 0.35, 0.35), "light_chance": 0.6, "props": 4, "bulkheads": 3, "weight": 2},
	"BACKROOMS": {"floor_kind": "carpet", "floor": Color.WHITE, "wall_kind": "wallpaper", "wall": Color.WHITE,
		"band_kind": "wallpaper", "band": Color(0.75, 0.7, 0.6), "ceil_kind": "tiles", "ceiling": Color(0.85, 0.83, 0.75),
		"light": Color(1, 1, 0.82), "light_chance": 0.8, "props": 1, "bulkheads": 0, "weight": 1},
}

const WEATHERS := ["CLEAR", "CLEAR", "CLEAR", "SANDSTORM", "ACID_RAIN"]


static func kind(id: String) -> String:
	return ITEMS[id].get("kind", "scrap")


static func scrap_ids() -> Array:
	return ITEMS.keys().filter(func(k): return kind(k) == "scrap" and not ITEMS[k].get("no_spawn", false))


static func random_scrap(rng: RandomNumberGenerator) -> String:
	var ids := scrap_ids()
	return ids[rng.randi() % ids.size()]


static func color(id: String) -> Color:
	var d: Dictionary = ITEMS[id]
	if d.has("color"):
		return d.color
	var best := ""
	for r in d.res:
		if best == "" or d.res[r] > d.res[best]:
			best = r
	return RES_COLOR.get(best, Color.GRAY)


static func res_text(res: Dictionary) -> String:
	var parts := PackedStringArray()
	for r in RES:
		if res.get(r, 0) > 0:
			parts.append("%d %s" % [res[r], RES_SHORT[r]])
	return ", ".join(parts)
