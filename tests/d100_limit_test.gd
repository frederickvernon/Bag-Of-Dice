extends "res://tests/app_test.gd"
## The 20-dice limit counts a d100 as two, in the editor and on the table.

func _init() -> void:
	test_name = "D100 LIMIT"


func run() -> void:
	var main: Node = launch_main()
	await frames(2)
	var editor: SetEditor = main.get_node("UI/Root/SetEditor")
	var adds: Array = editor.get("_add_buttons")
	var add_d100: Button = adds[DiceFactory.TYPES.find("d100")]
	var add_d6: Button = adds[DiceFactory.TYPES.find("d6")]
	editor.open({})
	(editor.get("_name_edit") as LineEdit).text = "Max d100"
	for i: int in 15:
		editor.call("_add_die", "d100")
	var dice: Array = editor.get("_dice")
	check(dice.size() == 10, "adding d100s stops at 10 (= 20 dice)")
	check(add_d100.disabled and add_d6.disabled, "every add button is disabled when the set is full")

	dice.remove_at(9)
	editor.call("_rebuild_rows")
	editor.call("_add_die", "d6")
	check(add_d100.disabled and not add_d6.disabled, "with one place left, a d6 can be added but not a d100")
	editor.call("_add_die", "d6")  # 9 x d100 + 2 x d6 = 20: full

	var rows: VBoxContainer = editor.get("_rows")
	var type_picker: OptionButton = rows.get_child(rows.get_child_count() - 1).get_child(1)
	var d100_item: int = -1
	for i: int in type_picker.item_count:
		if type_picker.get_item_text(i) == "d100":
			d100_item = i
	type_picker.select(d100_item)
	type_picker.item_selected.emit(d100_item)
	check(dice[-1]["type"] == "d6" and not (editor.get("_error") as Label).text.is_empty(),
			"changing a die to d100 when it won't fit is refused with a message")

	dice.remove_at(dice.size() - 1)
	dice[-1]["type"] = "d100"  # 10 x d100
	editor.call("_save")
	await frames(10)
	var roller: DiceRoller = main.get_node("DiceRoller")
	check(roller.get_dice().size() == 20, "a 10 x d100 set puts 20 dice on the table, not 40")
	main.call("_on_roll_button_pressed")
	await frames(40)
	main.call("_on_roll_button_pressed")
	var results: Array = await roller.roll_finished
	check(results.size() == 10, "it rolls and gives 10 d100 results")
