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
		print("[Shiro AI Assistant] Listening on 127.0.0.1:", PORT)
	else:
		push_error("[Shiro AI Assistant] Failed to listen on port %d: %d" % [PORT, err])

func _process(_delta: float) -> void:
	if not tcp_server.is_listening():
		return

	if tcp_server.is_connection_available():
		var peer: StreamPeerTCP = tcp_server.take_connection()
		handle_connection(peer)

func handle_connection(peer: StreamPeerTCP) -> void:
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

func execute_command(cmd: String, payload: Dictionary) -> Dictionary:
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

		"get_current_script":
			var script_info: Dictionary = {}
			if plugin_ref:
				var ei = plugin_ref.get_editor_interface()
				var se = ei.get_script_editor()
				if se:
					var cs = se.get_current_script()
					if cs and cs is Script:
						script_info = {
							"path": cs.resource_path,
							"source_code": cs.source_code
						}
			return {
				"success": true,
				"current_script": script_info
			}

		"get_selected_nodes":
			var nodes_info: Array = []
			if plugin_ref:
				var selection = plugin_ref.get_editor_interface().get_selection().get_selected_nodes()
				for node in selection:
					var script_path = ""
					var node_script = node.get_script()
					if node_script and node_script is Script:
						script_path = node_script.resource_path
					nodes_info.append({
						"name": node.name,
						"type": node.get_class(),
						"path": str(node.get_path()),
						"script_path": script_path
					})
			return {
				"success": true,
				"selected_nodes": nodes_info
			}

		"write_file":
			var file_path = payload.get("path", "")
			var content = payload.get("content", "")
			return apply_file_content(file_path, content)

		"reload_scripts":
			if plugin_ref:
				var ei = plugin_ref.get_editor_interface()
				ei.get_resource_filesystem().scan()
			return {
				"success": true,
				"message": "Editor filesystem scanned and reloaded."
			}

		"reload_plugin":
			if plugin_ref:
				var ei = plugin_ref.get_editor_interface()
				ei.set_plugin_enabled("godot_mcp_bridge", false)
				ei.set_plugin_enabled("godot_mcp_bridge", true)
			return {
				"success": true,
				"message": "Plugin reloaded."
			}

		_:
			return {
				"success": false,
				"error": "Unrecognized command: " + cmd
			}

func apply_file_content(file_path: String, content: String) -> Dictionary:
	if file_path.is_empty():
		return {"success": false, "error": "No file path provided"}

	if not file_path.begins_with("res://") and not file_path.begins_with("user://"):
		file_path = "res://" + file_path

	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if not file:
		return {"success": false, "error": "Failed to open file for writing: " + str(FileAccess.get_open_error())}
	file.store_string(content)
	file.close()

	if plugin_ref:
		var ei = plugin_ref.get_editor_interface()
		ei.get_resource_filesystem().update_file(file_path)
		ei.get_resource_filesystem().scan()
		if file_path.ends_with(".gd"):
			var res = load(file_path)
			if res and res is Script:
				ei.edit_script(res)

	return {
		"success": true,
		"message": "File written and reloaded: " + file_path,
		"path": file_path
	}
