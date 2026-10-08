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
	"ENGINE_BLOCK": {"name": "Engine Block", "res": {"steel": 8, "copper": 2}, "size": Vector3(0.7, 0.45, 0.48), "heavy": true, "rare": true},
	"TRANSFORMER": {"name": "Transformer", "res": {"copper": 7, "steel": 3}, "size": Vector3(0.5, 0.7, 0.44), "heavy": true, "rare": true},
	"CABLE_DRUM": {"name": "Cable Drum", "res": {"copper": 5, "rubber": 4}, "size": Vector3(0.56, 0.7, 0.7), "heavy": true},
	"SAFE_BOX": {"name": "Office Safe", "res": {"steel": 9, "copper": 1}, "size": Vector3(0.52, 0.64, 0.5), "heavy": true, "rare": true},
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
	"CROWBAR": {"name": "Crowbar", "kind": "weapon", "price": 45, "res": {"steel": 3},
		"size": Vector3(0.04, 0.07, 0.68), "damage": 22.0, "swing": 0.55, "reach": 2.3, "desc": "Melee. Quick, light hits."},
	"FIRE_AXE": {"name": "Fire Axe", "kind": "weapon", "price": 85, "res": {"steel": 2, "plastic": 1},
		"size": Vector3(0.08, 0.3, 0.9), "damage": 48.0, "swing": 1.0, "reach": 2.5, "desc": "Melee. Slow, heavy hits."},
	"SHOTGUN": {"name": "Shotgun", "kind": "weapon", "price": 240, "charge": 6.0, "res": {"steel": 3, "plastic": 1},
		"size": Vector3(0.07, 0.16, 1.0), "damage": 13.0, "pellets": 8, "swing": 0.9, "reach": 26.0,
		"desc": "Eight pellets a shell, deafening. Restocked aboard the train."},
	"PHOTO": {"name": "Photograph", "kind": "photo", "res": {}, "size": Vector3(0.2, 0.008, 0.17), "no_spawn": true,
		"desc": "Somebody took your picture. Pin it up on the train."},
	"REMAINS": {"name": "Your Remains", "kind": "remains", "res": {}, "size": Vector3(0.5, 0.32, 1.7), "heavy": true, "no_spawn": true,
		"desc": "Bring them aboard to release the impounded cargo."},
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
	["OBSERVER", "Field note, crew 9: something has been taking our picture.\nWe hear the shutter behind us. Every time, behind us.\nMorrow turned round. He says the flash was the last thing he saw for a while.\nWe found the photograph afterwards. It was of Morrow, turning round.\nDo not look back. Keep walking. It only wants the picture."],
	["WRAITH", "Shift log, sector 6, the night of the outage: lamps going out one by one, heading our way.\nThen the cold. Then the whispering.\nIt wore a hard hat. Bureau issue.\nWe kept it off with our torches until the batteries went. Keep yours charged.\nIt does not like the light. Nothing that has been down here that long does."],
	["WARDEN", "The site's security unit was upgraded with biological components after funding cuts.\nIt sees only what its searchlight touches.\nStay out of the beam. If it finds you, get up high: it cannot climb.\nYou will hear it long before you see it."],
	["LEVIATHAN", "Survey teams report subsurface movement after 17:00.\nWhen the ground starts shaking, it is listening.\nCrouch. Stop talking. Do not run unless you are under a roof.\nThe train has a roof. The train is recommended."],
	["SNATCHER", "Vents painted yellow are maintenance shafts. Some are occupied.\nAn occupied vent drips.\nEmployees taken by the vents are usually returned, in a different room, minus what they were holding.\nUsually."],
	["SCRAPPER", "A small creature that builds its shell out of discarded material.\nIt startles at footsteps. Approach crouched.\nThe shell is worth more than most of what you will find down there.\nThe Bureau considers this a renewable resource."],
	["GLOE", "Some crews report a small floating light that follows one person around.\nIt does not attack. It does not respond to commands.\nIt seems to like people.\nThis has not been studied, because nobody wants to scare it off."],
	["QUOTA", "Quotas are calculated by the Bureau's allocation engine.\nThe engine considers market demand, site yield, and crew size.\nCrew size is weighted at zero.\nIf you are reading this, your quota has already been raised."],
]


const SHOP := ["FLASHLIGHT", "LANTERN", "SCANNER", "BACKPACK", "CROWBAR", "FIRE_AXE", "SHOTGUN"]

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

