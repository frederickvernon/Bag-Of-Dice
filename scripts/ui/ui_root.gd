extends Control
## Root of all on-screen UI. Applies the app theme as soon as it's created,
## before any child sets itself up, so every control below picks it up.
## Lets taps through to the table except where a child control takes them.


func _init() -> void:
	theme = UITheme.build()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
