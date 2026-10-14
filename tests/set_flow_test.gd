extends "res://tests/app_test.gd"
## Dice sets end to end: create a set in the editor, roll it, edit it, delete
## it, check the saved file; then roll a full 20-die set.

var _main: Node
var _store: DiceSetStore
var _roller: DiceRoller


func _init() -> void:
	test_name = "SET FLOW"


func run() -> void:
	_main = launch_main()
	await frames(2)
	_store = _main.get("_store")
	_roller = _main.get_node("DiceRoller")
	var editor: SetEditor = _main.get_node("UI/Root/SetEditor")
	var button: Button = _main.get_node("UI/Root/BottomBar/SetsButton")
	check(_store.sets.size() == 3, "a fresh data file starts with the 3 example sets")

	editor.open({})
	(editor.get("_name_edit") as LineEdit).text = "Test Set"
	editor.call("_add_die", "d20")
	editor.call("_add_die", "d100")
	editor.get("_dice")[0]["label"] = "Attack"
	editor.get("_dice")[0]["color"] = "#3373d9"
	editor.call("_save")
	var created: Dictionary = _store.sets[-1]
	check(created["name"] == "Test Set" and button.text == "Test Set", "a saved set goes onto the table")
	check(_roller.get_dice().size() == 3, "the table has the d20 plus the d100's two dice")

	var results: Array = await _roll()
	check(results.size() == 2 and results[0]["label"] == "Attack" and results[0]["color"] == "#3373d9",
			"roll results carry each die's label and colour")

	editor.open(_store.get_set(created["id"]))
	editor.get("_dice").remove_at(1)
	editor.call("_save")
	check(_roller.get_dice().size() == 1 and _store.get_set(created["id"])["dice"].size() == 1,
			"editing removes a die and reloads the table")

	editor.open(_store.get_set(created["id"]))
	(editor.get("_confirm_delete") as ConfirmationDialog).confirmed.emit()
	check(_store.get_set(created["id"]).is_empty() and button.text == _store.sets[0]["name"],
			"deleting removes the set and falls back to the first one")
	var reloaded: DiceSetStore = DiceSetStore.new(_store.path)
	reloaded.load_sets()
	check(reloaded.sets.size() == 3 and reloaded.get_set(created["id"]).is_empty(),
			"the saved file matches after the delete")

	var big: Dictionary = { "name": "Big", "dice": [] }
	for i: int in 20:
		big["dice"].append({ "type": "d6", "color": "#f2edd9", "label": "" })
	var stored: Dictionary = _store.upsert(big)
	_main.call("_on_set_chosen", stored["id"])
	results = await _roll()
	check(results.size() == 20, "a 20d6 set rolls and gives 20 results")
	snap("20d6")


## Roll button twice (arm, then throw) and wait for the result.
func _roll() -> Array:
	_main.call("_on_roll_button_pressed")
	_main.call("_on_roll_button_pressed")
	var results: Array = await _roller.roll_finished
	await frames(60)
	return results