# Who lives where: a multiplier on how many of each creature a facility type gets. 0 = never found there.
const HABITAT := {
	"FACTORY": {"roomba": 1.0, "pulsator": 1.0, "mimic": 1.5, "marionette": 0.6, "warden": 1.5, "trap": 1.3, "snatcher": 0.8, "scrapper": 1.4, "gloe": 0.6, "statue": 0.6, "observer": 1.0, "wraith": 0.8},
	"LAB": {"roomba": 1.6, "pulsator": 0.8, "mimic": 0.6, "marionette": 1.3, "warden": 1.0, "trap": 0.6, "snatcher": 1.0, "scrapper": 0.8, "gloe": 1.0, "statue": 1.5, "observer": 1.5, "wraith": 0.7},
	"FLESH": {"roomba": 0.0, "pulsator": 1.8, "mimic": 0.5, "marionette": 0.8, "warden": 0.4, "trap": 1.0, "snatcher": 2.5, "scrapper": 0.4, "gloe": 0.0, "statue": 0.6, "observer": 0.4, "wraith": 1.5},
	"BACKROOMS": {"roomba": 0.0, "pulsator": 1.0, "mimic": 0.0, "marionette": 1.8, "warden": 0.0, "trap": 0.5, "snatcher": 0.7, "scrapper": 0.5, "gloe": 1.6, "statue": 1.8, "observer": 1.2, "wraith": 1.4},
}

# The Bureau field guide: one entry per creature, unlocked the first time your scanner picks it up
# (the leviathan can't be scanned: it's logged the first time it surfaces). Keys are the creature's
# script name. Kept across runs in user://field_guide.json.
const GUIDE := {
	"roomba": {"name": "ROOMBA", "threat": "HIGH", "where": "Labs and factories. Never the backrooms.",
		"signs": "A soft servo whine and a ticking. Two red laser lines across the floor ahead of it.",
		"habits": "A security floor unit still on its rounds. Break either beam and it arms: it beeps faster and faster, then detonates.",
		"counter": "Step over the beams or wait for it to turn. The casing is armoured: hitting it does nothing."},
	"pulsator": {"name": "PULSATOR", "threat": "HIGH", "where": "Everywhere, most of all in the flesh. More arrive as the day goes on, and after 18:00 some come up to the surface.",
		"signs": "A heartbeat that speeds up. Footsteps of three hands.",
		"habits": "Blind. It hears footsteps, then locks on, swells and bursts a few seconds later or the moment it reaches you.",
		"counter": "Crouch: it can't hear crouched steps. Walls muffle you. Killing it makes it burst anyway, so do it from range."},
	"statue": {"name": "STATUE", "threat": "SEVERE", "where": "Labs and backrooms, late in the day (after 15:00).",
		"signs": "Stone grinding when you aren't looking. A figure that wasn't there, in a different pose each time.",
		"habits": "Dormant until first seen. From then on it moves only while nobody looks at it, fast, and its hits are heavy enough to stop you healing.",
		"counter": "Keep eyes on it and back away. Stone: nothing you carry will break it."},
	"marionette": {"name": "MARIONETTE", "threat": "LETHAL", "where": "Labs and backrooms, crouched in corners.",
		"signs": "A jointed wooden figure, folded up. The clack of wooden feet.",
		"habits": "The reverse of the statue: it moves only while someone is looking at it, straight at them. One touch kills.",
		"counter": "Look away and it freezes. Walk out backwards without looking. It can be broken: three or four solid hits."},
	"mimic": {"name": "MIMIC", "threat": "HIGH", "where": "Factories, among the barrels. Never the backrooms.",
		"signs": "A barrel whose lid twitches now and then. Doesn't show on the minimap.",
		"habits": "Get within arm's reach and it bites, then sprouts legs and runs off to hide somewhere else.",
		"counter": "Step in and straight back out to make it bite the air. A poke gives it away. It can be killed."},
	"warden": {"name": "WARDEN", "threat": "SEVERE", "where": "Factories most of all. Never the backrooms.",
		"signs": "Heavy footsteps you feel through the floor. A searchlight sweeping the room, then turning red.",
		"habits": "Sees only what its beam touches. Once it has you it runs you down with its blades.",
		"counter": "Stay out of the beam. Get up on something: it can't climb. Hitting it makes it hunt you. It takes a lot of shot."},
	"scrapper": {"name": "SCRAPPER", "threat": "NONE", "where": "Factories, sitting still among the junk.",
		"signs": "A pile of scrap that chitters.",
		"habits": "A shy bug wearing a junk shell. Footsteps wake it and it scuttles off.",
		"counter": "Crouch up to it and grab it, or kill it. The shell is worth a lot either way."},
	"observer": {"name": "OBSERVER", "threat": "MODERATE", "where": "Labs and backrooms.",
		"signs": "A shutter clicking behind you. A lens motor whirring. A red tally lamp.",
		"habits": "A camera on long tripod legs that follows you, always from behind, creeping closer. Look back and it charges its flash.",
		"counter": "Don't look back. If you do, look away again before the whine peaks. It runs when hit. It leaves photographs."},
	"wraith": {"name": "WRAITH", "threat": "SEVERE", "where": "The flesh and the backrooms, after 16:00. Faster when the power is out.",
		"signs": "Lamps dying one after another, heading your way. Whispering. Your visor frosting over.",
		"habits": "What's left of a miner. It drifts after you a little slower than you walk and carries the dark with it.",
		"counter": "Light. Hold a flashlight beam on it and it comes apart. A lit lantern keeps it at arm's length. Steel goes straight through it."},
	"snatcher": {"name": "SNATCHER", "threat": "MODERATE", "where": "Ceiling vents with yellow-painted frames, the flesh most of all.",
		"signs": "Blood dripping from a vent.",
		"habits": "Walk under it and a maw drops and drags you through the ducts. You come out somewhere else, without what you were holding.",
		"counter": "Watch the ceiling. Don't walk under a dripping vent."},
	"bear_trap": {"name": "BEAR TRAP", "threat": "LOW", "where": "On the floor, anywhere, in the dark.",
		"signs": "Rusted jaws, open.",
		"habits": "Snaps shut on whoever steps in it and holds them.",
		"counter": "Look where you put your feet. Hold E to pry it open. That's loud."},
	"gloe": {"name": "GLOE", "threat": "NONE", "where": "Rare. Labs and backrooms.",
		"signs": "A small floating light that hums.",
		"habits": "Picks one employee as its friend and floats beside them, lighting the way. It does not respond to commands.",
		"counter": "None needed. Nobody wants to scare it off."},
	"leviathan": {"name": "LEVIATHAN", "threat": "LETHAL", "where": "Under the dunes at the surface, late in the day.",
		"signs": "The ground rumbling. Then cracking.",
		"habits": "During a rumble it listens. Make a sound in the open and it bursts up under you.",
		"counter": "Crouch and keep still until the rumble stops, or get a roof over your head."},
}

