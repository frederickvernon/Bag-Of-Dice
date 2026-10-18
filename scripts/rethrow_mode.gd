class_name RethrowMode
extends RefCounted
## What happens to the other dice when a die has to be re-thrown (cocked, on
## another die, off the table or moving too long). Saved as these ids.

## Everything stays in play until all dice stop.
const LIVE: String = "live"
## Dice that landed cleanly keep their result; they stay on the table and can be knocked.
const COUNT: String = "count"
## Settled dice are read and lifted off before the re-throw.
const CLEAR: String = "clear"
## A set that follows the global setting.
const TABLE_DEFAULT: String = "default"

const MODES: Array[String] = [LIVE, COUNT, CLEAR]
const NAMES: Dictionary = {
	LIVE: "Live table", COUNT: "Count where they land", CLEAR: "Clear the table",
	TABLE_DEFAULT: "Table default",
}
const DESCRIPTIONS: Dictionary = {
	LIVE: "Everything stays in play until all dice stop.",
	COUNT: "Dice that landed cleanly keep their result, like at a real table.",
	CLEAR: "Settled dice are counted and removed before a re-roll.",
}


## The global setting from storage: anything unknown becomes Clear the table.
static func clean_global(value: Variant) -> String:
	var mode: String = str(value) if value is String else ""
	return mode if MODES.has(mode) else CLEAR


## A set's choice from storage: anything unknown (or missing) becomes Table default.
static func clean_set(value: Variant) -> String:
	var mode: String = str(value) if value is String else ""
	return mode if MODES.has(mode) else TABLE_DEFAULT


## The mode a roll actually uses: the set's own choice, or the global one.
static func resolve(set_mode: Variant, global_mode: String) -> String:
	var mode: String = clean_set(set_mode)
	return clean_global(global_mode) if mode == TABLE_DEFAULT else mode
