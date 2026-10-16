extends "res://tests/app_test.gd"
## Entitlements and the fake store: default free, cache loading, damaged
## files, pro_changed, every purchase outcome, pending → success / failure,
## restore across restarts, double-tap protection, offline behaviour, and the
## gating helpers. Uses its own files, never the app's.

const ENT: String = "user://ent_test_entitlements.json"
const STORE: String = "user://ent_test_store.json"

var _changes: Array[bool] = []
var _states: Array[String] = []


func _init() -> void:
	test_name = "ENTITLEMENTS"
	uses_app = false


func run() -> void:
	_wipe()

	# Defaults and the cache.
	var e: ProEntitlements = await _open()
	check(not e.is_pro(), "a fresh install is free")
	check(not e.can_duplicate_set() and e.can_add_set(2) and not e.can_add_set(3),
			"free: can add a set at 0–2, not at 3; can't duplicate")
	_stop(e)
	JsonFile.write(ENT, { "version": 1, "owned": [ProConfig.PRODUCT_PRO], "confirmed_at": 5 })
	var store: FakeBillingProvider = FakeBillingProvider.new(STORE)
	store.available = false  # offline: the cache must stand
	e = await _open(store)
	check(e.is_pro() and e.confirmed_at == 5, "cached Pro loads and holds while the store is offline")
	_stop(e)

	_write_raw(ENT, "{ not json")
	e = await _open()
	check(not e.is_pro() and FileAccess.file_exists(ENT.get_basename() + ".corrupt.json"),
			"a damaged file means free, and is kept aside as .corrupt.json")
	_stop(e)
	_wipe()
	JsonFile.write(ENT, { "version": 1, "owned": "bag_of_dice_pro" })
	e = await _open()
	check(not e.is_pro(), "valid JSON in the wrong shape is never treated as Pro")
	_stop(e)
	_wipe()

	# The store's answer wins when it gives one.
	JsonFile.write(ENT, { "version": 1, "owned": [ProConfig.PRODUCT_PRO], "confirmed_at": 5 })
	e = await _open()
	check(not e.is_pro() and _changes == [false], "cache says Pro, store says not owned: free, and pro_changed(false) fires")
	_stop(e)
	_wipe()

	# Purchase outcomes.
	store = FakeBillingProvider.new(STORE)
	e = await _open(store)
	store.next_outcome = BillingProvider.Result.CANCELLED
	await _buy(e)
	check(_states == ["purchasing", "cancelled"] and not e.is_pro(), "CANCELLED: back to free, no error")
	store.next_outcome = BillingProvider.Result.ERROR
	await _buy(e)
	check(_states == ["purchasing", "error"] and not e.is_pro(), "ERROR: reported, still free")
	store.next_outcome = BillingProvider.Result.PENDING
	await _buy(e)
	check(_states == ["purchasing", "pending"] and not e.is_pro() and store.has_pending(), "PENDING: waits, still free")
	_states.clear()
	e.purchase_state_changed.connect(_record_state)
	store.resolve_pending(false)
	await frames(3)
	e.purchase_state_changed.disconnect(_record_state)
	check(_states == ["error"] and not e.is_pro() and not store.has_pending(), "pending → declined: stays free")
	await _buy(e)
	_changes.clear()
	_states.clear()
	e.purchase_state_changed.connect(_record_state)
	store.resolve_pending(true)  # settles later, e.g. with the upgrade screen closed
	await frames(3)
	e.purchase_state_changed.disconnect(_record_state)
	check(e.is_pro() and _changes == [true] and _states == ["success"], "pending → confirmed: Pro unlocks and pro_changed(true) fires")
	check(store.is_acknowledged("token-" + ProConfig.PRODUCT_PRO), "the purchase is acknowledged")
	var saved: Variant = JsonFile.read(ENT)
	check(saved is Dictionary and (saved["owned"] as Array).has(ProConfig.PRODUCT_PRO), "Pro is saved to the cache")
	_stop(e)
	_wipe()

	store = FakeBillingProvider.new(STORE)
	e = await _open(store)
	store.next_outcome = BillingProvider.Result.SUCCESS
	await _buy(e)
	check(_states == ["purchasing", "success"] and e.is_pro(), "SUCCESS: Pro unlocks")
	_stop(e)
	_wipe_entitlements_only()
	store = FakeBillingProvider.new(STORE)
	store.next_outcome = BillingProvider.Result.ALREADY_OWNED
	e = await _open(store)
	check(e.is_pro(), "owned purchases come back on startup (restore across restarts)")
	_stop(e)
	_wipe()

	store = FakeBillingProvider.new(STORE)
	e = await _open(store)
	store.next_outcome = BillingProvider.Result.ALREADY_OWNED
	await _buy(e)
	check(_states == ["purchasing", "success"] and e.is_pro(), "ALREADY_OWNED: treated as owned")
	_stop(e)
	_wipe()

	# Double tap.
	store = FakeBillingProvider.new(STORE)
	e = await _open(store, true, 0.3)
	await create_timer(1.0).timeout  # let the startup store check finish
	var calls: Array[int] = [0]
	store.purchase_finished.connect(func(_a: String, _b: BillingProvider.Result, _c: String, _d: Dictionary) -> void: calls[0] += 1)
	var first: bool = e.purchase_pro()
	var second: bool = e.purchase_pro()
	await create_timer(0.6).timeout
	check(first and not second and calls[0] == 1 and e.is_pro(), "a double tap on Buy starts only one purchase")
	check(not e.purchase_pro(), "buying again once Pro is owned does nothing")
	_stop(e)
	_wipe()

	# Restore.
	store = FakeBillingProvider.new(STORE)
	e = await _open(store)
	var results: Array[String] = []
	e.restore_finished.connect(func(r: String) -> void: results.append(r))
	e.restore_purchases()
	await frames(5)
	store.next_outcome = BillingProvider.Result.SUCCESS
	await _buy(e)
	_stop(e)
	_wipe_entitlements_only()  # e.g. app data cleared; the store still knows
	store = FakeBillingProvider.new(STORE)
	e = await _open(store, false)
	e.restore_finished.connect(func(r: String) -> void: results.append(r))
	e.restore_purchases()
	await frames(5)
	store.available = false
	e.restore_purchases()
	await frames(5)
	check(results == ["none", "restored", "unavailable"], "restore reports none / restored / unavailable: %s" % [results])
	check(e.is_pro(), "a failed restore keeps the current status")
	_stop(e)

	# Colours.
	_wipe()
	e = await _open()
	var free_ok: bool = true
	for id: String in ProConfig.FREE_COLOURS:
		free_ok = free_ok and e.is_colour_available(id)
	var pro_locked: bool = true
	for id: String in ProConfig.PRO_COLOURS:
		pro_locked = pro_locked and not e.is_colour_available(id)
	check(free_ok and pro_locked, "free: the 5 free colours are available, the 5 Pro colours aren't")
	(e.provider as FakeBillingProvider).next_outcome = BillingProvider.Result.SUCCESS
	await _buy(e)
	var all_ok: bool = e.can_add_set(4) and e.can_duplicate_set()
	for id: String in ProConfig.FREE_COLOURS + ProConfig.PRO_COLOURS:
		all_ok = all_ok and e.is_colour_available(id)
	check(all_ok, "Pro: every colour, unlimited sets, duplicate")
	check(ProConfig.FREE_COLOURS.size() + ProConfig.PRO_COLOURS.size() == DicePalette.COLORS.size(),
			"every palette colour is either free or Pro")
	_stop(e)
	_wipe()


## Starts Entitlements on the test files and waits for its first store check.
## `delay`: how slowly the fake store answers (seconds).
func _open(store: FakeBillingProvider = null, wait: bool = true, delay: float = 0.0) -> ProEntitlements:
	if store == null:
		store = FakeBillingProvider.new(STORE)
	store.delay = delay
	var e: ProEntitlements = ProEntitlements.new(ENT, store)
	_changes.clear()
	e.pro_changed.connect(func(on: bool) -> void: _changes.append(on))
	root.add_child(e)
	if wait:
		await frames(6)
	return e


func _buy(e: ProEntitlements) -> void:
	_states.clear()
	e.purchase_state_changed.connect(_record_state)
	e.purchase_pro()
	await frames(6)
	e.purchase_state_changed.disconnect(_record_state)


func _record_state(state: String, _message: String) -> void:
	_states.append(state)


func _stop(e: ProEntitlements) -> void:
	root.remove_child(e)
	e.queue_free()


func _write_raw(path: String, text: String) -> void:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _wipe_entitlements_only() -> void:
	for p: String in [ENT, ENT + ".tmp", ENT.get_basename() + ".corrupt.json"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


func _wipe() -> void:
	_wipe_entitlements_only()
	for p: String in [STORE, STORE + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