# Room hazards per facility type (hazards.gd). Power failures and tremors can happen anywhere.
const SITE_HAZARDS := {
	"FACTORY": ["steam", "flood"],
	"LAB": ["gas", "flood"],
	"FLESH": ["gas", "steam"],
	"BACKROOMS": ["flood"],
}
const HAZARD_NAMES := {"steam": "BURST STEAM LINES", "flood": "FLOODED SECTORS", "gas": "TOXIC GAS"}

const WEATHERS := ["CLEAR", "CLEAR", "CLEAR", "SANDSTORM", "ACID_RAIN"]


## Animation pace: 1.0 in the game; tests set Engine meta "fast_test" to shrink travel/elevator waits.
static func pace() -> float:
	return 0.1 if Engine.has_meta("fast_test") else 1.0


static func kind(id: String) -> String:
	return ITEMS[id].get("kind", "scrap")


static func scrap_ids() -> Array:
	return ITEMS.keys().filter(func(k): return kind(k) == "scrap" and not ITEMS[k].get("no_spawn", false))


## Weighted: heavy things turn up now and then, the rare heavy things hardly ever (they live in vaults).
static func random_scrap(rng: RandomNumberGenerator) -> String:
	var ids := scrap_ids()
	while true:
		var id: String = ids[rng.randi() % ids.size()]
		var w := 0.12 if ITEMS[id].get("rare", false) else (0.35 if ITEMS[id].get("heavy", false) else 1.0)
		if rng.randf() < w:
			return id
	return ids[0]


## Something worth the trip: a rare heavy piece, or one of the richest ordinary items.
static func valuable_scrap(rng: RandomNumberGenerator, heavy_ok := true) -> String:
	var pool := scrap_ids().filter(func(k): return (heavy_ok and ITEMS[k].get("rare", false)) or (not ITEMS[k].get("heavy", false) and value_units(k) >= 4))
	return pool[rng.randi() % pool.size()]


static func value_units(id: String) -> int:
	var n := 0
	for r in ITEMS[id].res:
		n += ITEMS[id].res[r]
	return n


static func is_heavy(id: String) -> bool:
	return ITEMS.has(id) and ITEMS[id].get("heavy", false)


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
