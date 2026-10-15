@tool
extends Control

var plugin_ref: EditorPlugin = null
var bridge_ref: Node = null

const OLLAMA_HOST: String = "http://127.0.0.1:11434"

var messages: Array = []
var is_requesting: bool = false

# UI Elements
var model_dropdown: OptionButton
var status_label: Label
var refresh_btn: Button
var ctx_checkbox: CheckBox
var clear_btn: Button
var chat_display: RichTextLabel
var prompt_input: TextEdit
var send_btn: Button

# HTTP
var tags_request: HTTPRequest
var chat_request: HTTPRequest

func _init(p_plugin: EditorPlugin = null, p_bridge: Node = null) -> void:
	plugin_ref = p_plugin
	bridge_ref = p_bridge
	name = "Ollama AI"

func _ready() -> void:
	custom_minimum_size = Vector2(280, 200)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	_build_ui()
	_setup_http()
	_refresh_models()

func _build_ui() -> void:
	var main_vbox = VBoxContainer.new()
	main_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_theme_constant_override("separation", 6)
	add_child(main_vbox)

	# --- Header Row 1: Model & Status ---
	var header_hbox = HBoxContainer.new()
	header_hbox.add_theme_constant_override("separation", 6)
	main_vbox.add_child(header_hbox)

	var model_lbl = Label.new()
	model_lbl.text = "Modelo:"
	header_hbox.add_child(model_lbl)

	model_dropdown = OptionButton.new()
	model_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(model_dropdown)

	refresh_btn = Button.new()
	refresh_btn.text = "🔄"
	refresh_btn.tooltip_text = "Refrescar modelos de Ollama"
	refresh_btn.pressed.connect(_on_refresh_pressed)
	header_hbox.add_child(refresh_btn)

	status_label = Label.new()
	status_label.text = "● Desconectado"
	status_label.modulate = Color(1.0, 0.3, 0.3)
	header_hbox.add_child(status_label)

	# --- Header Row 2: Controls ---
	var subheader_hbox = HBoxContainer.new()
	subheader_hbox.add_theme_constant_override("separation", 8)
	main_vbox.add_child(subheader_hbox)

	ctx_checkbox = CheckBox.new()
	ctx_checkbox.text = "Incluir contexto de escena actual"
	ctx_checkbox.button_pressed = true
	ctx_checkbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	subheader_hbox.add_child(ctx_checkbox)

	clear_btn = Button.new()
	clear_btn.text = "Limpiar"
	clear_btn.tooltip_text = "Borrar historial del chat"
	clear_btn.pressed.connect(_on_clear_pressed)
	subheader_hbox.add_child(clear_btn)

	# --- Chat History Area ---
	chat_display = RichTextLabel.new()
	chat_display.bbcode_enabled = true
	chat_display.scroll_following = true
	chat_display.selection_enabled = true
	chat_display.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_display.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chat_display.custom_minimum_size = Vector2(0, 150)
	main_vbox.add_child(chat_display)

	chat_display.append_text("[color=#888888][i]Asistente Ollama listo. Escribe una duda, pide código GDScript o consulta sobre tus nodos abiertos.[/i][/color]\n\n")

	# --- Input Area ---
	var input_hbox = HBoxContainer.new()
	input_hbox.add_theme_constant_override("separation", 6)
	main_vbox.add_child(input_hbox)

	prompt_input = TextEdit.new()
	prompt_input.placeholder_text = "Pregunta algo a Ollama... (Enter o Ctrl+Enter para enviar)"
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

func _setup_http() -> void:
	tags_request = HTTPRequest.new()
	add_child(tags_request)
	tags_request.request_completed.connect(_on_tags_completed)

	chat_request = HTTPRequest.new()
	add_child(chat_request)
	chat_request.request_completed.connect(_on_chat_completed)

func _refresh_models() -> void:
	if not tags_request:
		return
	status_label.text = "● Conectando..."
	status_label.modulate = Color(0.9, 0.8, 0.2)
	var err = tags_request.request(OLLAMA_HOST + "/api/tags")
	if err != OK:
		_set_status_disconnected("Error al iniciar solicitud HTTP")

func _on_refresh_pressed() -> void:
	_refresh_models()

func _on_tags_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if response_code != 200:
		_set_status_disconnected("Ollama no responde (Código: %d)" % response_code)
		return

	var json = JSON.new()
	var parse_err = json.parse(body.get_string_from_utf8())
	if parse_err != OK:
		_set_status_disconnected("JSON inválido de Ollama")
		return

	var data = json.data
	var models: Array = data.get("models", [])
	model_dropdown.clear()

	if models.is_empty():
		model_dropdown.add_item("(Sin modelos instalados)")
		_set_status_disconnected("Sin modelos en Ollama")
		return

	for m in models:
		var m_name = m.get("name", "")
		model_dropdown.add_item(m_name)

	status_label.text = "● Ollama Conectado"
	status_label.modulate = Color(0.2, 0.9, 0.3)

func _set_status_disconnected(reason: String = "") -> void:
	status_label.text = "● Desconectado"
	status_label.modulate = Color(1.0, 0.3, 0.3)
	if not reason.is_empty():
		status_label.tooltip_text = reason

