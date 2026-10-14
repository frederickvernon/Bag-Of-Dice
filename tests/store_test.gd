extends SceneTree
## Tests for DiceSetStore (saving / loading dice sets). Uses its own file in
## user://, never the app's real one, and deletes it afterwards.
##
## Run from the project folder:
##   Godot --headless --path . -s res://tests/store_test.gd

const PATH: String = "user://test_dice_sets.json"

## Number of checks below. If fewer run (e.g. a script failed to compile and
## a test stopped early), the run counts as failed.
const EXPECTED_CHECKS: int = 29

var _failures: int = 0
var _checks: int = 0


func _init() -> void:
	_clean()
	_test_first_run()
	_test_round_trip()
	_test_sanitizing()
	_test_corrupt_file()
	_test_delete()
	_clean()
	if _checks != EXPECTED_CHECKS:
		print("\nONLY %d OF %d CHECKS RAN — see errors above" % [_checks, EXPECTED_CHECKS])
		_failures += 1
	print("\n%s" % ("ALL %d STORE CHECKS PASSED" % _checks if _failures == 0 else "STORE TESTS FAILED"))
	quit(1 if _failures > 0 else 0)


func _test_first_run() -> void:
	print("First run:")
	var store: DiceSetStore = DiceSetStore.new(PATH)
	store.load_sets()
	_check(store.sets.size() == 3, "starts with the 3 example sets")
	_check(FileAccess.file_exists(PATH), "writes the file straight away")
	_check(not FileAccess.file_exists(PATH + ".tmp"), "leaves no temporary file behind")
	var fireball: Dictionary = store.sets[0]
	_check(fireball["name"] == "Fireball" and DiceSetStore.summary(fireball) == "8d6", "Fireball is 8d6")
	var risk: Dictionary = store.sets[1]
	_check(risk["pick_dice"] and risk["dice"][0]["label"] == "Attack" and risk["dice"][4]["label"] == "Defend",
			"Risk holds attack and defend dice, with picking on")


func _test_round_trip() -> void:
	print("Save and reload:")
	var store: DiceSetStore = DiceSetStore.new(PATH)
	store.load_sets()
	var added: Dictionary = store.upsert({
		"name": "  Risk test  ",
		"pick_dice": true,
		"dice": [
			{ "type": "d6", "color": "#d23333", "label": "Attacker" },
			{ "type": "d100", "color": "#3373d9", "label": "" },
		],
	})
	store.set_last_used(added["id"])
	var reloaded: DiceSetStore = DiceSetStore.new(PATH)
	reloaded.load_sets()
	var got: Dictionary = reloaded.get_set(added["id"])
	_check(not got.is_empty(), "new set survives a reload")
	_check(got.get("name") == "Risk test", "name is trimmed")
	_check(got.get("dice", []).size() == 2 and got["dice"][0]["label"] == "Attacker"
			and got["dice"][1]["type"] == "d100" and got["dice"][0]["color"] == "#d23333",
			"dice types, colours and labels survive")
	_check(reloaded.last_set_id == added["id"], "last used set is remembered")
	_check(got.get("pick_dice") == true and DiceSetStore.sanitize_set({ "dice": [{ "type": "d6" }] })["pick_dice"] == false,
			"the pick-dice option survives a reload, and is off unless set")

	got["name"] = "Renamed"
	reloaded.upsert(got)
	var again: DiceSetStore = DiceSetStore.new(PATH)
	again.load_sets()
	_check(again.get_set(added["id"])["name"] == "Renamed" and again.sets.size() == 4,
			"editing replaces the set instead of adding a copy")


