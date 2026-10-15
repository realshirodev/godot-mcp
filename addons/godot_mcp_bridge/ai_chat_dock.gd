@tool
extends VBoxContainer

var plugin_ref: EditorPlugin = null
var bridge_ref: Node = null

const OLLAMA_HOST: String = "http://127.0.0.1:11434"
const CLAUDE_ENDPOINT: String = "https://api.anthropic.com/v1/messages"
const OPENAI_ENDPOINT: String = "https://api.openai.com/v1/chat/completions"
const CONFIG_FILE_PATH: String = "user://shiro_ai_config.json"

enum Provider {
	OLLAMA = 0,
	CLAUDE = 1,
	OPENAI = 2
}

var current_provider: int = Provider.OLLAMA
var messages: Array = []
var is_requesting: bool = false
var attached_scripts: Array[String] = []
var poll_timer: float = 0.0
var copy_buffers: Dictionary = {}
var copy_counter: int = 0

# UI Elements
var provider_dropdown: OptionButton
var model_dropdown: OptionButton
var status_label: Label
var refresh_btn: Button
var key_container: HBoxContainer
var key_label: Label
var key_input: LineEdit
var agent_card: PanelContainer
var agent_node_label: Label
var agent_script_label: Label
var scripts_bar: HBoxContainer
var attach_btn: Button
var attach_open_btn: Button
var clear_scripts_btn: Button
var chips_container: HFlowContainer
var file_dialog: FileDialog
var opt_hbox: HBoxContainer
var auto_apply_checkbox: CheckBox
var auto_attach_checkbox: CheckBox
var clear_btn: Button
var chat_display: RichTextLabel
var prompt_input: TextEdit
var send_btn: Button
var http_request: HTTPRequest
var tags_request: HTTPRequest

const CLAUDE_MODELS = [
	"claude-opus-4-5",
	"claude-3-7-sonnet-20250219",
	"claude-3-5-sonnet-20241022",
	"claude-3-5-haiku-20241022",
]
const OPENAI_MODELS = [
	"gpt-4o",
	"gpt-4o-mini",
	"o3-mini"
]

func _init(p_plugin: EditorPlugin = null, p_bridge: Node = null) -> void:
	plugin_ref = p_plugin
	bridge_ref = p_bridge
	name = "Shiro AI Assistant"

func _ready() -> void:
	add_theme_constant_override("separation", 4)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_ui()
	_setup_http()
	_connect_editor_signals()
	_load_config()
	_update_provider_ui()
	_update_agent_card()
	_update_chips_ui()

func _process(delta: float) -> void:
	poll_timer += delta
	if poll_timer >= 0.3:
		poll_timer = 0.0
		_update_agent_card()

func _connect_editor_signals() -> void:
	if not plugin_ref:
		return
	if not plugin_ref.scene_changed.is_connected(func(_root): _update_agent_card()):
		plugin_ref.scene_changed.connect(func(_root): _update_agent_card())
	if not plugin_ref.scene_closed.is_connected(func(_path): _update_agent_card()):
		plugin_ref.scene_closed.connect(func(_path): _update_agent_card())
	var ei = plugin_ref.get_editor_interface()
	var se = ei.get_script_editor()
	if se and not se.editor_script_changed.is_connected(func(_scr): _update_agent_card()):
		se.editor_script_changed.connect(func(_scr): _update_agent_card())
	var sel = ei.get_selection()
	if sel and not sel.selection_changed.is_connected(func(): _update_agent_card()):
		sel.selection_changed.connect(func(): _update_agent_card())

func _setup_http() -> void:
	tags_request = HTTPRequest.new()
	add_child(tags_request)
	tags_request.request_completed.connect(_on_tags_completed)
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.timeout = 300.0
	http_request.request_completed.connect(_on_chat_completed)

func _build_ui() -> void:

	var row1 = HBoxContainer.new()
	row1.add_theme_constant_override("separation", 6)
	add_child(row1)
	var prov_lbl = Label.new()
	prov_lbl.text = "IA:"
	row1.add_child(prov_lbl)
	provider_dropdown = OptionButton.new()
	provider_dropdown.add_item("Ollama (Local)")
	provider_dropdown.add_item("Claude (Anthropic)")
	provider_dropdown.add_item("OpenAI")
	provider_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	provider_dropdown.item_selected.connect(_on_provider_selected)
	row1.add_child(provider_dropdown)
	status_label = Label.new()
	status_label.text = "Listo"
	status_label.modulate = Color(0.2, 0.9, 0.3)
	row1.add_child(status_label)

	var row2 = HBoxContainer.new()
	row2.add_theme_constant_override("separation", 6)
	add_child(row2)
	var model_lbl = Label.new()
	model_lbl.text = "Modelo:"
	row2.add_child(model_lbl)
	model_dropdown = OptionButton.new()
	model_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	model_dropdown.item_selected.connect(func(_idx): _save_config())
	row2.add_child(model_dropdown)
	refresh_btn = Button.new()
	refresh_btn.text = "Refrescar"
	refresh_btn.tooltip_text = "Refrescar modelos disponibles"
	refresh_btn.pressed.connect(_on_refresh_pressed)
	row2.add_child(refresh_btn)

	key_container = HBoxContainer.new()
	key_container.add_theme_constant_override("separation", 6)
	add_child(key_container)
	key_label = Label.new()
	key_label.text = "API Key:"
	key_container.add_child(key_label)
	key_input = LineEdit.new()
	key_input.secret = true
	key_input.placeholder_text = "sk-ant-..."
	key_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key_input.text_changed.connect(func(_t): _save_config())
	key_container.add_child(key_input)

	agent_card = PanelContainer.new()
	var card_vbox = VBoxContainer.new()
	card_vbox.add_theme_constant_override("separation", 2)
	agent_card.add_child(card_vbox)
	add_child(agent_card)
	var title_lbl = Label.new()
	title_lbl.text = "CONTEXTO ACTIVO DEL AGENTE"
	title_lbl.modulate = Color(0.5, 0.8, 1.0)
	card_vbox.add_child(title_lbl)
	agent_node_label = Label.new()
	agent_node_label.text = "Nodo: (Ninguno)"
	agent_node_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card_vbox.add_child(agent_node_label)
	agent_script_label = Label.new()
	agent_script_label.text = "Script: (Sin script)"
	agent_script_label.modulate = Color(0.8, 0.8, 0.8)
	agent_script_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card_vbox.add_child(agent_script_label)

	scripts_bar = HBoxContainer.new()
	scripts_bar.add_theme_constant_override("separation", 4)
	add_child(scripts_bar)
	var scr_lbl = Label.new()
	scr_lbl.text = "Scripts extra:"
	scripts_bar.add_child(scr_lbl)
	attach_btn = Button.new()
	attach_btn.text = "Adjuntar"
	attach_btn.tooltip_text = "Adjuntar script(s) del proyecto"
	attach_btn.pressed.connect(func(): file_dialog.popup_centered_ratio(0.7))
	scripts_bar.add_child(attach_btn)
	attach_open_btn = Button.new()
	attach_open_btn.text = "Abiertos"
	attach_open_btn.tooltip_text = "Adjuntar todos los scripts abiertos en el editor"
	attach_open_btn.pressed.connect(_on_attach_open_pressed)
	scripts_bar.add_child(attach_open_btn)
	clear_scripts_btn = Button.new()
	clear_scripts_btn.text = "Quitar todos"
	clear_scripts_btn.tooltip_text = "Quitar scripts adjuntos"
	clear_scripts_btn.pressed.connect(func():
		attached_scripts.clear()
		_update_chips_ui()
	)
	scripts_bar.add_child(clear_scripts_btn)

	chips_container = HFlowContainer.new()
	chips_container.add_theme_constant_override("h_separation", 4)
	chips_container.add_theme_constant_override("v_separation", 3)
	add_child(chips_container)

	opt_hbox = HBoxContainer.new()
	opt_hbox.add_theme_constant_override("separation", 8)
	add_child(opt_hbox)
	auto_apply_checkbox = CheckBox.new()
	auto_apply_checkbox.text = "Auto-guardar"
	auto_apply_checkbox.button_pressed = true
	auto_apply_checkbox.tooltip_text = "Guarda y recarga los scripts en disco automaticamente"
	auto_apply_checkbox.toggled.connect(func(_b): _save_config())
	opt_hbox.add_child(auto_apply_checkbox)
	auto_attach_checkbox = CheckBox.new()
	auto_attach_checkbox.text = "Auto-adjuntar"
	auto_attach_checkbox.button_pressed = true
	auto_attach_checkbox.tooltip_text = "Adjunta el nuevo script al nodo seleccionado si no tenia ninguno"
	auto_attach_checkbox.toggled.connect(func(_b): _save_config())
	opt_hbox.add_child(auto_attach_checkbox)
	clear_btn = Button.new()
	clear_btn.text = "Limpiar chat"
	clear_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	clear_btn.pressed.connect(_on_clear_pressed)
	opt_hbox.add_child(clear_btn)

	chat_display = RichTextLabel.new()
	chat_display.bbcode_enabled = true
	chat_display.scroll_following = true
	chat_display.selection_enabled = true
	chat_display.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_display.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chat_display.custom_minimum_size = Vector2(0, 160)
	chat_display.meta_clicked.connect(_on_chat_meta_clicked)
	add_child(chat_display)
	chat_display.append_text("[color=#888888][i]Shiro AI listo. Selecciona un nodo o script y pideme hacer cambios directamente.[/i][/color]\n\n")

	var input_hbox = HBoxContainer.new()
	input_hbox.add_theme_constant_override("separation", 6)
	add_child(input_hbox)
	prompt_input = TextEdit.new()
	prompt_input.placeholder_text = "Ej: haz que colisione con el suelo (Enter=enviar, Shift+Enter=nueva linea)..."
	prompt_input.custom_minimum_size = Vector2(0, 52)
	prompt_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prompt_input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	prompt_input.gui_input.connect(_on_input_gui_input)
	input_hbox.add_child(prompt_input)
	send_btn = Button.new()
	send_btn.text = "Enviar"
	send_btn.custom_minimum_size = Vector2(65, 0)
	send_btn.pressed.connect(_on_send_pressed)
	input_hbox.add_child(send_btn)

	file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	file_dialog.access = FileDialog.ACCESS_RESOURCES
	file_dialog.filters = PackedStringArray(["*.gd ; GDScript"])
	file_dialog.files_selected.connect(_on_files_selected)
	add_child(file_dialog)

