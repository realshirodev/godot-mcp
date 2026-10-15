@tool
extends EditorPlugin

var bridge_server: Node = null

func _enter_tree() -> void:
	var script = load("res://addons/godot_mcp_bridge/bridge_server.gd")
	if script:
		bridge_server = script.new(self)
		add_child(bridge_server)
		print("[Godot MCP Bridge] Addon loaded and TCP server started on port 6008.")

func _exit_tree() -> void:
	if bridge_server:
		bridge_server.queue_free()
		bridge_server = null
		print("[Godot MCP Bridge] Addon unloaded.")
