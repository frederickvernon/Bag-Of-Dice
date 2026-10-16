class_name DicePalette
extends RefCounted
## The die colours users can choose from. Colours are stored in saved sets as
## "#rrggbb" text so the JSON stays readable.

const COLORS: Array[Dictionary] = [
	{ "id": "ivory", "name": "Ivory", "color": Color("#f2edd9") },
	{ "id": "black", "name": "Black", "color": Color("#262626") },
	{ "id": "red", "name": "Red", "color": Color("#d23333") },
	{ "id": "orange", "name": "Orange", "color": Color("#e8742a") },
	{ "id": "yellow", "name": "Yellow", "color": Color("#f2c033") },
	{ "id": "green", "name": "Green", "color": Color("#33a666") },
	{ "id": "teal", "name": "Teal", "color": Color("#2a9d9d") },
	{ "id": "blue", "name": "Blue", "color": Color("#3373d9") },
	{ "id": "purple", "name": "Purple", "color": Color("#8c4dbf") },
	{ "id": "pink", "name": "Pink", "color": Color("#e05c9e") },
]
const DEFAULT_HEX: String = "#f2edd9"


static func to_hex(c: Color) -> String:
	return "#" + c.to_html(false)


## Parses "#rrggbb"; anything else gives the default colour.
static func from_hex(hex: String) -> Color:
	if Color.html_is_valid(hex):
		return Color.html(hex)
	return Color.html(DEFAULT_HEX)


## Palette id ("red") for a stored "#rrggbb", or "" if it isn't a palette colour.
static func id_for_hex(hex: String) -> String:
	for entry: Dictionary in COLORS:
		if to_hex(entry["color"]) == hex.to_lower():
			return entry["id"]
	return ""


static func is_valid_hex(hex: String) -> bool:
	return hex.begins_with("#") and hex.length() == 7 and Color.html_is_valid(hex)
