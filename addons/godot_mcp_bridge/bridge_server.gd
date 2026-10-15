@tool
extends Node

const PORT: int = 6008
var tcp_server: TCPServer = TCPServer.new()
var plugin_ref: EditorPlugin = null

func _init(p_plugin: EditorPlugin = null) -> void:
	plugin_ref = p_plugin

func _ready() -> void:
	var err = tcp_server.listen(PORT, "127.0.0.1")
	if err == OK:
		print("[Godot MCP Bridge] Listening on 127.0.0.1:", PORT)
	else:
		push_error("[Godot MCP Bridge] Failed to listen on port %d: %d" % [PORT, err])

func _process(_delta: float) -> void:
	if not tcp_server.is_listening():
		return

	if tcp_server.is_connection_available():
		var peer: StreamPeerTCP = tcp_server.take_connection()
		handle_connection(peer)

func handle_connection(peer: StreamPeerTCP) -> void:
	# Give short time to read
	var timeout_usec: int = 500000 # 500ms
	var start_time: int = Time.get_ticks_usec()
	var raw_data: String = ""

	while Time.get_ticks_usec() - start_time < timeout_usec:
		peer.poll()
		var bytes_avail = peer.get_available_bytes()
		if bytes_avail > 0:
			raw_data += peer.get_utf8_string(bytes_avail)
			if raw_data.contains("\n"):
				break
		OS.delay_msec(5)

	var trimmed = raw_data.strip_edges()
	if trimmed.is_empty():
		peer.disconnect_from_host()
		return

	var json = JSON.new()
	var parse_err = json.parse(trimmed)
	var response: Dictionary = {}

	if parse_err != OK:
		response = {
			"success": false,
			"error": "Malformed JSON: " + json.get_error_message()
		}
	else:
		var req = json.data
		var cmd = req.get("command", "")
		var payload = req.get("payload", {})
		response = execute_command(cmd, payload)

	var response_str = JSON.stringify(response) + "\n"
	peer.put_data(response_str.to_utf8_buffer())
	peer.disconnect_from_host()

func execute_command(cmd: String, _payload: Dictionary) -> Dictionary:
	match cmd:
		"ping":
			return {
				"success": true,
				"message": "pong",
				"engine_version": Engine.get_version_info(),
				"project_path": ProjectSettings.globalize_path("res://")
			}

		"get_open_scenes":
			var scenes: Array = []
			if plugin_ref:
				var ei = plugin_ref.get_editor_interface()
				scenes = ei.get_open_scenes()
			return {
				"success": true,
				"open_scenes": scenes
			}

		"get_selected_nodes":
			var nodes_info: Array = []
			if plugin_ref:
				var selection = plugin_ref.get_editor_interface().get_selection().get_selected_nodes()
				for node in selection:
					nodes_info.append({
						"name": node.name,
						"type": node.get_class(),
						"path": str(node.get_path())
					})
			return {
				"success": true,
				"selected_nodes": nodes_info
			}

		"reload_scripts":
			if plugin_ref:
				var ei = plugin_ref.get_editor_interface()
				ei.get_resource_filesystem().scan()
			return {
				"success": true,
				"message": "Editor filesystem scanned and reloaded."
			}

		_:
			return {
				"success": false,
				"error": "Unrecognized command: " + cmd
			}
