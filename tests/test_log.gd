extends RefCounted
## Appends test output to user://test_results.log as well as printing it, so
## results can be read back from a phone whose system log is hidden.

const PATH: String = "user://test_results.log"


static func line(text: String) -> void:
	print(text)
	var f: FileAccess = FileAccess.open(PATH, FileAccess.READ_WRITE if FileAccess.file_exists(PATH) else FileAccess.WRITE)
	if f != null:
		f.seek_end()
		f.store_line(text)
		f.close()
