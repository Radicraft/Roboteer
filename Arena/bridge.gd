extends Node
## Bridge: the single, narrow, data-only contract between the SwiftUI shell and
## the embedded Godot arena. See docs/bridge-spec.md; that file is the authority.
##
## Wire format, both directions, is a Godot Dictionary with exactly two keys:
##   type: String  message name, snake_case
##   json: String  UTF-8 JSON text of the payload (may be "{}")

## Emitted for every message arriving from the host, plus the synthetic
## "bridge_attached" message when the host node is first found.
signal message_received(type: String, payload: Dictionary)

## Local only, not part of the wire contract. Emitted by send() whether or not a
## host is attached, so headless tests can observe what the arena would send.
signal message_sent(type: String, payload: Dictionary)

const BRIDGE_NODE := "__swiftgodotkit_bridge__"

const SINGLETON := "RoboteerHost"

var _host: Node = null
## The app's own singleton (Roboteer/HostBridge.swift), preferred when present.
var _singleton: Object = null


func _process(_dt: float) -> void:
	if _singleton == null and Engine.has_singleton(SINGLETON):
		_singleton = Engine.get_singleton(SINGLETON)
		_singleton.message_from_host.connect(_on_singleton_message)
		print("Bridge: RoboteerHost singleton attached")
	if _host == null:
		_host = get_tree().root.get_node_or_null(BRIDGE_NODE)
		if _host != null:
			_host.message_from_host.connect(_on_message_from_host)
			print("Bridge: SwiftGodotKit host node attached")
	if is_attached():
		set_process(false)
		emit_signal("message_received", "bridge_attached", {})


## True once a host (singleton or SwiftGodotKit node) has been found and connected.
func is_attached() -> bool:
	return _singleton != null or _host != null


func send(type: String, payload: Dictionary) -> void:
	emit_signal("message_sent", type, payload)
	if not is_attached():
		push_warning("Bridge.send before attach: " + type)
		return
	var json := JSON.stringify(payload)
	if _singleton != null:
		# Signals are the only Godot -> Swift path that works; never call Swift methods.
		_singleton.message_to_host.emit(type, json)
	elif _host != null:
		_host.emit_message_to_host({"type": type, "json": json})


func _on_singleton_message(type: String, json: String) -> void:
	_on_message_from_host({"type": type, "json": json})


## Test seam: drive the exact host receive path without a host attached.
func inject_from_host(message: Dictionary) -> void:
	_on_message_from_host(message)


func _on_message_from_host(message: Dictionary) -> void:
	var type := str(message.get("type", ""))
	var parsed: Variant = JSON.parse_string(str(message.get("json", "{}")))
	var payload: Dictionary = parsed if parsed is Dictionary else {}
	emit_signal("message_received", type, payload)