# ---------------------------------------------------------------------------
# CONTEXT RESOLUTION
# Priority: 1) Node selected in scene  2) Active script in script editor
# ---------------------------------------------------------------------------

func _get_context() -> Dictionary:
	var ctx := {}
	if plugin_ref:
		var ei = plugin_ref.get_editor_interface()
		var selection = ei.get_selection().get_selected_nodes()
		if not selection.is_empty():
			var node = selection[0]
			ctx["mode"] = "node"
			ctx["node"] = node
			ctx["node_class"] = node.get_class()
			ctx["node_name"] = node.name
			ctx["node_path"] = str(node.get_path())
			var scr = node.get_script()
			if scr and scr is Script and not scr.resource_path.is_empty():
				ctx["script_path"] = scr.resource_path
				ctx["script_code"] = _read_file_text(scr.resource_path)
			else:
				ctx["script_path"] = ""
				ctx["script_code"] = ""
			return ctx
		var se = ei.get_script_editor()
		if se:
			var cs = se.get_current_script()
			if cs and cs is Script and not cs.resource_path.is_empty():
				ctx["mode"] = "script"
				ctx["node"] = null
				ctx["node_class"] = ""
				ctx["node_name"] = ""
				ctx["node_path"] = ""
				ctx["script_path"] = cs.resource_path
				ctx["script_code"] = _read_file_text(cs.resource_path)
				return ctx
	ctx["mode"] = "none"
	ctx["node"] = null
	ctx["node_class"] = ""
	ctx["node_name"] = ""
	ctx["node_path"] = ""
	ctx["script_path"] = ""
	ctx["script_code"] = ""
	return ctx

func _update_agent_card() -> void:
	var ctx = _get_context()
	match ctx["mode"]:
		"node":
			agent_node_label.text = "[%s] \"%s\"" % [ctx["node_class"], ctx["node_name"]]
			agent_node_label.modulate = Color(0.3, 1.0, 0.5)
			if not ctx["script_path"].is_empty():
				agent_script_label.text = "Script: " + ctx["script_path"]
				agent_script_label.modulate = Color(0.5, 0.9, 1.0)
			else:
				agent_script_label.text = "Script: (Sin script - se creara res://%s.gd)" % ctx["node_name"].to_snake_case()
				agent_script_label.modulate = Color(1.0, 0.7, 0.3)
		"script":
			agent_node_label.text = "Editor de Script"
			agent_node_label.modulate = Color(0.5, 0.8, 1.0)
			agent_script_label.text = "Script: " + ctx["script_path"]
			agent_script_label.modulate = Color(0.5, 0.9, 1.0)
		_:
			agent_node_label.text = "(Ningun nodo o script seleccionado)"
			agent_node_label.modulate = Color(0.7, 0.7, 0.7)
			agent_script_label.text = "Script: (Ninguno)"
			agent_script_label.modulate = Color(0.7, 0.7, 0.7)

# ---------------------------------------------------------------------------
# SYSTEM PROMPT
# ---------------------------------------------------------------------------

func _build_scene_tree_ascii(node: Node, selected_node, indent: String = "") -> String:
	var line = indent + "- " + node.name + " [" + node.get_class() + "]"
	var scr = node.get_script()
	if scr and scr is Script:
		line += " (script: " + scr.resource_path + ")"
	if node == selected_node:
		line += "  <=== NODO SELECCIONADO"
	line += "\n"
	for child in node.get_children():
		line += _build_scene_tree_ascii(child, selected_node, indent + "  ")
	return line

