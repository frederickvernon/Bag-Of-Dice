class_name DicePalette
extends RefCounted
## The die colours users can choose from. Colours are stored in saved sets as
## "#rrggbb" text so the JSON stays readable.

const COLORS: Array[Dictionary] = [
	{ "name": "Ivory", "color": Color("#f2edd9") },
	{ "name": "Black", "color": Color("#262626") },
	{ "name": "Red", "color": Color("#d23333") },
	{ "name": "Orange", "color": Color("#e8742a") },
	{ "name": "Yellow", "color": Color("#f2c033") },
	{ "name": "Green", "color": Color("#33a666") },
	{ "name": "Teal", "color": Color("#2a9d9d") },
	{ "name": "Blue", "color": Color("#3373d9") },
	{ "name": "Purple", "color": Color("#8c4dbf") },
	{ "name": "Pink", "color": Color("#e05c9e") },
]
const DEFAULT_HEX: String = "#f2edd9"


static func to_hex(c: Color) -> String:
	return "#" + c.to_html(false)


## Parses "#rrggbb"; anything else gives the default colour.
static func from_hex(hex: String) -> Color:
	if Color.html_is_valid(hex):
		return Color.html(hex)
	return Color.html(DEFAULT_HEX)


static func is_valid_hex(hex: String) -> bool:
	return hex.begins_with("#") and hex.length() == 7 and Color.html_is_valid(hex)
