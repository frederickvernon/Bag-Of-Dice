extends Control
## Root of all UI. Applies the theme before any child sets itself up.
## Taps pass through to the table except where a child control takes them.


func _init() -> void:
	theme = UITheme.build()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