func _build_agent_system_prompt(ctx: Dictionary) -> String:
	var ei = plugin_ref.get_editor_interface() if plugin_ref else null
	var prompt = ""
	prompt += "Eres Shiro AI, un AGENTE AUTONOMO de desarrollo de videojuegos integrado en Godot 4.\n"
	prompt += "Actuas como un desarrollador experto: creas escenas, scripts, efectos VFX, materiales, sistemas de particulas, mecanicas de juego completas y prototipos jugables.\n"
	prompt += "REGLA DE ORO: NO eres un chatbot teorico. Cuando se te pida crear o modificar algo, ESCRIBES EL CODIGO COMPLETO DE TODOS LOS ARCHIVOS DIRECTAMENTE. No des instrucciones paso a paso ni pidas confirmacion.\n\n"

	prompt += "=== ESTADO ACTUAL DEL EDITOR ===\n"
	match ctx["mode"]:
		"node":
			var n_class: String = ctx["node_class"]
			var n_name: String = ctx["node_name"]
			var n_path: String = ctx["node_path"]
			var sp: String = ctx["script_path"]
			var code: String = ctx["script_code"]
			prompt += "NODO SELECCIONADO: [" + n_class + "] \"" + n_name + "\", ruta: " + n_path + "\n"
			if not sp.is_empty():
				prompt += "Script: " + sp + "\n"
				prompt += "\n[CODIGO ACTUAL]\n```gdscript\n" + code + "\n```\n"
			else:
				prompt += "Script: NINGUNO. Si creas uno, usa extends " + n_class + " y guardalo en res://" + n_name.to_snake_case() + ".gd\n"
			prompt += "REGLA: extends SIEMPRE debe ser " + n_class + " (nunca otra clase incorrecta).\n"
			if ei:
				var scene_root = ei.get_edited_scene_root()
				if scene_root:
					prompt += "\n[JERARQUIA DE ESCENA - " + scene_root.name + "]\n"
					prompt += _build_scene_tree_ascii(scene_root, ctx["node"])
		"script":
			var sp: String = ctx["script_path"]
			prompt += "SCRIPT ACTIVO: " + sp + "\n"
			prompt += "\n[CODIGO ACTUAL]\n```gdscript\n" + ctx["script_code"] + "\n```\n"
		_:
			prompt += "Sin seleccion activa. Puedes crear escenas o scripts nuevos.\n"
			if ei:
				var scene_root = ei.get_edited_scene_root()
				if scene_root:
					prompt += "\n[ESCENA ABIERTA: " + scene_root.name + "]\n"
					prompt += _build_scene_tree_ascii(scene_root, null)

	if not attached_scripts.is_empty():
		prompt += "\n[SCRIPTS ADICIONALES ADJUNTOS]\n"
		for p in attached_scripts:
			prompt += "--- " + p + " ---\n```gdscript\n" + _read_file_text(p) + "\n```\n\n"

	prompt += """
=== FORMATO PARA CREAR O EDITAR ARCHIVOS ===
Escribe el codigo completo dentro de un bloque indicando la ruta del archivo:
```write_file:res://ruta/archivo.gd
extends CharacterBody2D
# Codigo GDScript completo...
```

=== ACCIONES DISPONIBLES EN EL EDITOR DE GODOT ===
Puedes ejecutar acciones en el proyecto usando bloques action:

1. ANADIR NODO HIJO al nodo seleccionado en la escena actual:
```action:add_child
{"type": "CollisionShape2D", "name": "Collision", "properties": {}}
```

2. CREAR ESCENA NUEVA (.tscn empaquetada nativamente por Godot):
```action:create_scene
{"path": "res://scenes/player.tscn", "root_type": "CharacterBody3D", "root_name": "Player", "script": "res://scripts/player.gd", "children": [{"type": "MeshInstance3D", "name": "Mesh", "properties": {"mesh": "CapsuleMesh"}}, {"type": "CollisionShape3D", "name": "Collision", "properties": {"shape": "CapsuleShape3D"}}]}
```

3. INSTANCIAR ESCENA bajo el nodo seleccionado:
```action:instance_scene
{"scene_path": "res://scenes/enemigo.tscn", "name": "Enemigo"}
```

4. CAMBIAR PROPIEDAD de un nodo en la escena abierta:
```action:set_property
{"node_path": "Player/Sprite2D", "property": "modulate", "value": [1.0, 0.5, 0.5, 1.0]}
```

5. GUARDAR LA ESCENA ACTUAL:
```action:save_scene
{}
```

6. ABRIR O EJECUTAR ESCENA:
```action:open_scene
{"path": "res://scenes/nivel.tscn"}
```
```action:run_scene
{"path": "res://scenes/nivel.tscn"}
```

=== REGLAS DE DESARROLLO EN GODOT 4 ===
- Eres un asistente GENERAL para cualquier tipo de juego, mecanica o herramienta: plataformas, RPG, top-down, 3D, UI, shaders, fisica, particulas, etc.
- Usa SIEMPRE APIs reales y validas de Godot 4:
  - 2D: CharacterBody2D (con velocity y move_and_slide()), StaticBody2D, RigidBody2D, Area2D, Sprite2D, AnimatedSprite2D, CollisionShape2D, Camera2D, etc.
  - 3D: CharacterBody3D, Camera3D, MeshInstance3D, CollisionShape3D, etc.
  - UI: Control, Button, Label, MarginContainer, Panel, etc.
  - Particulas: GPUParticles2D / GPUParticles3D con ParticleProcessMaterial.
  - Dibujo procedural en CanvasItem: usa _draw() con draw_circle(), draw_rect(), draw_colored_polygon(), draw_line().
- CREACION DE ESCENAS Y SCRIPTS: Cuando se te pida crear una entidad, personaje, bala o mecanica (ej. 'crea un jugador', 'crea un proyectil'), NO crees solo el script. Crea SIEMPRE tanto la escena completa (.tscn) con 'action:create_scene' con todos sus nodos hijos necesarios (MeshInstance3D, CollisionShape3D, etc.) como su script (.gd) con 'write_file'. Luego abre la escena con 'action:open_scene'.
- MODELOS 3D Y ASSETS (MUY IMPORTANTE): Eres un modelo de texto y NO puedes generar archivos binarios 3D (.glb, .gltf, .obj) ni texturas (.png, .jpg). NUNCA inventes archivos .glb ni pidas al usuario poner contenido binario. Para 3D, usa SIEMPRE mallas primitivas de Godot (BoxMesh, SphereMesh, CapsuleMesh, CylinderMesh) asignadas al 'mesh' de un MeshInstance3D, con StandardMaterial3D y CollisionShape3D con sus respectivas formas (BoxShape3D, SphereShape3D, CapsuleShape3D), o crealas en GDScript.
- ESCENAS Y ACCIONES: Solo puedes ejecutar 'set_property' o 'add_child' si hay una escena abierta en el editor. Si no hay escena abierta (ver ESTADO ACTUAL DEL EDITOR), crea la escena completa con 'action:create_scene' y luego abrela con 'action:open_scene'.
- Cuando se te pida crear o modificar algo, genera DIRECTAMENTE el codigo de los archivos necesarios con write_file.
- Escribe SIEMPRE codigo COMPLETO, sin abreviaciones, sin omitir funciones y sin comentarios como '# resto del codigo igual'.
- Explicacion breve despues de los bloques, nunca antes.
"""
	return prompt

# ---------------------------------------------------------------------------
# SEND & HTTP
# ---------------------------------------------------------------------------