func _on_input_gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ENTER and not event.shift_pressed:
			get_viewport().set_input_as_handled()
			_on_send_pressed()

func _on_send_pressed() -> void:
	if is_requesting:
		return

	var text = prompt_input.text.strip_edges()
	if text.is_empty():
		return

	prompt_input.clear()

	# Agregar al chat visual
	chat_display.append_text("[b][color=#5cb3ff]Tú:[/color][/b] " + text + "\n\n")

	# Construir historial de mensajes para Ollama
	var prompt_messages: Array = []

	# Contexto de sistema
	var system_content = "Eres un asistente de desarrollo experto en Godot 4 y GDScript integrado en el editor de Godot.\n"
	system_content += "Sé claro, conciso y ofrece código GDScript moderno y funcional para Godot 4.\n"

	if ctx_checkbox.button_pressed:
		var scene_context = _gather_scene_context()
		system_content += "\n[CONTEXTO ACTUAL DEL EDITOR GODOT]:\n" + scene_context

	prompt_messages.append({
		"role": "system",
		"content": system_content
	})

	# Historial previo
	for m in messages:
		prompt_messages.append(m)

	# Mensaje actual del usuario
	var user_msg = {"role": "user", "content": text}
	prompt_messages.append(user_msg)
	messages.append(user_msg)

	# Enviar a Ollama
	var selected_idx = model_dropdown.selected
	var model_name = model_dropdown.get_item_text(selected_idx)
	if model_name.is_empty() or model_name.begins_with("("):
		chat_display.append_text("[color=red][b]Error:[/b] No hay ningún modelo seleccionado.[/color]\n\n")
		return

	var body_dict = {
		"model": model_name,
		"messages": prompt_messages,
		"stream": false
	}

	var json_body = JSON.stringify(body_dict)
	var headers = PackedStringArray(["Content-Type: application/json"])

	is_requesting = true
	send_btn.disabled = true
	send_btn.text = "..."
	chat_display.append_text("[b][color=#a37acc]Ollama (" + model_name + "):[/color][/b] [i]Pensando...[/i]\n")

	var err = chat_request.request(OLLAMA_HOST + "/api/chat", headers, HTTPClient.METHOD_POST, json_body)
	if err != OK:
		_finish_request_with_error("No se pudo enviar la solicitud HTTP: " + str(err))

func _on_chat_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	is_requesting = false
	send_btn.disabled = false
	send_btn.text = "Enviar"

	# Remover "[i]Pensando...[/i]\n" de la última línea visualizando respuesta
	# En RichTextLabel podemos agregar un salto de línea y la respuesta
	if response_code != 200:
		_finish_request_with_error("Error de Ollama (HTTP %d): %s" % [response_code, body.get_string_from_utf8()])
		return

	var json = JSON.new()
	var parse_err = json.parse(body.get_string_from_utf8())
	if parse_err != OK:
		_finish_request_with_error("Respuesta no válida de Ollama: " + json.get_error_message())
		return

	var resp = json.data
	var msg_obj = resp.get("message", {})
	var content = msg_obj.get("content", "")

	if content.is_empty():
		content = "(Respuesta vacía)"

	# Guardar en historial
	messages.append({
		"role": "assistant",
		"content": content
	})

	# Formatear y mostrar en el chat
	var formatted = _format_bbcode(content)
	chat_display.append_text(formatted + "\n\n")

func _finish_request_with_error(err_msg: String) -> void:
	is_requesting = false
	send_btn.disabled = false
	send_btn.text = "Enviar"
	chat_display.append_text("[color=#ff6b6b][b]Error:[/b] " + err_msg + "[/color]\n\n")

func _format_bbcode(raw_text: String) -> String:
	# Convertir bloques de código ```gdscript ... ``` o ``` ... ``` a formato BBCode
	var text = raw_text
	var code_regex = RegEx.new()
	code_regex.compile("(?s)```(?:[a-zA-Z0-9_-]+)?\\s*(.*?)```")
	text = code_regex.sub(text, "[code][color=#c3e88d]$1[/color][/code]", true)
	return text

func _gather_scene_context() -> String:
	var info = ""
	if plugin_ref:
		var ei = plugin_ref.get_editor_interface()
		var open_scenes = ei.get_open_scenes()
		info += "- Escenas abiertas en pestañas: " + str(open_scenes) + "\n"

		var selection = ei.get_selection().get_selected_nodes()
		if selection.is_empty():
			info += "- Nodos seleccionados actualmente: Ninguno\n"
		else:
			info += "- Nodos seleccionados actualmente:\n"
			for node in selection:
				info += "  * " + node.name + " (" + node.get_class() + ") en ruta: " + str(node.get_path()) + "\n"

	info += "- Versión del motor: Godot " + Engine.get_version_info().get("string", "") + "\n"
	return info

func _on_clear_pressed() -> void:
	messages.clear()
	chat_display.clear()
	chat_display.append_text("[color=#888888][i]Chat limpiado.[/i][/color]\n\n")
