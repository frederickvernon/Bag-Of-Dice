class_name RollHistory
extends RefCounted
## Past rolls, newest first, capped at 50. Saved as JSON in user://.
##
## File format:
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
## The cap applies on load as well as on save.

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
	# Rewrite a file that was over the cap or had bad entries.
	if raw_entries.size() != entries.size():
		save()


## Adds as newest, drops the oldest beyond the cap, and saves.
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


## Returns a clean copy, or {} if unusable. Out-of-range die values are
## dropped and the total is recalculated, not trusted.
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


## Groups consecutive dice of the same type and label ("d6: 4  2  5").
## On screen, non-breaking spaces keep "d6:" with its first value on wrap.
static func format_dice(results: Array, for_screen: bool) -> String:
	var groups: Array[Dictionary] = []
	var total: int = 0
	for r: Dictionary in results:
		var label: String = r["label"]
		var die_name: String = r["type"] if label.is_empty() else "%s (%s)" % [label, r["type"]]
		var value: String = str(r["value"])
		if r["type"] == "d100":
			value += " (%02d + %d)" % [r["parts"][0], r["parts"][1]]
		total += r["value"]
		if not groups.is_empty() and groups[-1]["name"] == die_name:
			groups[-1]["values"].append(value)
		else:
			# Plain Array: a PackedStringArray read from a Dictionary is a copy.
			groups.append({ "name": die_name, "values": [value] })

	var nbsp: String = "\u00a0" if for_screen else " "
	var parts: PackedStringArray = PackedStringArray()
	for g: Dictionary in groups:
		var values: PackedStringArray = PackedStringArray()
		for v: String in g["values"] as Array:
			values.append(v.replace(" ", nbsp))
		parts.append(("%s:" % g["name"]).replace(" ", nbsp) + nbsp + "  ".join(values))
	var text: String = ("   " if for_screen else ", ").join(parts)
	if results.size() > 1:
		text += ("\nTotal: %d" if for_screen else "  (total %d)") % total
	return text


## One plain-text line for copying, e.g.
## "Risk (14:32): Attack (d6): 6  5, Defend (d6): 4  (total 15)".
static func format_entry(entry: Dictionary, now_unix: int = -1) -> String:
	var title: String = str(entry.get("set_name", ""))
	if title.is_empty():
		title = "Roll"
	return "%s (%s): %s" % [title, format_time(entry.get("time", 0), now_unix), format_dice(entry.get("dice", []), false)]


## "14:32" today, "Yesterday 14:32", else "13 Oct 14:32", in local time.
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