func _on_send_pressed() -> void:
	if is_requesting:
		return
	var text = prompt_input.text.strip_edges()
	if text.is_empty():
		return
	prompt_input.clear()
	var ctx = _get_context()
	var node_info = ""
	if ctx["mode"] == "node":
		node_info = "[%s] \"%s\"" % [ctx["node_class"], ctx["node_name"]]
	elif ctx["mode"] == "script":
		node_info = ctx["script_path"].get_file()
	chat_display.append_text("[b][color=#5cb3ff]Tu:[/color][/b] " + text + "\n")
	if not node_info.is_empty():
		chat_display.append_text("[color=#88bbff][size=12]Contexto: " + node_info + "[/size][/color]\n\n")
	else:
		chat_display.append_text("\n")
	var system_content = _build_agent_system_prompt(ctx)
	var selected_model = model_dropdown.get_item_text(model_dropdown.selected)
	if selected_model.is_empty() or selected_model.begins_with("("):
		chat_display.append_text("[color=red][b]Error:[/b] No hay ningun modelo seleccionado.[/color]\n\n")
		return
	messages.append({"role": "user", "content": text})
	match current_provider:
		Provider.OLLAMA:
			_send_ollama_request(system_content, selected_model)
		Provider.CLAUDE:
			_send_claude_request(system_content, selected_model)
		Provider.OPENAI:
			_send_openai_request(system_content, selected_model)

func _send_ollama_request(system_content: String, model_name: String) -> void:
	var prompt_messages: Array = []
	prompt_messages.append({"role": "system", "content": system_content})
	var start_idx = 0
	if messages.size() > 6:
		start_idx = messages.size() - 6
	for i in range(start_idx, messages.size()):
		prompt_messages.append(messages[i])
	var body_dict = {
		"model": model_name,
		"messages": prompt_messages,
		"stream": false,
		"options": {
			"num_ctx": 8192,
			"num_predict": 4096
		}
	}
	_dispatch_http(OLLAMA_HOST + "/api/chat", PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST, JSON.stringify(body_dict), "Ollama", model_name)

func _send_claude_request(system_content: String, model_name: String) -> void:
	var api_key = key_input.text.strip_edges()
	if api_key.is_empty():
		chat_display.append_text("[color=red][b]Error:[/b] Ingresa tu API Key de Claude.[/color]\n\n")
		return
	var anthropic_messages: Array = []
	for m in messages:
		anthropic_messages.append({"role": m.get("role", "user"), "content": m.get("content", "")})
	var body_dict = {"model": model_name, "max_tokens": 8096, "system": system_content, "messages": anthropic_messages}
	_dispatch_http(CLAUDE_ENDPOINT, PackedStringArray(["Content-Type: application/json", "x-api-key: " + api_key, "anthropic-version: 2023-06-01"]), HTTPClient.METHOD_POST, JSON.stringify(body_dict), "Claude", model_name)

func _send_openai_request(system_content: String, model_name: String) -> void:
	var api_key = key_input.text.strip_edges()
	if api_key.is_empty():
		chat_display.append_text("[color=red][b]Error:[/b] Ingresa tu API Key de OpenAI.[/color]\n\n")
		return
	var prompt_messages: Array = []
	prompt_messages.append({"role": "system", "content": system_content})
	for m in messages:
		prompt_messages.append(m)
	var body_dict = {"model": model_name, "messages": prompt_messages}
	_dispatch_http(OPENAI_ENDPOINT, PackedStringArray(["Content-Type: application/json", "Authorization: Bearer " + api_key]), HTTPClient.METHOD_POST, JSON.stringify(body_dict), "OpenAI", model_name)

func _dispatch_http(url: String, headers: PackedStringArray, method: int, json_body: String, provider_name: String, model_name: String) -> void:
	is_requesting = true
	send_btn.disabled = true
	send_btn.text = "..."
	chat_display.append_text("[b][color=#a37acc]Shiro AI (" + provider_name + " / " + model_name + "):[/color][/b] [i]Pensando...[/i]\n")
	var err = http_request.request(url, headers, method, json_body)
	if err != OK:
		_finish_request_with_error("No se pudo iniciar la solicitud HTTP: " + str(err))

func _on_chat_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	is_requesting = false
	send_btn.disabled = false
	send_btn.text = "Enviar"
	var raw_str = body.get_string_from_utf8()
	if response_code != 200:
		_finish_request_with_error("Error del servidor (HTTP %d):\n%s" % [response_code, raw_str])
		return
	var json = JSON.new()
	if json.parse(raw_str) != OK:
		_finish_request_with_error("Respuesta JSON no valida: " + json.get_error_message())
		return
	var data = json.data
	var assistant_content: String = ""
	match current_provider:
		Provider.OLLAMA:
			var msg_dict = data.get("message", {})
			assistant_content = msg_dict.get("content", "")
			if assistant_content.is_empty():
				assistant_content = msg_dict.get("thinking", "")
			if assistant_content.is_empty():
				assistant_content = data.get("response", "")
			if assistant_content.is_empty():
				var dr = data.get("done_reason", "")
				if dr == "length":
					assistant_content = "(El modelo excedió el límite de tokens/contexto. Haz clic en 'Limpiar chat' y vuelve a intentar)."
				else:
					assistant_content = "(Respuesta vacía del modelo en Ollama)"
		Provider.CLAUDE:
			for item in data.get("content", []):
				if item.get("type", "") == "text":
					assistant_content += item.get("text", "")
		Provider.OPENAI:
			var choices = data.get("choices", [])
			if not choices.is_empty():
				assistant_content = choices[0].get("message", {}).get("content", "")
	if assistant_content.is_empty():
		assistant_content = "(Respuesta vacia del modelo)"
	messages.append({"role": "assistant", "content": assistant_content})
	_process_agent_response(assistant_content)

# ---------------------------------------------------------------------------
# AGENT RESPONSE PROCESSING
# ---------------------------------------------------------------------------

func _normalize_res_path(path: String) -> String:
	var p = path.strip_edges()
	p = p.replace("\\", "/")
	p = p.trim_prefix("\"").trim_suffix("\"").trim_prefix("'").trim_suffix("'")
	p = p.trim_prefix(":")
	if not p.begins_with("res://") and not p.begins_with("user://"):
		p = "res://" + p.trim_prefix("/")
	return p

