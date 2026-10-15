@tool
extends EditorPlugin

var bridge_server: Node = null
var chat_dock: Control = null

func _enter_tree() -> void:
	_cleanup_docks()

	var bridge_class = load("res://addons/godot_mcp_bridge/bridge_server.gd")
	if not bridge_class:
		bridge_class = load("res://Addons/godot_mcp_bridge/bridge_server.gd")
	if bridge_class:
		bridge_server = bridge_class.new(self)
		add_child(bridge_server)
		print("[Shiro AI Assistant] Servidor TCP iniciado en puerto 6008.")

	var dock_class = load("res://addons/godot_mcp_bridge/ai_chat_dock.gd")
	if not dock_class:
		dock_class = load("res://Addons/godot_mcp_bridge/ai_chat_dock.gd")
	if dock_class:
		chat_dock = dock_class.new(self, bridge_server)
		chat_dock.name = "Shiro AI Assistant"
		add_control_to_dock(DOCK_SLOT_RIGHT_UL, chat_dock)
		print("[Shiro AI Assistant] Pestaña Shiro AI Assistant agregada al editor.")

func _exit_tree() -> void:
	_cleanup_docks()

	if bridge_server:
		bridge_server.queue_free()
		bridge_server = null
		print("[Shiro AI Assistant] Desactivado.")

func _cleanup_docks() -> void:
	if chat_dock:
		remove_control_from_docks(chat_dock)
		chat_dock.queue_free()
		chat_dock = null

	var base = get_editor_interface().get_base_control()
	if base:
		for name_to_check in ["Ollama AI", "Shiro AI Assistant"]:
			var found = base.find_children(name_to_check, "Control", true, false)
			for child in found:
				remove_control_from_docks(child)
				child.queue_free()
