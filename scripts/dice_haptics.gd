class_name DiceHaptics
extends Node
## Phone vibrations on dice impacts, stronger for harder hits. Needs Android's
## VIBRATE permission (granted at install); does nothing on desktop.
## On Android 13+ buzzes are sent as media vibrations through the Android API:
## Godot's own vibrate counts as touch feedback, which phones drop when touch vibration is off.

## VibrationAttributes.USAGE_MEDIA.
const USAGE_MEDIA: int = 19

@export var enabled: bool = true
## Hits slower than this (units/s) don't vibrate.
@export var min_impact_speed: float = 2.5
## Hit speed that gives the strongest buzz.
@export var max_impact_speed: float = 14.0
## Buzz length (ms) for the softest and hardest hits.
@export var min_duration_ms: int = 8
@export var max_duration_ms: int = 30
## Min seconds between buzzes, so many dice landing together don't become one long rumble.
@export var min_gap: float = 0.06

var _last_buzz: float = -1.0
# Android objects for media vibrations; null where unavailable (desktop, Android < 13).
var _vibrator: Variant = null
var _effect_class: Variant = null
var _media_attrs: Variant = null


func _ready() -> void:
	if OS.get_name() != "Android" or not Engine.has_singleton("AndroidRuntime"):
		return
	var activity: Variant = Engine.get_singleton("AndroidRuntime").getActivity()
	var attrs_class: Variant = JavaClassWrapper.wrap("android.os.VibrationAttributes")
	_effect_class = JavaClassWrapper.wrap("android.os.VibrationEffect")
	if activity == null or attrs_class == null or _effect_class == null:
		return
	_media_attrs = attrs_class.createForUsage(USAGE_MEDIA)
	_vibrator = activity.getSystemService("vibrator")
	if _media_attrs == null or _vibrator == null:
		_vibrator = null
	print("Haptics: %s" % ("media vibrations via Android API" if _vibrator != null else "Godot vibrate (touch feedback)"))


## A die hit something at `speed` (units/s). `kind` as DiceRoller.die_impact.
func play_impact(kind: String, speed: float) -> void:
	if not enabled or kind == "cup" or speed < min_impact_speed:
		return  # in the hand the phone is being shaken anyway
	var now: float = Time.get_ticks_msec() / 1000.0
	if now - _last_buzz < min_gap:
		return
	_last_buzz = now
	var strength: float = clampf((speed - min_impact_speed) / (max_impact_speed - min_impact_speed), 0.0, 1.0)
	var ms: int = int(lerpf(min_duration_ms, max_duration_ms, strength))
	var amplitude: float = lerpf(0.25, 1.0, strength)
	if _vibrator != null:
		_vibrator.vibrate(_effect_class.createOneShot(ms, int(amplitude * 255.0)), _media_attrs)
	else:
		Input.vibrate_handheld(ms, amplitude)