func _resolve_target_path(header: String, code: String, ctx: Dictionary, block_idx: int, used_paths: Array[String]) -> String:
	var clean_h = header.strip_edges()

	for prefix in ["write_file:", "file:", "path:", "target:"]:
		if clean_h.begins_with(prefix):
			var p = clean_h.substr(prefix.length()).strip_edges()
			if not p.is_empty():
				return _normalize_res_path(p)

	for lang in ["gdscript:", "gd:", "text:"]:
		if clean_h.begins_with(lang):
			clean_h = clean_h.substr(lang.length()).strip_edges()
			break

	var tokens = clean_h.split(" ", false)
	for tok in tokens:
		tok = tok.strip_edges()
		if tok.ends_with(".gd") or tok.ends_with(".tscn") or tok.ends_with(".json") or tok.ends_with(".tres"):
			return _normalize_res_path(tok)

	if clean_h.ends_with(".gd") or clean_h.ends_with(".tscn") or clean_h.ends_with(".json") or clean_h.ends_with(".tres"):
		return _normalize_res_path(clean_h)

	var lines = code.split("\n")
	var check_lines = mini(lines.size(), 6)
	for i in range(check_lines):
		var line = lines[i].strip_edges()
		if line.begins_with("#") or line.begins_with("//") or line.begins_with(";") or line.begins_with("--"):
			var comment_content = line.substr(1).strip_edges().trim_prefix("/").strip_edges()
			for lead in ["file:", "File:", "script:", "Script:", "archivo:", "res://"]:
				if comment_content.begins_with(lead):
					comment_content = comment_content.substr(lead.length()).strip_edges()
					if lead == "res://":
						comment_content = "res://" + comment_content
			var words = comment_content.split(" ", false)
			for w in words:
				w = w.strip_edges()
				if w.ends_with(".gd") or w.ends_with(".tscn") or w.ends_with(".json") or w.ends_with(".tres"):
					return _normalize_res_path(w)

	var class_regex = RegEx.new()
	if class_regex.compile("class_name\\s+([A-Za-z0-9_]+)") == OK:
		var match_res = class_regex.search(code)
		if match_res:
			var cname = match_res.get_string(1).to_snake_case()
			var cand = _normalize_res_path(cname + ".gd")
			if not used_paths.has(cand):
				return cand

	if block_idx == 0:
		match ctx["mode"]:
			"node":
				var sp = ctx["script_path"]
				if not sp.is_empty():
					return sp
				return "res://" + ctx["node_name"].to_snake_case() + ".gd"
			"script":
				return ctx["script_path"]
			_:
				if not attached_scripts.is_empty():
					return attached_scripts[0]
				return "res://script.gd"
	else:
		var fallback = "res://script_%d.gd" % (block_idx + 1)
		var counter = block_idx + 1
		while used_paths.has(fallback):
			counter += 1
			fallback = "res://script_%d.gd" % counter
		return fallback

func _extract_code_blocks(content: String) -> Array:
	var blocks: Array = []
	var start_pos = 0
	while true:
		var open_idx = content.find("```", start_pos)
		if open_idx == -1:
			break
		var end_idx = content.find("```", open_idx + 3)
		if end_idx == -1:
			break
		var inside = content.substr(open_idx + 3, end_idx - (open_idx + 3))
		var first_newline = inside.find("\n")
		var header = ""
		var body = inside
		if first_newline != -1:
			header = inside.substr(0, first_newline).strip_edges()
			body = inside.substr(first_newline + 1).strip_edges()
		blocks.append({"header": header, "body": body})
		start_pos = end_idx + 3
	return blocks

func _process_agent_response(content: String) -> void:
	var ctx = _get_context()
	var selected_node = ctx.get("node", null)
	var blocks = _extract_code_blocks(content)
	var applied_files: Array[String] = []
	var attached_to_node: Array[String] = []
	var executed_actions: int = 0
	var used_paths: Array[String] = []

	var action_items: Array = []
	var file_items: Array = []

	var block_idx = 0
	for b in blocks:
		var header: String = b.get("header", "")
		var code: String = b.get("body", "")
		if code.is_empty():
			continue

		var action_type = ""
		if header.begins_with("action:"):
			action_type = header.substr(7).strip_edges()
		elif header == "action" or header == "json" or header.is_empty():
			var test_j = JSON.new()
			if test_j.parse(code) == OK and test_j.data is Dictionary:
				var jd: Dictionary = test_j.data
				if jd.has("action"):
					action_type = str(jd["action"]).strip_edges()
				elif jd.has("node_path") and jd.has("property"):
					action_type = "set_property"
				elif jd.has("root_type") and jd.has("path"):
					action_type = "create_scene"
				elif jd.has("scene_path"):
					action_type = "instance_scene"
				elif jd.has("type") and (jd.has("properties") or ClassDB.class_exists(jd.get("type", ""))):
					action_type = "add_child"

		if not action_type.is_empty():
			action_items.append({"type": action_type, "code": code})
			continue

		var target_path = _resolve_target_path(header, code, ctx, block_idx, used_paths)
		block_idx += 1
		if target_path.is_empty():
			continue
		target_path = _normalize_res_path(target_path)
		used_paths.append(target_path)
		file_items.append({"path": target_path, "code": code})

	# 1. Guardar primero todos los archivos/scripts en disco
	for item in file_items:
		var target_path: String = item["path"]
		var code: String = item["code"]
		if auto_apply_checkbox.button_pressed:
			var ok = _apply_file_content(target_path, code)
			if ok:
				applied_files.append(target_path)
				if auto_attach_checkbox.button_pressed and selected_node and selected_node.get_script() == null and applied_files.size() == 1:
					var scr_res = load(target_path)
					if scr_res and scr_res is Script:
						selected_node.set_script(scr_res)
						attached_to_node.append(target_path)
		else:
			var act_id = str(Time.get_ticks_msec()) + "_" + target_path.get_file()
			if not has_meta("_pending_actions"):
				set_meta("_pending_actions", {})
			var pending: Dictionary = get_meta("_pending_actions")
			pending[act_id] = {"path": target_path, "code": code}
			set_meta("_pending_actions", pending)
			chat_display.append_text("\n[url=apply:" + act_id + "][color=#5cb3ff][b]Guardar manualmente: " + target_path + "[/b][/color][/url]\n")

	# Actualizar sistema de archivos de Godot para que las acciones puedan enlazar los nuevos scripts
	if not applied_files.is_empty() and plugin_ref:
		plugin_ref.get_editor_interface().get_resource_filesystem().scan()

	# 2. Ejecutar luego las acciones (crear escenas, añadir nodos, etc.)
	for item in action_items:
		var action_type: String = item["type"]
		var code: String = item["code"]
		match action_type:
			"add_node", "add_child":
				_execute_add_child_action(code, selected_node)
			"create_scene":
				_execute_create_scene_action(code)
			"set_property":
				_execute_set_property_action(code)
			"save_scene":
				_execute_save_scene_action()
			"instance_scene":
				_execute_instance_scene_action(code, selected_node)
			"open_scene":
				_execute_open_scene_action(code)
			"run_scene":
				_execute_run_scene_action(code)
			"set_main_scene":
				_execute_set_main_scene_action(code)
		executed_actions += 1

	var formatted = _format_bbcode(content)
	chat_display.append_text(formatted + "\n")

	for p in applied_files:
		chat_display.append_text("[color=#55ff88][b]Guardado:[/b] " + p + "[/color]\n")
	for p in attached_to_node:
		var nd = selected_node.name if selected_node else "nodo"
		chat_display.append_text("[color=#33ffff][b]Script adjuntado al nodo \"%s\"[/b][/color]\n" % nd)

	var scene_to_run = ""
	for p in applied_files:
		if p.ends_with(".tscn"):
			scene_to_run = p
			break
	if not scene_to_run.is_empty():
		if plugin_ref:
			plugin_ref.get_editor_interface().open_scene_from_path(scene_to_run)
		chat_display.append_text("[url=run_scene:" + scene_to_run + "][color=#33ffff][b]▶ PROBAR ESCENA (F6 o clic aqui)[/b][/color][/url]\n")

	if applied_files.is_empty() and executed_actions == 0:
		chat_display.append_text("[color=#ffaa44][i]Nota: El modelo no devolvio bloques de codigo o acciones ejecutables.[/i][/color]\n")

	chat_display.append_text("\n")
	_update_agent_card()

