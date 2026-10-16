class_name DeviceTestRunner
extends SceneTree
## Main loop of the phone test build only (feature "device_tests", see
## project.godot and run_on_device.sh); the real app never uses it.
## Runs the test named in user://next_test.txt: "res://tests/x.gd" or
## "res://tests/fairness_test.tscn --throws=600" (extra words become test args).

func _initialize() -> void:
	var words: PackedStringArray = FileAccess.get_file_as_string("user://next_test.txt").strip_edges().split(" ", false)
	if words.is_empty():
		preload("res://tests/test_log.gd").line("DEVICE RUNNER: FAIL — no user://next_test.txt")
		quit(1)
		return
	Engine.set_meta("device_test_args", words.slice(1))
	if words[0].ends_with(".tscn"):
		change_scene_to_file(words[0])
	else:
		# Become the test: tests are SceneTree scripts and expect to be the main loop.
		set_script(load(words[0]))
		call("_initialize")
