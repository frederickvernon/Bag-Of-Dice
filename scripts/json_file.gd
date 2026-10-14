class_name JsonFile
extends RefCounted
## Reading and writing app data as JSON files in user://.


## Writes `data` as JSON. Writes to a temporary file first, then swaps it in,
## so a crash mid-save can't leave a half-written file. Returns false on
## failure.
static func write(path: String, data: Variant) -> bool:
	var tmp_path: String = path + ".tmp"
	var file: FileAccess = FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		push_error("Could not save %s: %s" % [path, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	var err: Error = DirAccess.rename_absolute(tmp_path, path)
	if err != OK:
		push_error("Could not save %s: %s" % [path, error_string(err)])
		return false
	return true


## Returns the parsed contents, or null if the file doesn't exist. A file
## that exists but isn't valid JSON is moved aside (see keep_corrupt) and
## null is returned.
static func read(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var json: JSON = JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		keep_corrupt(path)
		return null
	return json.data


## Moves an unreadable file to <name>.corrupt.json so it isn't overwritten
## (and could be recovered by hand).
static func keep_corrupt(path: String) -> void:
	var backup: String = path.get_basename() + ".corrupt.json"
	DirAccess.rename_absolute(path, backup)
	push_warning("%s could not be read; kept it as %s and started fresh." % [path, backup])
