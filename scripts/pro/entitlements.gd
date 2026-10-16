class_name ProEntitlements
extends Node
## The one source of truth for what the player has unlocked (autoload
## "Entitlements"). The app asks this, never the store. The answer is cached on
## disk so the app works offline; the store's answer wins whenever it gives one.
## Built around product ids, so further one-time products can be added later.
##
## File: { "version": 1, "owned": ["bag_of_dice_pro"], "confirmed_at": 1760000000 }

signal pro_changed(is_pro: bool)
## Progress of purchase_pro(): "purchasing", "pending", "success", "cancelled" or "error".
signal purchase_state_changed(state: String, message: String)
signal product_info_received(ok: bool, price_text: String)
## Result of restore_purchases(): "restored", "none" or "unavailable".
signal restore_finished(result: String)

const DEFAULT_PATH: String = "user://entitlements.json"
const FORMAT_VERSION: int = 1

var path: String
var provider: BillingProvider
## Unix time the store last confirmed what's owned (0 = never).
var confirmed_at: int = 0

var _owned: Dictionary = {}  # product id -> true
var _purchasing: bool = false
var _restoring: bool = false


## Defaults (empty path, no provider) come from the command line or the real setup.
func _init(file_path: String = "", billing: BillingProvider = null) -> void:
	path = file_path
	provider = billing


func _ready() -> void:
	if path.is_empty():
		path = _arg("--entitlements-file=", DEFAULT_PATH)
	if provider == null:
		provider = _make_provider()
	add_child(provider)
	provider.purchase_finished.connect(_on_purchase_finished)
	provider.owned_purchases_queried.connect(_on_owned_queried)
	provider.product_queried.connect(func(product_id: String, ok: bool, info: Dictionary) -> void:
		if product_id == ProConfig.PRODUCT_PRO:
			product_info_received.emit(ok, str(info.get("price_text", ""))))
	load_cache()
	refresh()


func _make_provider() -> BillingProvider:
	# The real store plugs in here: a PlayBillingProvider built on Godot's Google
	# Play Billing plugin. Until it exists, every build uses the fake store.
	return FakeBillingProvider.new(_arg("--fake-store-file=", FakeBillingProvider.DEFAULT_PATH))


func is_pro() -> bool:
	return owns(ProConfig.PRODUCT_PRO)


func owns(product_id: String) -> bool:
	return _owned.has(product_id)


## Whether one more saved set can be created when `current_count` exist.
func can_add_set(current_count: int) -> bool:
	return is_pro() or current_count < ProConfig.FREE_SET_LIMIT


func can_duplicate_set() -> bool:
	return is_pro()


## `colour_id`: a DicePalette id such as "red".
func is_colour_available(colour_id: String) -> bool:
	return is_pro() or ProConfig.FREE_COLOURS.has(colour_id)


func is_purchasing() -> bool:
	return _purchasing


## Asks the store for Pro's price; answers via product_info_received.
func query_pro_product() -> void:
	provider.query_product(ProConfig.PRODUCT_PRO)


## Starts buying Pro. Returns false (and does nothing) if a purchase is already
## under way or Pro is owned, so a double tap can't start two purchases.
func purchase_pro() -> bool:
	if _purchasing or is_pro():
		return false
	_purchasing = true
	purchase_state_changed.emit("purchasing", "")
	provider.purchase(ProConfig.PRODUCT_PRO)
	return true


## Asks the store what's owned; answers via restore_finished.
func restore_purchases() -> void:
	_restoring = true
	refresh()


## Connects to the store and updates from what it says is owned. A failed
## answer leaves the cached state as it was.
func refresh() -> void:
	provider.connect_service()
	var ok: bool = await provider.service_connected
	if ok:
		provider.query_owned_purchases()
	elif _restoring:
		_restoring = false
		restore_finished.emit("unavailable")


## Reads the cached state. A missing or damaged file means free (a damaged one
## is kept aside as *.corrupt.json); the store check can then restore Pro.
func load_cache() -> void:
	_owned.clear()
	confirmed_at = 0
	var data: Variant = JsonFile.read(path)
	if data == null:
		return
	if typeof(data) != TYPE_DICTIONARY or typeof(data.get("owned")) != TYPE_ARRAY:
		JsonFile.keep_corrupt(path)
		return
	for id: Variant in data["owned"]:
		if typeof(id) == TYPE_STRING:
			_owned[id] = true
	confirmed_at = int(data.get("confirmed_at", 0))


func _save() -> void:
	JsonFile.write(path, { "version": FORMAT_VERSION, "owned": _owned.keys(), "confirmed_at": confirmed_at })


func _on_owned_queried(ok: bool, product_ids: Array[String]) -> void:
	if not ok:
		if _restoring:
			_restoring = false
			restore_finished.emit("unavailable")
		return
	var was_pro: bool = is_pro()
	_owned.clear()
	for id: String in product_ids:
		_owned[id] = true
	confirmed_at = int(Time.get_unix_time_from_system())
	_save()
	if is_pro() != was_pro:
		pro_changed.emit(is_pro())
	if _restoring:
		_restoring = false
		restore_finished.emit("restored" if is_pro() else "none")


func _on_purchase_finished(product_id: String, result: BillingProvider.Result, message: String, purchase: Dictionary) -> void:
	if product_id != ProConfig.PRODUCT_PRO:
		return
	_purchasing = false
	match result:
		BillingProvider.Result.SUCCESS, BillingProvider.Result.ALREADY_OWNED:
			if not purchase.is_empty():
				provider.acknowledge(purchase)
			_grant(product_id)
			purchase_state_changed.emit("success", "")
		BillingProvider.Result.PENDING:
			purchase_state_changed.emit("pending", "")
		BillingProvider.Result.CANCELLED:
			purchase_state_changed.emit("cancelled", "")
		_:
			purchase_state_changed.emit("error", message)


func _grant(product_id: String) -> void:
	var was_pro: bool = is_pro()
	_owned[product_id] = true
	confirmed_at = int(Time.get_unix_time_from_system())
	_save()
	if is_pro() != was_pro:
		pro_changed.emit(is_pro())


static func _arg(prefix: String, fallback: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.trim_prefix(prefix)
	return fallback