func _execute_add_child_action(json_code: String, parent_node: Node) -> void:
	if not parent_node:
		chat_display.append_text("[color=red]No hay nodo seleccionado para anadir hijo.[/color]\n")
		return
	var json = JSON.new()
	if json.parse(json_code) != OK or not json.data is Dictionary:
		chat_display.append_text("[color=red]Error: JSON de accion invalido.[/color]\n")
		return
	var node_type = json.data.get("type", "")
	var node_name_str = json.data.get("name", node_type)
	var properties: Dictionary = json.data.get("properties", {})
	var scr_path: String = json.data.get("script", "")
	if not ClassDB.class_exists(node_type):
		chat_display.append_text("[color=red]Tipo de nodo invalido: " + node_type + "[/color]\n")
		return
	var new_child = ClassDB.instantiate(node_type)
	if not new_child:
		return
	new_child.name = node_name_str
	for prop in properties:
		var val = _json_to_godot_value(properties[prop], new_child, prop)
		if val != null:
			new_child.set(prop, val)
	if not scr_path.is_empty() and FileAccess.file_exists(scr_path):
		var scr = load(scr_path)
		if scr and scr is Script:
			new_child.set_script(scr)
	parent_node.add_child(new_child)
	if plugin_ref:
		var root = plugin_ref.get_editor_interface().get_edited_scene_root()
		if root:
			new_child.owner = root
	chat_display.append_text("[color=#33ffff][b]Nodo [%s] \"%s\" anadido bajo \"%s\".[/b][/color]\n" % [node_type, node_name_str, parent_node.name])

func _execute_create_scene_action(json_code: String) -> void:
	var json = JSON.new()
	if json.parse(json_code) != OK or not json.data is Dictionary:
		chat_display.append_text("[color=red]Error: JSON de create_scene invalido.[/color]\n")
		return
	var data: Dictionary = json.data
	var scene_path: String = data.get("path", "")
	var root_type: String = data.get("root_type", "Node2D")
	var root_name_str: String = data.get("root_name", "Scene")
	var root_script: String = data.get("script", "")
	var children: Array = data.get("children", [])
	if scene_path.is_empty():
		chat_display.append_text("[color=red]Error: create_scene requiere campo 'path'.[/color]\n")
		return
	scene_path = _normalize_res_path(scene_path)
	var root_node: Node = null
	if ClassDB.class_exists(root_type):
		root_node = ClassDB.instantiate(root_type)
	if not root_node:
		root_node = Node2D.new()
	root_node.name = root_name_str
	if not root_script.is_empty() and FileAccess.file_exists(root_script):
		var scr = load(root_script)
		if scr and scr is Script:
			root_node.set_script(scr)
	for child_data in children:
		var c_type: String = child_data.get("type", "Node")
		var c_name: String = child_data.get("name", c_type)
		var c_props: Dictionary = child_data.get("properties", {})
		var c_script: String = child_data.get("script", "")
		if ClassDB.class_exists(c_type):
			var c_node = ClassDB.instantiate(c_type)
			if c_node:
				c_node.name = c_name
				for prop in c_props:
					var val = _json_to_godot_value(c_props[prop], c_node, prop)
					if val != null:
						c_node.set(prop, val)
				if not c_script.is_empty() and FileAccess.file_exists(c_script):
					var c_scr = load(c_script)
					if c_scr and c_scr is Script:
						c_node.set_script(c_scr)
				root_node.add_child(c_node)
				c_node.owner = root_node
	var packed = PackedScene.new()
	if packed.pack(root_node) == OK:
		var base_dir = scene_path.get_base_dir()
		if not DirAccess.dir_exists_absolute(base_dir):
			DirAccess.make_dir_recursive_absolute(base_dir)
		var err = ResourceSaver.save(packed, scene_path)
		if err == OK:
			chat_display.append_text("[color=#55ff88][b]Escena creada:[/b] " + scene_path + "[/color]\n")
			if plugin_ref:
				var ei = plugin_ref.get_editor_interface()
				ei.get_resource_filesystem().scan()
				ei.open_scene_from_path(scene_path)
				chat_display.append_text("[url=run_scene:" + scene_path + "][color=#33ffff][b]▶ PROBAR JUEGO (F6 o clic aqui)[/b][/color][/url]\n")
		else:
			chat_display.append_text("[color=red]Error al guardar escena: " + str(err) + "[/color]\n")
	root_node.queue_free()

func _execute_open_scene_action(json_code: String) -> void:
	var json = JSON.new()
	var scene_path = "res://main.tscn"
	if json.parse(json_code) == OK and json.data is Dictionary:
		scene_path = json.data.get("path", scene_path)
	scene_path = _normalize_res_path(scene_path)
	if not FileAccess.file_exists(scene_path):
		chat_display.append_text("[color=red]No se puede abrir escena (archivo no encontrado): " + scene_path + "[/color]\n")
		return
	if plugin_ref:
		var ei = plugin_ref.get_editor_interface()
		ei.open_scene_from_path(scene_path)
		chat_display.append_text("[color=#33ffff][b]Escena abierta en el editor: " + scene_path + "[/b][/color]\n")

func _execute_run_scene_action(json_code: String) -> void:
	var json = JSON.new()
	var scene_path = "res://main.tscn"
	if json.parse(json_code) == OK and json.data is Dictionary:
		scene_path = json.data.get("path", scene_path)
	scene_path = _normalize_res_path(scene_path)
	if plugin_ref:
		var ei = plugin_ref.get_editor_interface()
		ei.play_custom_scene(scene_path)
		chat_display.append_text("[color=#55ff88][b]▶ Ejecutando escena: " + scene_path + "[/b][/color]\n")

func _execute_set_main_scene_action(json_code: String) -> void:
	var json = JSON.new()
	var scene_path = "res://main.tscn"
	if json.parse(json_code) == OK and json.data is Dictionary:
		scene_path = json.data.get("path", scene_path)
	scene_path = _normalize_res_path(scene_path)
	ProjectSettings.set_setting("application/run/main_scene", scene_path)
	ProjectSettings.save()
	chat_display.append_text("[color=#55ff88][b]Escena principal fijada en ProjectSettings: " + scene_path + "[/b][/color]\n")

func _execute_set_property_action(json_code: String) -> void:
	var json = JSON.new()
	if json.parse(json_code) != OK or not json.data is Dictionary:
		chat_display.append_text("[color=red]Error: JSON de set_property invalido.[/color]\n")
		return
	var node_path_str: String = json.data.get("node_path", "")
	var prop: String = json.data.get("property", "")
	var val_raw = json.data.get("value", null)
	if node_path_str.is_empty() or prop.is_empty():
		chat_display.append_text("[color=red]set_property requiere 'node_path' y 'property'.[/color]\n")
		return
	if not plugin_ref:
		return
	var scene_root = plugin_ref.get_editor_interface().get_edited_scene_root()
	if not scene_root:
		chat_display.append_text("[color=red]No hay escena abierta.[/color]\n")
		return
	var target_node = scene_root.get_node_or_null(node_path_str)
	if not target_node:
		chat_display.append_text("[color=red]Nodo no encontrado: " + node_path_str + "[/color]\n")
		return
	var val = _json_to_godot_value(val_raw, target_node, prop)
	target_node.set(prop, val)
	chat_display.append_text("[color=#33ffff][b]Propiedad '" + prop + "' = " + str(val) + " en " + node_path_str + "[/b][/color]\n")

