class_name RollHistory
extends RefCounted
## The log of past rolls, newest first, kept to a fixed 50 entries (the oldest
## is dropped when a new roll goes over). Saved as JSON in user://.
##
## File format (plain data so game rules could be layered on later):
## {
##   "version": 1,
##   "entries": [
##     { "time": 1760360000,            ← Unix time, seconds (UTC)
##       "set_id": "…", "set_name": "Risk – Attacker",
##       "total": 11,
##       "dice": [ { "type": "d6", "value": 5, "color": "#d23333",
##                   "label": "", "parts": [5] }, … ] }   ← parts: d100 = [tens, units]
##   ]
## }
##
## The 50 cap is applied on every save and also when loading, so the stored
## copy can never grow past it.

const DEFAULT_PATH: String = "user://roll_history.json"
const FORMAT_VERSION: int = 1
const MAX_ENTRIES: int = 50

const MONTHS: PackedStringArray = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
		"Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

var path: String
var entries: Array[Dictionary] = []


func _init(file_path: String = DEFAULT_PATH) -> void:
	path = file_path


func load_entries() -> void:
	entries.clear()
	var data: Variant = JsonFile.read(path)
	if data == null:
		return  # first run (or an unreadable file, already moved aside)
	if typeof(data) != TYPE_DICTIONARY or typeof(data.get("entries")) != TYPE_ARRAY:
		JsonFile.keep_corrupt(path)
		return
	var raw_entries: Array = data["entries"]
	for raw: Variant in raw_entries:
		var e: Dictionary = sanitize_entry(raw)
		if not e.is_empty():
			entries.append(e)
		if entries.size() >= MAX_ENTRIES:
			break
	# Rewrite a file that held more than the cap (or had bad entries).
	if raw_entries.size() != entries.size():
		save()


## Adds a roll as the newest entry, dropping the oldest beyond the cap, and
## saves.
func add(entry: Dictionary) -> void:
	entries.insert(0, entry)
	while entries.size() > MAX_ENTRIES:
		entries.pop_back()
	save()


func clear() -> void:
	entries.clear()
	save()


func save() -> bool:
	return JsonFile.write(path, { "version": FORMAT_VERSION, "entries": entries })


## Builds an entry from DiceRoller results.
static func make_entry(set_id: String, set_name: String, results: Array[Dictionary],
		unix_time: int = -1) -> Dictionary:
	var dice: Array[Dictionary] = []
	var total: int = 0
	for r: Dictionary in results:
		dice.append({
			"type": r["type"], "value": r["value"], "color": r["color"],
			"label": r.get("label", ""), "parts": r.get("parts", [r["value"]]).duplicate(),
		})
		total += int(r["value"])
	if unix_time < 0:
		unix_time = int(Time.get_unix_time_from_system())
	return { "time": unix_time, "set_id": set_id, "set_name": set_name, "total": total, "dice": dice }


## Returns a clean copy of an entry read from disk, or {} if it's unusable.
## Die values outside the die's range are treated as damage and dropped; the
## total is recalculated rather than trusted.
static func sanitize_entry(raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	var dice: Array[Dictionary] = []
	var total: int = 0
	var raw_dice: Variant = raw.get("dice", [])
	if typeof(raw_dice) != TYPE_ARRAY:
		return {}
	for d: Variant in raw_dice:
		if typeof(d) != TYPE_DICTIONARY:
			continue
		var type: String = str(d.get("type", ""))
		if not DiceFactory.TYPES.has(type):
			continue
		var value: int = int(d.get("value", 0))
		if value < 1 or value > type.substr(1).to_int():
			continue
		var color: String = str(d.get("color", ""))
		if not DicePalette.is_valid_hex(color):
			color = DicePalette.DEFAULT_HEX
		var parts: Array[int] = []
		if typeof(d.get("parts")) == TYPE_ARRAY:
			for p: Variant in d["parts"]:
				parts.append(int(p))
		if parts.is_empty():
			parts.append(value)
		dice.append({
			"type": type, "value": value, "color": color,
			"label": str(d.get("label", "")).left(DiceSetStore.MAX_LABEL_LENGTH), "parts": parts,
		})
		total += value
	if dice.is_empty():
		return {}
	return {
		"time": maxi(0, int(raw.get("time", 0))),
		"set_id": str(raw.get("set_id", "")),
		"set_name": str(raw.get("set_name", "")).left(DiceSetStore.MAX_NAME_LENGTH),
		"total": total,
		"dice": dice,
	}


## "14:32" for today, "Yesterday 14:32", otherwise "13 Oct 14:32" — in the
## device's local time.
static func format_time(unix_time: int, now_unix: int = -1) -> String:
	if now_unix < 0:
		now_unix = int(Time.get_unix_time_from_system())
	var bias: int = int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var t: Dictionary = Time.get_datetime_dict_from_unix_time(unix_time + bias)
	var clock: String = "%02d:%02d" % [t["hour"], t["minute"]]
	var day: int = floori((unix_time + bias) / 86400.0)
	var today: int = floori((now_unix + bias) / 86400.0)
	if day == today:
		return clock
	if day == today - 1:
		return "Yesterday " + clock
	return "%d %s %s" % [t["day"], MONTHS[t["month"] - 1], clock]
