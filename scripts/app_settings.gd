class_name AppSettings
extends RefCounted
## App-wide preferences, saved as JSON in user://settings.json:
##   { "version": 1, "sound": true, "haptics": true, "fast_roll": false, "tap_to_roll": true }

const DEFAULT_PATH: String = "user://settings.json"
const FORMAT_VERSION: int = 1

var path: String
var sound: bool = true
## Short vibrations when dice hit something.
var haptics: bool = true
## Rolls play out faster (same physics, sped up) and results lift quicker.
var fast_roll: bool = false
## Tapping the table works like the Roll / Pick up / Throw button; flicking up throws held dice.
var tap_to_roll: bool = true


func _init(file_path: String = DEFAULT_PATH) -> void:
	path = file_path


func load_settings() -> void:
	var data: Variant = JsonFile.read(path)
	if typeof(data) != TYPE_DICTIONARY:
		if data != null:
			JsonFile.keep_corrupt(path)
		return  # first run: defaults
	sound = data.get("sound", true) != false
	haptics = data.get("haptics", true) != false
	fast_roll = data.get("fast_roll", false) == true
	tap_to_roll = data.get("tap_to_roll", true) != false


func save() -> bool:
	return JsonFile.write(path, {
		"version": FORMAT_VERSION, "sound": sound, "haptics": haptics, "fast_roll": fast_roll,
		"tap_to_roll": tap_to_roll,
	})