func _execute_save_scene_action() -> void:
	if not plugin_ref:
		return
	var scene_root = plugin_ref.get_editor_interface().get_edited_scene_root()
	if not scene_root:
		chat_display.append_text("[color=#ffaa44]Aviso: No se pudo guardar la escena porque no hay ninguna escena abierta en el editor.[/color]\n")
		return
	var err = plugin_ref.get_editor_interface().save_scene()
	if err == OK:
		chat_display.append_text("[color=#55ff88][b]Escena guardada.[/b][/color]\n")
	else:
		chat_display.append_text("[color=red]Error al guardar escena: " + str(err) + "[/color]\n")

func _execute_instance_scene_action(json_code: String, parent_node: Node) -> void:
	if not parent_node:
		chat_display.append_text("[color=red]No hay nodo seleccionado como padre.[/color]\n")
		return
	var json = JSON.new()
	if json.parse(json_code) != OK or not json.data is Dictionary:
		chat_display.append_text("[color=red]Error: JSON de instance_scene invalido.[/color]\n")
		return
	var scene_path: String = json.data.get("scene_path", "")
	var inst_name: String = json.data.get("name", "")
	if not FileAccess.file_exists(scene_path):
		chat_display.append_text("[color=red]Escena no encontrada: " + scene_path + "[/color]\n")
		return
	var packed = load(scene_path)
	if not packed is PackedScene:
		chat_display.append_text("[color=red]No es una PackedScene: " + scene_path + "[/color]\n")
		return
	var inst = packed.instantiate()
	if not inst_name.is_empty():
		inst.name = inst_name
	parent_node.add_child(inst)
	if plugin_ref:
		var root = plugin_ref.get_editor_interface().get_edited_scene_root()
		if root:
			inst.owner = root
	chat_display.append_text("[color=#33ffff][b]Escena instanciada: " + scene_path + " bajo \"" + parent_node.name + "\"[/b][/color]\n")

func _json_to_godot_value(val, node: Node, prop: String) -> Variant:
	if val == null:
		return null
	if val is bool or val is int or val is float:
		return val
	if val is String:
		var s: String = val
		if s.begins_with("res://") and (ResourceLoader.exists(s) or FileAccess.file_exists(s)):
			return load(s)
		if ClassDB.class_exists(s) and ClassDB.is_parent_class(s, "Resource"):
			return ClassDB.instantiate(s)
		return s
	if val is Array:
		match val.size():
			2:
				return Vector2(val[0], val[1])
			3:
				var pi = node.get_property_list().filter(func(p): return p.name == prop)
				if not pi.is_empty() and pi[0].type == TYPE_COLOR:
					return Color(val[0], val[1], val[2])
				return Vector3(val[0], val[1], val[2])
			4:
				var pi = node.get_property_list().filter(func(p): return p.name == prop)
				if not pi.is_empty() and pi[0].type == TYPE_VECTOR4:
					return Vector4(val[0], val[1], val[2], val[3])
				return Color(val[0], val[1], val[2], val[3])
	return val

func _apply_file_content(file_path: String, content: String) -> bool:
	if file_path.is_empty() or content.is_empty():
		return false
	file_path = _normalize_res_path(file_path)
	var ext = file_path.get_extension().to_lower()
	if ext in ["glb", "gltf", "png", "jpg", "jpeg", "webp", "wav", "ogg", "mp3"]:
		chat_display.append_text("[color=#ffaa44]Aviso: No se puede guardar '" + file_path + "' porque es un formato binario y la IA genera texto.[/color]\n")
		return false
	var base_dir = file_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(base_dir):
		DirAccess.make_dir_recursive_absolute(base_dir)
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if not file:
		chat_display.append_text("[color=red][b]Error al escribir " + file_path + ":[/b] " + str(FileAccess.get_open_error()) + "[/color]\n")
		return false
	file.store_string(content)
	file.close()
	if plugin_ref:
		var ei = plugin_ref.get_editor_interface()
		ei.get_resource_filesystem().update_file(file_path)
		_reload_file_deferred.call_deferred(file_path)
	print("[Shiro AI Assistant] Archivo escrito: ", file_path)
	return true

func _reload_file_deferred(file_path: String) -> void:
	if not plugin_ref:
		return
	var ei = plugin_ref.get_editor_interface()
	ei.get_resource_filesystem().scan()
	if file_path.ends_with(".gd"):
		var res = load(file_path)
		if res and res is Script:
			ei.edit_script(res)

func _on_chat_meta_clicked(meta: Variant) -> void:
	var meta_str = str(meta)
	if meta_str.begins_with("copy:"):
		var cid = meta_str.substr(5)
		if copy_buffers.has(cid):
			DisplayServer.clipboard_set(copy_buffers[cid])
			chat_display.append_text("[color=#aaaaaa][i]Codigo copiado al portapapeles.[/i][/color]\n")
	elif meta_str.begins_with("apply:"):
		var act_id = meta_str.substr(6)
		if has_meta("_pending_actions"):
			var pending: Dictionary = get_meta("_pending_actions")
			if pending.has(act_id):
				var act = pending[act_id]
				var ok = _apply_file_content(act.path, act.code)
				if ok:
					chat_display.append_text("[color=#55ff88][b]Aplicado:[/b] " + act.path + "[/color]\n")
				pending.erase(act_id)
				set_meta("_pending_actions", pending)
	elif meta_str.begins_with("run_scene:"):
		var sp = meta_str.substr("run_scene:".length())
		if plugin_ref:
			plugin_ref.get_editor_interface().play_custom_scene(sp)
	elif meta_str.begins_with("open_scene:"):
		var sp = meta_str.substr("open_scene:".length())
		if plugin_ref:
			plugin_ref.get_editor_interface().open_scene_from_path(sp)

func _finish_request_with_error(err_msg: String) -> void:
	is_requesting = false
	send_btn.disabled = false
	send_btn.text = "Enviar"
	chat_display.append_text("[color=#ff6b6b][b]Error:[/b] " + err_msg + "[/color]\n\n")

func _format_bbcode(raw_text: String) -> String:
	var result = ""
	var start_pos = 0
	while true:
		var open_idx = raw_text.find("```", start_pos)
		if open_idx == -1:
			result += raw_text.substr(start_pos)
			break
		result += raw_text.substr(start_pos, open_idx - start_pos)
		var end_idx = raw_text.find("```", open_idx + 3)
		if end_idx == -1:
			result += raw_text.substr(open_idx)
			break
		var inside = raw_text.substr(open_idx + 3, end_idx - (open_idx + 3))
		var first_newline = inside.find("\n")
		var lang = ""
		var body = inside
		if first_newline != -1:
			lang = inside.substr(0, first_newline).strip_edges()
			body = inside.substr(first_newline + 1).strip_edges()
		# Store body in copy_buffers so user can click to copy
		copy_counter += 1
		var cid = str(copy_counter)
		copy_buffers[cid] = body
		var label = ""
		if lang.begins_with("write_file:"):
			label = "[color=#55ff88][b]Archivo: " + lang.substr("write_file:".length()).strip_edges() + "[/b][/color]  "
			label += "[url=copy:" + cid + "][color=#aaaaaa][b][Copiar][/b][/color][/url]\n"
		elif not lang.is_empty() and not lang.begins_with("action:"):
			label = "[color=#888888][i]" + lang + "[/i][/color]  "
			label += "[url=copy:" + cid + "][color=#aaaaaa][b][Copiar][/b][/color][/url]\n"
		else:
			label = "[url=copy:" + cid + "][color=#aaaaaa][b][Copiar][/b][/color][/url]\n"
		result += label + "[code][color=#c3e88d]" + body.xml_escape() + "[/color][/code]"
		start_pos = end_idx + 3
	return result

