extends SceneTree
## Base for the tests here: set `test_name` and put the steps in run().
## Exits 0 only if every check passed.
##
## Tests that launch the app must use throwaway data files (run_all.sh passes
## them; they're deleted before and after each test):
##   -- --sets-file=user://test_sets.json --history-file=user://test_history.json
##      --settings-file=user://test_settings.json --entitlements-file=user://test_entitlements.json
##      --fake-store-file=user://test_fake_store.json

const TestLog = preload("res://tests/test_log.gd")
const FILE_ARGS: Array[String] = ["--sets-file=", "--history-file=", "--settings-file=",
		"--entitlements-file=", "--fake-store-file="]

var test_name: String = "TEST"
## If true, the test needs throwaway data files.
var uses_app: bool = true
## Seconds before the test gives up and fails.
var time_limit: float = 240.0

var _checks: int = 0
var _failures: int = 0
var _finished: bool = false


func _initialize() -> void:
	_start.call_deferred()


func _start() -> void:
	if uses_app and _data_files().size() < FILE_ARGS.size():
		TestLog.line("%s: FAIL — needs throwaway data files, e.g. run via tests/run_all.sh" % test_name)
		quit(1)
		return
	create_timer(time_limit).timeout.connect(func() -> void:
		_fail("timed out after %d s" % int(time_limit))
		finish())
	_clean_files()
	await run()
	finish()


func run() -> void:
	pass


func check(ok: bool, what: String) -> void:
	_checks += 1
	print("  %s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_failures += 1
		TestLog.line("  FAIL %s" % what)


func finish() -> void:
	if _finished:
		return
	_finished = true
	_clean_files()
	if _checks == 0:
		_fail("no checks ran")
	if _failures == 0:
		TestLog.line("%s: ALL %d CHECKS PASSED" % [test_name, _checks])
	else:
		TestLog.line("%s: %d OF %d CHECKS FAILED" % [test_name, _failures, _checks])
	quit(0 if _failures == 0 else 1)


## Opens on the start menu.
func launch_main() -> Node:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	return main


## Presses Back once (clearing the app's guard against Android's doubled
## Back events, so tests can press it in quick succession).
func press_back(main: Node) -> void:
	main.set("_last_back_ms", -1000)
	main.call("_go_back")


func frames(n: int) -> void:
	for i: int in n:
		await process_frame


func physics_frames(n: int) -> void:
	for i: int in n:
		await physics_frame


## Saves a screenshot when SHOT is set to a path prefix. Not under --headless.
func snap(shot_name: String) -> void:
	var prefix: String = OS.get_environment("SHOT")
	if not prefix.is_empty() and DisplayServer.get_name() != "headless":
		root.get_texture().get_image().save_png("%s_%s.png" % [prefix, shot_name])


func _fail(what: String) -> void:
	_checks += 1
	_failures += 1
	TestLog.line("  FAIL %s" % what)


func _data_files() -> Array[String]:
	var paths: Array[String] = []
	for arg: String in OS.get_cmdline_user_args():
		for prefix: String in FILE_ARGS:
			if arg.begins_with(prefix):
				var path: String = arg.trim_prefix(prefix)
				if path.begins_with("user://"):
					paths.append(path)
	return paths


func _clean_files() -> void:
	for path: String in _data_files():
		for p: String in [path, path + ".tmp", path.get_basename() + ".corrupt.json"]:
			if FileAccess.file_exists(p):
				DirAccess.remove_absolute(p)
