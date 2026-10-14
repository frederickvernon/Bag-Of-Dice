class_name DiceSetStore
extends RefCounted
## Loads and saves the user's dice sets as JSON in user:// (the app's private
## storage — on Android it's inside the app's data folder; on a Mac it's under
## ~/Library/Application Support/Godot/app_userdata/Bag Of Dice/).
##
## File format (plain data so it can be read, or extended, later):
## {
##   "version": 1,
##   "last_set_id": "…",
##   "sets": [
##     { "id": "…", "name": "Fireball", "pick_dice": false,
##       "dice": [ { "type": "d6", "style": "pips", "color": "#e8742a", "label": "" }, … ] }
##
## style: how the faces look, for types with a choice (see DiceFactory.STYLES);
## missing or unknown means the natural default (pips on a d6, 0–9 on a d10).
## pick_dice: before each throw the player picks which of the set's dice to
## throw (e.g. one Risk set holding both attack and defend dice).
##   ]
## }
##
## Everything read from disk is checked; anything malformed is dropped rather
## than crashing the app. A file that can't be read at all is kept aside as
## dice_sets.corrupt.json instead of being overwritten (see JsonFile).

const DEFAULT_PATH: String = "user://dice_sets.json"
const FORMAT_VERSION: int = 1
## Most physical dice a set can put on the table. A d100 counts as 2, since
## it's rolled as two d10s.
const MAX_DICE: int = 20
const MAX_NAME_LENGTH: int = 40
const MAX_LABEL_LENGTH: int = 24

var path: String
var sets: Array[Dictionary] = []
var last_set_id: String = ""


func _init(file_path: String = DEFAULT_PATH) -> void:
	path = file_path


## Reads the file. On first run (no file yet) starts with the example sets.
func load_sets() -> void:
	sets.clear()
	last_set_id = ""
	var first_run: bool = not FileAccess.file_exists(path)
	var data: Variant = JsonFile.read(path)
	if typeof(data) != TYPE_DICTIONARY or typeof(data.get("sets")) != TYPE_ARRAY:
		if FileAccess.file_exists(path):
			JsonFile.keep_corrupt(path)  # valid JSON, but not a sets file
		sets = example_sets()
		save_sets()
		if not first_run:
			push_warning("Dice sets were reset to the examples.")
		return

	for raw: Variant in data["sets"]:
		var s: Dictionary = sanitize_set(raw)
		if not s.is_empty() and get_set(s["id"]).is_empty():
			sets.append(s)
	last_set_id = str(data.get("last_set_id", ""))


## Writes all sets. Returns false on failure.
func save_sets() -> bool:
	return JsonFile.write(path, { "version": FORMAT_VERSION, "last_set_id": last_set_id, "sets": sets })


func get_set(id: String) -> Dictionary:
	for s: Dictionary in sets:
		if s["id"] == id:
			return s
	return {}


## Adds a new set or replaces the one with the same id, then saves. Returns
## the cleaned-up set as stored ({} if it was invalid, e.g. no dice).
func upsert(set_data: Dictionary) -> Dictionary:
	var s: Dictionary = sanitize_set(set_data)
	if s.is_empty():
		return {}
	for i: int in sets.size():
		if sets[i]["id"] == s["id"]:
			sets[i] = s
			save_sets()
			return s
	sets.append(s)
	save_sets()
	return s


func delete(id: String) -> void:
	for i: int in sets.size():
		if sets[i]["id"] == id:
			sets.remove_at(i)
			break
	if last_set_id == id:
		last_set_id = ""
	save_sets()


func set_last_used(id: String) -> void:
	if last_set_id != id:
		last_set_id = id
		save_sets()