func _read_file_text(path: String) -> String:
	if path.is_empty():
		return ""
	if plugin_ref:
		var se = plugin_ref.get_editor_interface().get_script_editor()
		if se:
			for scr in se.get_open_scripts():
				if scr and scr.resource_path == path:
					return scr.source_code
	if FileAccess.file_exists(path):
		var f = FileAccess.open(path, FileAccess.READ)
		if f:
			var txt = f.get_as_text()
			f.close()
			return txt
	return ""

# ---------------------------------------------------------------------------
# SCRIPTS ATTACHMENT
# ---------------------------------------------------------------------------

func _on_attach_open_pressed() -> void:
	if plugin_ref:
		var se = plugin_ref.get_editor_interface().get_script_editor()
		if se:
			for scr in se.get_open_scripts():
				if scr and not scr.resource_path.is_empty():
					var p = scr.resource_path
					if not attached_scripts.has(p):
						attached_scripts.append(p)
	_update_chips_ui()

func _on_files_selected(paths: PackedStringArray) -> void:
	for p in paths:
		if not attached_scripts.has(p):
			attached_scripts.append(p)
	_update_chips_ui()

func _update_chips_ui() -> void:
	for child in chips_container.get_children():
		child.queue_free()
	for path in attached_scripts:
		var chip_btn = Button.new()
		chip_btn.text = path.get_file() + " [x]"
		chip_btn.tooltip_text = path + " (Clic para quitar)"
		var target_path = path
		chip_btn.pressed.connect(func():
			attached_scripts.erase(target_path)
			_update_chips_ui()
		)
		chips_container.add_child(chip_btn)

# ---------------------------------------------------------------------------
# PROVIDER & MODEL
# ---------------------------------------------------------------------------

func _on_provider_selected(idx: int) -> void:
	current_provider = idx
	_update_provider_ui()
	_save_config()

func _update_provider_ui() -> void:
	model_dropdown.clear()
	match current_provider:
		Provider.OLLAMA:
			key_container.visible = false
			refresh_btn.visible = true
			_refresh_ollama_models()
		Provider.CLAUDE:
			key_container.visible = true
			key_label.text = "Claude Key:"
			key_input.placeholder_text = "sk-ant-api03-..."
			refresh_btn.visible = false
			for m in CLAUDE_MODELS:
				model_dropdown.add_item(m)
			status_label.text = "Claude"
			status_label.modulate = Color(0.2, 0.9, 0.3)
		Provider.OPENAI:
			key_container.visible = true
			key_label.text = "OpenAI Key:"
			key_input.placeholder_text = "sk-..."
			refresh_btn.visible = false
			for m in OPENAI_MODELS:
				model_dropdown.add_item(m)
			status_label.text = "OpenAI"
			status_label.modulate = Color(0.2, 0.9, 0.3)

func _refresh_ollama_models() -> void:
	if not tags_request:
		return
	status_label.text = "Conectando..."
	status_label.modulate = Color(0.9, 0.8, 0.2)
	var err = tags_request.request(OLLAMA_HOST + "/api/tags")
	if err != OK:
		_set_status_disconnected("Error al conectar con Ollama")

func _on_refresh_pressed() -> void:
	if current_provider == Provider.OLLAMA:
		_refresh_ollama_models()
	_update_agent_card()

func _on_tags_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if response_code != 200:
		_set_status_disconnected("Ollama no responde (HTTP %d)" % response_code)
		return
	var json = JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		_set_status_disconnected("Respuesta JSON invalida")
		return
	var models: Array = json.data.get("models", [])
	model_dropdown.clear()
	if models.is_empty():
		model_dropdown.add_item("(Sin modelos instalados)")
		_set_status_disconnected("Sin modelos instalados")
		return

	var saved_model = ""
	if FileAccess.file_exists(CONFIG_FILE_PATH):
		var f = FileAccess.open(CONFIG_FILE_PATH, FileAccess.READ)
		if f:
			var j2 = JSON.new()
			if j2.parse(f.get_as_text()) == OK and j2.data is Dictionary:
				saved_model = j2.data.get("model_name", "")
			f.close()

	var restore_idx = 0
	for i in range(models.size()):
		var m_name = models[i].get("name", "")
		model_dropdown.add_item(m_name)
		if m_name == saved_model:
			restore_idx = i
	model_dropdown.select(restore_idx)
	status_label.text = "Ollama (%d modelos)" % models.size()
	status_label.modulate = Color(0.2, 0.9, 0.3)

func _set_status_disconnected(reason: String = "") -> void:
	status_label.text = "Desconectado"
	status_label.modulate = Color(1.0, 0.3, 0.3)
	if not reason.is_empty():
		status_label.tooltip_text = reason

# ---------------------------------------------------------------------------
# INPUT
# ---------------------------------------------------------------------------

func _on_input_gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER) and not event.shift_pressed:
			get_viewport().set_input_as_handled()
			_on_send_pressed()

func _on_clear_pressed() -> void:
	messages.clear()
	copy_buffers.clear()
	copy_counter = 0
	if has_meta("_pending_actions"):
		set_meta("_pending_actions", {})
	chat_display.clear()
	chat_display.append_text("[color=#888888][i]Chat limpiado.[/i][/color]\n\n")

# ---------------------------------------------------------------------------
# CONFIG PERSISTENCE
# ---------------------------------------------------------------------------

func _save_config() -> void:
	var model_name = model_dropdown.get_item_text(model_dropdown.selected) if model_dropdown.item_count > 0 else ""
	var cfg = {
		"provider": provider_dropdown.selected,
		"key": key_input.text,
		"model_name": model_name,
		"auto_apply": auto_apply_checkbox.button_pressed,
		"auto_attach": auto_attach_checkbox.button_pressed
	}
	var f = FileAccess.open(CONFIG_FILE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(cfg))
		f.close()

func _load_config() -> void:
	if not FileAccess.file_exists(CONFIG_FILE_PATH):
		return
	var f = FileAccess.open(CONFIG_FILE_PATH, FileAccess.READ)
	if not f:
		return
	var text = f.get_as_text()
	f.close()
	var json = JSON.new()
	if json.parse(text) == OK and json.data is Dictionary:
		var cfg: Dictionary = json.data
		var prov = int(cfg.get("provider", 0))
		provider_dropdown.select(prov)
		current_provider = prov
		key_input.text = cfg.get("key", "")
		auto_apply_checkbox.button_pressed = bool(cfg.get("auto_apply", true))
		auto_attach_checkbox.button_pressed = bool(cfg.get("auto_attach", true))