func _test_sanitizing() -> void:
	print("Cleaning bad data:")
	var many: Array = []
	for i: int in 30:
		many.append({ "type": "d6", "color": "#ffffff" })
	var s: Dictionary = DiceSetStore.sanitize_set({
		"name": "x".repeat(100),
		"dice": [
			{ "type": "d7", "color": "#ffffff" },
			{ "type": "d20", "color": "not a colour", "label": "y".repeat(100) },
			"junk",
		],
	})
	_check(s["name"].length() == DiceSetStore.MAX_NAME_LENGTH, "long names are shortened")
	_check(s["dice"].size() == 1 and s["dice"][0]["type"] == "d20", "unknown die types and junk are dropped")
	_check(s["dice"][0]["color"] == DicePalette.DEFAULT_HEX, "bad colours fall back to ivory")
	_check(s["dice"][0]["label"].length() == DiceSetStore.MAX_LABEL_LENGTH, "long labels are shortened")
	_check(DiceSetStore.sanitize_set({ "name": "Many", "dice": many })["dice"].size() == DiceSetStore.MAX_DICE,
			"dice are capped at %d" % DiceSetStore.MAX_DICE)
	var hundreds: Array = []
	for i: int in 20:
		hundreds.append({ "type": "d100" })
	var capped: Dictionary = DiceSetStore.sanitize_set({ "name": "d100s", "dice": hundreds })
	_check(capped["dice"].size() == 10 and DiceSetStore.physical_count(capped) == 20,
			"20 d100s are cut to 10 — each d100 is 2 physical dice")
	var mixed: Array = many.slice(0, 19) + [{ "type": "d100" }, { "type": "d6" }]
	var fit: Dictionary = DiceSetStore.sanitize_set({ "name": "Mixed", "dice": mixed })
	_check(DiceSetStore.physical_count(fit) == 20 and fit["dice"][-1]["type"] == "d6",
			"a d100 that doesn't fit is skipped, but a later single die that does is kept")
	_check(DiceSetStore.sanitize_set({ "name": "Empty", "dice": [] }).is_empty(), "a set with no dice is rejected")
	_check(DiceSetStore.sanitize_set("junk").is_empty(), "a non-object is rejected")
	var styled: Dictionary = DiceSetStore.sanitize_set({ "dice": [
		{ "type": "d6" }, { "type": "d6", "style": "numbers" }, { "type": "d10", "style": "bogus" }, { "type": "d20", "style": "pips" }] })
	_check(styled["dice"][0]["style"] == "pips" and styled["dice"][1]["style"] == "numbers",
			"d6 defaults to pips; a chosen style is kept")
	_check(styled["dice"][2]["style"] == "zero" and styled["dice"][3]["style"] == "",
			"unknown styles fall back to the default; types without styles get none")
	_check(DiceSetStore.sanitize_set({ "name": "   ", "dice": many })["name"] == "Untitled set",
			"a blank name gets a placeholder")


func _test_corrupt_file() -> void:
	print("Corrupt file:")
	var f: FileAccess = FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string("{ this is not json")
	f.close()
	var store: DiceSetStore = DiceSetStore.new(PATH)
	store.load_sets()
	var backup: String = PATH.get_basename() + ".corrupt.json"
	_check(FileAccess.file_exists(backup), "the unreadable file is kept as a backup")
	_check(FileAccess.get_file_as_string(backup) == "{ this is not json", "the backup is untouched")
	_check(store.sets.size() == 3, "the app starts again with the example sets")


func _test_delete() -> void:
	print("Delete:")
	var store: DiceSetStore = DiceSetStore.new(PATH)
	store.load_sets()
	var id: String = store.sets[1]["id"]
	store.set_last_used(id)
	store.delete(id)
	var reloaded: DiceSetStore = DiceSetStore.new(PATH)
	reloaded.load_sets()
	_check(reloaded.get_set(id).is_empty() and reloaded.sets.size() == 2, "deleted set is gone after reload")
	_check(reloaded.last_set_id == "", "last used set is cleared when it's deleted")
	for s: Dictionary in reloaded.sets.duplicate():
		reloaded.delete(s["id"])
	var empty: DiceSetStore = DiceSetStore.new(PATH)
	empty.load_sets()
	_check(empty.sets.is_empty(), "deleting every set stays empty (examples aren't re-added)")


func _check(ok: bool, what: String) -> void:
	_checks += 1
	print("  %s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_failures += 1


func _clean() -> void:
	for p: String in [PATH, PATH + ".tmp", PATH.get_basename() + ".corrupt.json"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