## Returns a clean copy of a set, or {} if it can't be used (not a
## dictionary, or no valid dice). Fixes what it can: trims and shortens the
## name, drops unknown die types, replaces bad colours, caps the dice count.
static func sanitize_set(raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	var name: String = str(raw.get("name", "")).strip_edges().left(MAX_NAME_LENGTH)
	if name.is_empty():
		name = "Untitled set"
	var id: String = str(raw.get("id", "")).strip_edges()
	if id.is_empty():
		id = new_id()

	var dice: Array[Dictionary] = []
	var physical: int = 0
	var raw_dice: Variant = raw.get("dice", [])
	if typeof(raw_dice) == TYPE_ARRAY:
		for d: Variant in raw_dice:
			if typeof(d) != TYPE_DICTIONARY:
				continue
			var type: String = str(d.get("type", ""))
			if not DiceFactory.TYPES.has(type):
				continue
			if physical + DiceFactory.dice_count(type) > MAX_DICE:
				continue  # no room left for this one
			physical += DiceFactory.dice_count(type)
			var color: String = str(d.get("color", ""))
			if not DicePalette.is_valid_hex(color):
				color = DicePalette.DEFAULT_HEX
			var label: String = str(d.get("label", "")).strip_edges().left(MAX_LABEL_LENGTH)
			var style: String = str(d.get("style", ""))
			if not DiceFactory.is_valid_style(type, style):
				style = DiceFactory.default_style(type)
			dice.append({ "type": type, "style": style, "color": color, "label": label })
	if dice.is_empty():
		return {}
	return { "id": id, "name": name, "pick_dice": raw.get("pick_dice", false) == true, "dice": dice }


static func new_id() -> String:
	return "%x-%08x" % [int(Time.get_unix_time_from_system() * 1000.0), randi()]


## The dice a set puts on the table, in the form DiceRoller.set_dice expects.
static func to_roller_specs(set_data: Dictionary) -> Array[Dictionary]:
	var specs: Array[Dictionary] = []
	for d: Dictionary in set_data.get("dice", []):
		specs.append({
			"type": d["type"],
			"style": d.get("style", ""),
			"color": DicePalette.from_hex(d["color"]),
			"label": d.get("label", ""),
		})
	return specs


## How many physical dice the set puts on the table (d100 counts as 2).
static func physical_count(set_data: Dictionary) -> int:
	var n: int = 0
	for d: Dictionary in set_data.get("dice", []):
		n += DiceFactory.dice_count(d["type"])
	return n


## Short description such as "8d6" or "1d4 + 1d6 + 1d20", in die-type order.
static func summary(set_data: Dictionary) -> String:
	var counts: Dictionary = {}
	for d: Dictionary in set_data.get("dice", []):
		counts[d["type"]] = counts.get(d["type"], 0) + 1
	var parts: PackedStringArray = PackedStringArray()
	for type: String in DiceFactory.TYPES:
		if counts.has(type):
			parts.append("%d%s" % [counts[type], type])
	return " + ".join(parts)


static func example_sets() -> Array[Dictionary]:
	var examples: Array[Dictionary] = []
	examples.append(_example("Fireball", _repeat("d6", "#e8742a", 8), false))
	# Attack and defend dice in one set; pick which ones each throw.
	examples.append(_example("Risk",
			_repeat("d6", "#d23333", 3, "Attack") + _repeat("d6", "#f2edd9", 2, "Defend"), true))
	var rpg: Array[Dictionary] = []
	for type: String in DiceFactory.TYPES:
		rpg.append({ "type": type, "style": DiceFactory.default_style(type), "color": "#8c4dbf", "label": "" })
	examples.append(_example("RPG set", rpg, true))
	return examples


static func _example(name: String, dice: Array[Dictionary], pick_dice: bool) -> Dictionary:
	return { "id": new_id(), "name": name, "pick_dice": pick_dice, "dice": dice }


static func _repeat(type: String, color: String, count: int, label: String = "") -> Array[Dictionary]:
	var dice: Array[Dictionary] = []
	for i: int in count:
		dice.append({ "type": type, "style": DiceFactory.default_style(type), "color": color, "label": label })
	return dice
