class_name AppSettings
extends RefCounted
## App-wide preferences, saved as JSON in user://settings.json:
##   { "version": 1, "sound": true }

const DEFAULT_PATH: String = "user://settings.json"
const FORMAT_VERSION: int = 1

var path: String
var sound: bool = true


func _init(file_path: String = DEFAULT_PATH) -> void:
	path = file_path


func load_settings() -> void:
	var data: Variant = JsonFile.read(path)
	if typeof(data) != TYPE_DICTIONARY:
		if data != null:
			JsonFile.keep_corrupt(path)
		return  # first run: defaults
	sound = data.get("sound", true) != false


func save() -> bool:
	return JsonFile.write(path, { "version": FORMAT_VERSION, "sound": sound })
