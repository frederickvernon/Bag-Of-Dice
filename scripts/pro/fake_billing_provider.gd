class_name FakeBillingProvider
extends BillingProvider
## Stand-in store for development. Debug tools choose what the next purchase
## returns and how slow the store is. "Owned" is kept in its own file so
## restoring can be tested across restarts.
##
## File: { "version": 1, "owned": ["bag_of_dice_pro"], "pending": { "<product>": "<token>" } }

const DEFAULT_PATH: String = "user://fake_store.json"

var path: String
## What the next purchase() returns.
var next_outcome: Result = Result.SUCCESS
## Seconds every call takes to answer.
var delay: float = 0.3
## When false, every call fails as if offline.
var available: bool = true

var _owned: Array[String] = []
var _pending: Dictionary = {}  # product id -> token
var _acknowledged: Dictionary = {}  # token -> true


func _init(file_path: String = DEFAULT_PATH) -> void:
	path = file_path
	var data: Variant = JsonFile.read(path)
	if typeof(data) == TYPE_DICTIONARY:
		for id: Variant in data.get("owned", []):
			_owned.append(str(id))
		if typeof(data.get("pending")) == TYPE_DICTIONARY:
			_pending = data["pending"]


func connect_service() -> void:
	await _wait()
	service_connected.emit(available)


func query_product(product_id: String) -> void:
	await _wait()
	if not available or product_id != ProConfig.PRODUCT_PRO:
		product_queried.emit(product_id, false, {})
		return
	product_queried.emit(product_id, true, { "price_text": ProConfig.FAKE_PRICE_TEXT, "title": ProConfig.FAKE_PRODUCT_TITLE })


func purchase(product_id: String) -> void:
	await _wait()
	if not available:
		purchase_finished.emit(product_id, Result.ERROR, "Store unavailable", {})
		return
	if _owned.has(product_id):
		purchase_finished.emit(product_id, Result.ALREADY_OWNED, "", { "product_id": product_id, "token": "owned-" + product_id })
		return
	match next_outcome:
		Result.SUCCESS:
			_grant(product_id)
			purchase_finished.emit(product_id, Result.SUCCESS, "", _purchase_for(product_id))
		Result.PENDING:
			_pending[product_id] = "pending-%d" % Time.get_ticks_usec()
			_save()
			purchase_finished.emit(product_id, Result.PENDING, "", {})
		Result.CANCELLED:
			purchase_finished.emit(product_id, Result.CANCELLED, "", {})
		Result.ALREADY_OWNED:
			# As if bought earlier on another device: the store now reports it owned.
			_grant(product_id)
			purchase_finished.emit(product_id, Result.ALREADY_OWNED, "", _purchase_for(product_id))
		_:
			purchase_finished.emit(product_id, Result.ERROR, "Simulated store error", {})


func query_owned_purchases() -> void:
	await _wait()
	owned_purchases_queried.emit(available, _owned.duplicate() if available else ([] as Array[String]))


func acknowledge(purchase_data: Dictionary) -> void:
	await _wait()
	_acknowledged[purchase_data.get("token", "")] = true
	acknowledged.emit(str(purchase_data.get("product_id", "")), available)


# Developer controls (used by tests and the debug panel).

func has_pending(product_id: String = ProConfig.PRODUCT_PRO) -> bool:
	return _pending.has(product_id)


## Settles a pending purchase, as the store would later.
func resolve_pending(success: bool, product_id: String = ProConfig.PRODUCT_PRO) -> void:
	if not _pending.has(product_id):
		return
	_pending.erase(product_id)
	if success:
		_grant(product_id)
		purchase_finished.emit(product_id, Result.SUCCESS, "", _purchase_for(product_id))
	else:
		_save()
		purchase_finished.emit(product_id, Result.ERROR, "Payment declined", {})


## Forgets every purchase, as if on a new account.
func reset_store() -> void:
	_owned.clear()
	_pending.clear()
	_acknowledged.clear()
	_save()


func is_acknowledged(token: String) -> bool:
	return _acknowledged.has(token)


func _grant(product_id: String) -> void:
	if not _owned.has(product_id):
		_owned.append(product_id)
	_save()


func _purchase_for(product_id: String) -> Dictionary:
	return { "product_id": product_id, "token": "token-" + product_id }


func _save() -> void:
	JsonFile.write(path, { "version": 1, "owned": _owned, "pending": _pending })


func _wait() -> void:
	if delay > 0.0 and is_inside_tree():
		await get_tree().create_timer(delay).timeout
	else:
		await Engine.get_main_loop().process_frame
