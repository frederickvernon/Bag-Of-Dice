class_name BillingProvider
extends Node
## What any store connection must do. Every call answers later through a
## signal, so slow or offline stores never block the app.

enum Result { SUCCESS, CANCELLED, PENDING, ALREADY_OWNED, ERROR }

signal service_connected(ok: bool)
## `info`: { "price_text": "$3.99", "title": "…" }, or {} if the store can't be reached.
signal product_queried(product_id: String, ok: bool, info: Dictionary)
## A purchase finished, or a pending one was later resolved. `purchase`:
## { "product_id", "token" } (needed to acknowledge a SUCCESS).
signal purchase_finished(product_id: String, result: Result, message: String, purchase: Dictionary)
signal owned_purchases_queried(ok: bool, product_ids: Array[String])
signal acknowledged(product_id: String, ok: bool)


func connect_service() -> void:
	push_error("BillingProvider.connect_service not implemented")


func query_product(_product_id: String) -> void:
	push_error("BillingProvider.query_product not implemented")


func purchase(_product_id: String) -> void:
	push_error("BillingProvider.purchase not implemented")


func query_owned_purchases() -> void:
	push_error("BillingProvider.query_owned_purchases not implemented")


## Real stores refund purchases that aren't acknowledged (Google: within 3 days).
func acknowledge(_purchase: Dictionary) -> void:
	push_error("BillingProvider.acknowledge not implemented")
