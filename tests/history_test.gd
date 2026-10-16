extends SceneTree
## RollHistory: 50-roll cap, order, save/load, clearing, damaged files.
## Uses its own throwaway file, never the real history.
##
## Run from the project folder:
##   Godot --headless --path . -s res://tests/history_test.gd

const PATH: String = "user://test_roll_history.json"
## If fewer checks run (e.g. a test stopped early), the run fails.
const EXPECTED_CHECKS: int = 17

var _failures: int = 0
var _checks: int = 0


func _init() -> void:
	_clean()
	_test_cap_and_order()
	_test_reload()
	_test_oversized_file()
	_test_damaged_data()
	_test_clear()
	_test_time_format()
	_clean()
	if _checks != EXPECTED_CHECKS:
		print("\nONLY %d OF %d CHECKS RAN — see errors above" % [_checks, EXPECTED_CHECKS])
		_failures += 1
	preload("res://tests/test_log.gd").line("%s" % ("ALL %d HISTORY CHECKS PASSED" % _checks if _failures == 0 else "HISTORY TESTS FAILED"))
	quit(1 if _failures > 0 else 0)


## `n` d6 all showing `value`.
func _roll(number: int, value: int = 3, n: int = 2) -> Dictionary:
	var results: Array[Dictionary] = []
	for i: int in n:
		results.append({ "type": "d6", "value": value, "color": "#d23333", "label": "", "parts": [value] })
	return RollHistory.make_entry("set-1", "Roll %d" % number, results, 1_700_000_000 + number)


func _test_cap_and_order() -> void:
	print("Cap and order:")
	var h: RollHistory = RollHistory.new(PATH)
	h.load_entries()
	_check(h.entries.is_empty(), "starts empty when there's no file")
	for i: int in range(1, 56):
		h.add(_roll(i))
	_check(h.entries.size() == 50, "keeps only 50 after 55 rolls")
	_check(h.entries[0]["set_name"] == "Roll 55", "newest roll is first")
	_check(h.entries[-1]["set_name"] == "Roll 6", "rolls 1–5 (the oldest) were dropped")
	var e: Dictionary = _roll(99, 4, 3)
	_check(e["total"] == 12 and e["dice"].size() == 3 and e["dice"][0]["color"] == "#d23333",
			"an entry has each die's value and colour, and the total")


func _test_reload() -> void:
	print("Saved copy:")
	var h: RollHistory = RollHistory.new(PATH)
	h.load_entries()
	_check(h.entries.size() == 50 and h.entries[0]["set_name"] == "Roll 55", "the saved copy reloads the same 50, newest first")
	var on_disk: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	_check(on_disk["entries"].size() == 50, "the file on disk holds exactly 50")
	_check(not FileAccess.file_exists(PATH + ".tmp"), "no temporary file left behind")


func _test_oversized_file() -> void:
	print("A file with too many rolls:")
	var many: Array = []
	for i: int in 80:
		many.append(_roll(i))
	JsonFile.write(PATH, { "version": 1, "entries": many })
	var h: RollHistory = RollHistory.new(PATH)
	h.load_entries()
	_check(h.entries.size() == 50, "loading keeps only the first (newest) 50")
	var on_disk: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	_check(on_disk["entries"].size() == 50, "and rewrites the file down to 50")


func _test_damaged_data() -> void:
	print("Damaged data:")
	var good: Dictionary = _roll(1, 5)
	var bad_value: Dictionary = _roll(2, 9)  # a d6 can't show 9
	var wrong_total: Dictionary = _roll(3, 2)
	wrong_total["total"] = 999
	JsonFile.write(PATH, { "version": 1, "entries": [good, "junk", bad_value, wrong_total] })
	var h: RollHistory = RollHistory.new(PATH)
	h.load_entries()
	_check(h.entries.size() == 2, "junk and impossible results are skipped")
	_check(h.entries[1]["total"] == 4, "totals are recalculated, not trusted")

	var f: FileAccess = FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string("not json at all")
	f.close()
	var h2: RollHistory = RollHistory.new(PATH)
	h2.load_entries()
	_check(h2.entries.is_empty() and FileAccess.file_exists(PATH.get_basename() + ".corrupt.json"),
			"an unreadable file is kept aside and history starts empty")


func _test_clear() -> void:
	print("Clear:")
	var h: RollHistory = RollHistory.new(PATH)
	h.load_entries()
	h.add(_roll(1))
	h.add(_roll(2))
	h.clear()
	var reloaded: RollHistory = RollHistory.new(PATH)
	reloaded.load_entries()
	_check(h.entries.is_empty() and reloaded.entries.is_empty(), "clearing empties the saved copy too")


func _test_time_format() -> void:
	print("Time display:")
	var now: int = int(Time.get_unix_time_from_system())
	_check(RollHistory.format_time(now, now).length() == 5, "today shows just the time (hh:mm)")
	_check(RollHistory.format_time(now - 86400, now).begins_with("Yesterday "), "yesterday is labelled")
	_check(RollHistory.format_time(now - 86400 * 10, now).split(" ").size() == 3, "older rolls show day, month and time")


func _check(ok: bool, what: String) -> void:
	_checks += 1
	print("  %s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_failures += 1


func _clean() -> void:
	for p: String in [PATH, PATH + ".tmp", PATH.get_basename() + ".corrupt.json"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
