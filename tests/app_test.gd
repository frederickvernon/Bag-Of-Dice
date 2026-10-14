extends SceneTree
## Shared base for the tests in this folder. A test extends this file, sets
## `test_name`, and puts its steps in run() (which may use await). Each check
## prints PASS or FAIL; the run exits with code 0 only if every check passed.
##
## Tests that launch the app (uses_app = true) must be given throwaway data
## files, so they never touch the real sets, history or settings:
##   -- --sets-file=user://test_sets.json --history-file=user://test_history.json
##      --settings-file=user://test_settings.json
## run_all.sh passes these. The files are deleted before and after each test.

const FILE_ARGS: Array[String] = ["--sets-file=", "--history-file=", "--settings-file="]

var test_name: String = "TEST"
## Whether the test launches the app (and so needs throwaway data files).
var uses_app: bool = true
## Give up and fail after this many seconds.
var time_limit: float = 240.0

var _checks: int = 0
var _failures: int = 0
var _finished: bool = false


func _initialize() -> void:
	_start.call_deferred()


func _start() -> void:
	if uses_app and _data_files().size() < FILE_ARGS.size():
		print("%s: FAIL — needs throwaway data files, e.g. run via tests/run_all.sh" % test_name)
		quit(1)
		return
	create_timer(time_limit).timeout.connect(func() -> void:
		_fail("timed out after %d s" % int(time_limit))
		finish())
	_clean_files()
	await run()
	finish()


## Override with the test's steps.
func run() -> void:
	pass


func check(ok: bool, what: String) -> void:
	_checks += 1
	print("  %s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_failures += 1


func finish() -> void:
	if _finished:
		return
	_finished = true
	_clean_files()
	if _checks == 0:
		_fail("no checks ran")
	if _failures == 0:
		print("%s: ALL %d CHECKS PASSED" % [test_name, _checks])
	else:
		print("%s: %d OF %d CHECKS FAILED" % [test_name, _failures, _checks])
	quit(0 if _failures == 0 else 1)


## Starts the app's main screen (it opens on the start menu).
func launch_main() -> Node:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	return main


func frames(n: int) -> void:
	for i: int in n:
		await process_frame


func physics_frames(n: int) -> void:
	for i: int in n:
		await physics_frame


## Saves a screenshot if the SHOT environment variable gives a path prefix
## (only works with a window, not --headless).
func snap(shot_name: String) -> void:
	var prefix: String = OS.get_environment("SHOT")
	if not prefix.is_empty() and DisplayServer.get_name() != "headless":
		root.get_texture().get_image().save_png("%s_%s.png" % [prefix, shot_name])


func _fail(what: String) -> void:
	_checks += 1
	_failures += 1
	print("  FAIL %s" % what)


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
