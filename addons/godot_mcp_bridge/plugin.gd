@tool
extends EditorPlugin

var bridge_server: Node = null
var chat_dock: Control = null

const BridgeServerScript = preload("bridge_server.gd")
const AIChatDockScript = preload("ai_chat_dock.gd")

func _enter_tree() -> void:
	if BridgeServerScript:
		bridge_server = BridgeServerScript.new(self)
		add_child(bridge_server)
		print("[Godot MCP Bridge] Addon loaded and TCP server started on port 6008.")

	if AIChatDockScript:
		chat_dock = AIChatDockScript.new(self, bridge_server)
		add_control_to_dock(DOCK_SLOT_RIGHT_UL, chat_dock)
		print("[Godot MCP Bridge] Ollama AI Dock added to editor.")

func _exit_tree() -> void:
	if chat_dock:
		remove_control_from_docks(chat_dock)
		chat_dock.queue_free()
		chat_dock = null
		print("[Godot MCP Bridge] Ollama AI Dock removed.")

	if bridge_server:
		bridge_server.queue_free()
		bridge_server = null
		print("[Godot MCP Bridge] Addon unloaded.")
