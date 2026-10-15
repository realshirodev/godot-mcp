@tool
extends Control

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
var code_actions: Dictionary = {}
var action_counter: int = 0
var attached_scripts: Array[String] = []

var manually_selected_target: String = ""
var last_detected_path: String = ""
var poll_timer: float = 0.0

# UI Elements
var provider_dropdown: OptionButton
var model_dropdown: OptionButton
var status_label: Label
var refresh_btn: Button

# API Key row
var key_container: HBoxContainer
var key_label: Label
var key_input: LineEdit

# Target File Selector Row
var target_row: HBoxContainer
var target_lbl: Label
var target_dropdown: OptionButton
var refresh_target_btn: Button

# Scripts Attachment row & container
var scripts_bar: HBoxContainer
var attach_btn: Button
var attach_open_btn: Button
var attach_node_btn: Button
var clear_scripts_btn: Button
var chips_container: HFlowContainer
var file_dialog: FileDialog

# Options row
var opt_hbox: HBoxContainer
var ctx_checkbox: CheckBox
var auto_apply_checkbox: CheckBox
var clear_btn: Button

var chat_display: RichTextLabel
var prompt_input: TextEdit
var send_btn: Button

# HTTP
var http_request: HTTPRequest
var tags_request: HTTPRequest

const CLAUDE_MODELS = [
	"claude-3-7-sonnet-20250219",
	"claude-3-5-sonnet-20241022",
	"claude-3-5-haiku-20241022",
	"claude-3-opus-20240229"
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
	custom_minimum_size = Vector2(280, 310)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	_build_ui()
	_setup_http()
	_connect_editor_signals()
	_load_config()
	_update_provider_ui()
	_refresh_target_dropdown()
	_update_chips_ui()

func _process(delta: float) -> void:
	poll_timer += delta
	if poll_timer >= 0.3:
		poll_timer = 0.0
		_check_and_update_active_target()

func _connect_editor_signals() -> void:
	if plugin_ref:
		if not plugin_ref.scene_changed.is_connected(_on_scene_changed):
			plugin_ref.scene_changed.connect(_on_scene_changed)
		if not plugin_ref.scene_closed.is_connected(_on_scene_closed):
			plugin_ref.scene_closed.connect(_on_scene_closed)

		var ei = plugin_ref.get_editor_interface()
		var se = ei.get_script_editor()
		if se and not se.editor_script_changed.is_connected(_on_editor_script_changed):
			se.editor_script_changed.connect(_on_editor_script_changed)
		var sel = ei.get_selection()
		if sel and not sel.selection_changed.is_connected(_on_selection_changed):
			sel.selection_changed.connect(_on_selection_changed)

func _on_scene_changed(_scene_root: Node) -> void:
	if manually_selected_target.is_empty():
		_refresh_target_dropdown()

func _on_scene_closed(_filepath: String) -> void:
	if manually_selected_target.is_empty():
		_refresh_target_dropdown()

func _on_editor_script_changed(script: Script) -> void:
	if script and not script.resource_path.is_empty():
		if manually_selected_target.is_empty():
			_refresh_target_dropdown(script.resource_path)

func _on_selection_changed() -> void:
	if plugin_ref and manually_selected_target.is_empty():
		_refresh_target_dropdown()

func _check_and_update_active_target() -> void:
	if not manually_selected_target.is_empty():
		return
	var current = _detect_current_target_script()
	if current != last_detected_path:
		last_detected_path = current
		_refresh_target_dropdown(current)

func _detect_current_target_script() -> String:
	if not plugin_ref:
		return ""

	var ei = plugin_ref.get_editor_interface()
	var se = ei.get_script_editor()

	# 1. Si el usuario está trabajando en el Script Editor, dar prioridad al script seleccionado en él
	if se and se.is_visible_in_tree():
		var cs = se.get_current_script()
		if cs and cs is Script and not cs.resource_path.is_empty():
			return cs.resource_path

	# 2. Si hay un nodo seleccionado en la escena y tiene script adjunto
	var selection = ei.get_selection().get_selected_nodes()
	if not selection.is_empty():
		for node in selection:
			var scr = node.get_script()
			if scr and scr is Script and not scr.resource_path.is_empty():
				return scr.resource_path

	# 3. Si no hay nodo seleccionado con script, buscar el script del nodo raíz de la escena abierta
	var scene_root = ei.get_edited_scene_root()
	if scene_root:
		var root_scr = scene_root.get_script()
		if root_scr and root_scr is Script and not root_scr.resource_path.is_empty():
			return root_scr.resource_path

	# 4. Si no hay escena con script pero el script editor tiene un script abierto
	if se:
		var cs = se.get_current_script()
		if cs and cs is Script and not cs.resource_path.is_empty():
			return cs.resource_path

	# 5. Si no hay escena ni script seleccionado, devolver vacío (blanco)
	return ""

func _build_ui() -> void:
	var main_vbox = VBoxContainer.new()
	main_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_theme_constant_override("separation", 5)
	add_child(main_vbox)

	# --- Row 1: Provider & Status ---
	var row1 = HBoxContainer.new()
	row1.add_theme_constant_override("separation", 6)
	main_vbox.add_child(row1)

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
	status_label.text = "● Listo"
	status_label.modulate = Color(0.2, 0.9, 0.3)
	row1.add_child(status_label)

	# --- Row 2: Model & Refresh ---
	var row2 = HBoxContainer.new()
	row2.add_theme_constant_override("separation", 6)
	main_vbox.add_child(row2)

	var model_lbl = Label.new()
	model_lbl.text = "Modelo:"
	row2.add_child(model_lbl)

	model_dropdown = OptionButton.new()
	model_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	model_dropdown.item_selected.connect(func(_idx): _save_config())
	row2.add_child(model_dropdown)

	refresh_btn = Button.new()
	refresh_btn.text = "🔄"
	refresh_btn.tooltip_text = "Refrescar modelos disponibles"
	refresh_btn.pressed.connect(_on_refresh_pressed)
	row2.add_child(refresh_btn)

	# --- Row 3: API Key for Claude / OpenAI ---
	key_container = HBoxContainer.new()
	key_container.add_theme_constant_override("separation", 6)
	main_vbox.add_child(key_container)

	key_label = Label.new()
	key_label.text = "API Key:"
	key_container.add_child(key_label)

	key_input = LineEdit.new()
	key_input.secret = true
	key_input.placeholder_text = "sk-ant-... (Se guarda de forma segura)"
	key_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key_input.text_changed.connect(func(_t): _save_config())
	key_container.add_child(key_input)

	# --- Row 4: Target File Selector (Interactivo y sincronizado) ---
	target_row = HBoxContainer.new()
	target_row.add_theme_constant_override("separation", 6)
	main_vbox.add_child(target_row)

	target_lbl = Label.new()
	target_lbl.text = "🎯 Destino:"
	target_lbl.tooltip_text = "Archivo que Shiro AI editará cuando le pidas cambios de código"
	target_row.add_child(target_lbl)

	target_dropdown = OptionButton.new()
	target_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	target_dropdown.item_selected.connect(_on_target_dropdown_selected)
	target_row.add_child(target_dropdown)

	refresh_target_btn = Button.new()
	refresh_target_btn.text = "🔄"
	refresh_target_btn.tooltip_text = "Volver al modo automático (seguir escena o script activo)"
	refresh_target_btn.pressed.connect(func():
		manually_selected_target = ""
		last_detected_path = ""
		_refresh_target_dropdown()
	)
	target_row.add_child(refresh_target_btn)

	# --- Row 5: Attach Scripts Toolbar ---
	scripts_bar = HBoxContainer.new()
	scripts_bar.add_theme_constant_override("separation", 4)
	main_vbox.add_child(scripts_bar)

	var scr_lbl = Label.new()
	scr_lbl.text = "Scripts:"
	scripts_bar.add_child(scr_lbl)

	attach_btn = Button.new()
	attach_btn.text = "📎 Adjuntar"
	attach_btn.tooltip_text = "Seleccionar script(s) del proyecto para pasarle a Shiro AI"
	attach_btn.pressed.connect(_on_attach_pressed)
	scripts_bar.add_child(attach_btn)

	attach_open_btn = Button.new()
	attach_open_btn.text = "📑 Abiertos"
	attach_open_btn.tooltip_text = "Adjuntar automáticamente todos los scripts que tienes abiertos en pestañas"
	attach_open_btn.pressed.connect(_on_attach_open_pressed)
	scripts_bar.add_child(attach_open_btn)

	attach_node_btn = Button.new()
	attach_node_btn.text = "🎯 Nodo"
	attach_node_btn.tooltip_text = "Adjuntar el script del nodo seleccionado en la escena"
	attach_node_btn.pressed.connect(_on_attach_node_pressed)
	scripts_bar.add_child(attach_node_btn)

	clear_scripts_btn = Button.new()
	clear_scripts_btn.text = "✕"
	clear_scripts_btn.tooltip_text = "Quitar todos los scripts adjuntos"
	clear_scripts_btn.pressed.connect(_on_clear_scripts_pressed)
	scripts_bar.add_child(clear_scripts_btn)

	# --- Row 6: Attached Chips Container ---
	chips_container = HFlowContainer.new()
	chips_container.add_theme_constant_override("h_separation", 4)
	chips_container.add_theme_constant_override("v_separation", 4)
	main_vbox.add_child(chips_container)

	# --- Row 7: Options ---
	opt_hbox = HBoxContainer.new()
	opt_hbox.add_theme_constant_override("separation", 8)
	main_vbox.add_child(opt_hbox)

	auto_apply_checkbox = CheckBox.new()
	auto_apply_checkbox.text = "Auto-editar archivos"
	auto_apply_checkbox.button_pressed = true
	auto_apply_checkbox.tooltip_text = "Guarda y aplica automáticamente el código generado en el archivo correspondiente del proyecto"
	auto_apply_checkbox.toggled.connect(func(_b): _save_config())
	opt_hbox.add_child(auto_apply_checkbox)

	ctx_checkbox = CheckBox.new()
	ctx_checkbox.text = "Contexto escena"
	ctx_checkbox.button_pressed = true
	ctx_checkbox.tooltip_text = "Incluye nodos seleccionados y escenas abiertas en la consulta"
	opt_hbox.add_child(ctx_checkbox)

	clear_btn = Button.new()
	clear_btn.text = "Limpiar"
	clear_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	clear_btn.pressed.connect(_on_clear_pressed)
	opt_hbox.add_child(clear_btn)

	# --- Chat History Area ---
	chat_display = RichTextLabel.new()
	chat_display.bbcode_enabled = true
	chat_display.scroll_following = true
	chat_display.selection_enabled = true
	chat_display.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_display.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chat_display.custom_minimum_size = Vector2(0, 160)
	chat_display.meta_clicked.connect(_on_chat_meta_clicked)
	main_vbox.add_child(chat_display)

	chat_display.append_text("[color=#888888][i]Shiro AI Assistant listo. Selecciona un nodo en tu escena o abre un script en el editor y se detectará automáticamente.[/i][/color]\n\n")

	# --- Input Area ---
	var input_hbox = HBoxContainer.new()
	input_hbox.add_theme_constant_override("separation", 6)
	main_vbox.add_child(input_hbox)

	prompt_input = TextEdit.new()
	prompt_input.placeholder_text = "Escribe una instrucción... (Enter para enviar)..."
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

	# --- FileDialog Setup ---
	file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	file_dialog.access = FileDialog.ACCESS_RESOURCES
	file_dialog.filters = PackedStringArray(["*.gd ; GDScript"])
	file_dialog.files_selected.connect(_on_files_selected)
	add_child(file_dialog)

func _setup_http() -> void:
	tags_request = HTTPRequest.new()
	add_child(tags_request)
	tags_request.request_completed.connect(_on_tags_completed)

	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_chat_completed)

func _refresh_target_dropdown(preferred_path: String = "") -> void:
	target_dropdown.clear()
	var candidates: Array[String] = []

	var detected = preferred_path
	if detected.is_empty():
		detected = _detect_current_target_script()

	if not detected.is_empty():
		candidates.append(detected)

	# Agregar scripts abiertos en pestañas del editor
	if plugin_ref:
		var ei = plugin_ref.get_editor_interface()
		var se = ei.get_script_editor()
		if se:
			for scr in se.get_open_scripts():
				if scr and not scr.resource_path.is_empty():
					var p = scr.resource_path
					if not candidates.has(p):
						candidates.append(p)

	# Agregar scripts adjuntos
	for p in attached_scripts:
		if not candidates.has(p):
			candidates.append(p)

	if candidates.is_empty():
		target_dropdown.add_item("(Sin archivo seleccionado)")
		target_dropdown.modulate = Color(0.7, 0.7, 0.7)
		return

	target_dropdown.modulate = Color(1.0, 1.0, 1.0)
	for c in candidates:
		target_dropdown.add_item(c)

	var select_target = manually_selected_target
	if select_target.is_empty():
		select_target = detected

	for i in range(target_dropdown.item_count):
		if target_dropdown.get_item_text(i) == select_target:
			target_dropdown.select(i)
			return
	target_dropdown.select(0)

func _on_target_dropdown_selected(idx: int) -> void:
	var item_text = target_dropdown.get_item_text(idx)
	if item_text.begins_with("("):
		manually_selected_target = ""
	else:
		manually_selected_target = item_text

func _get_current_target_file() -> String:
	if target_dropdown.item_count > 0:
		var sel_idx = target_dropdown.selected
		if sel_idx >= 0 and sel_idx < target_dropdown.item_count:
			var txt = target_dropdown.get_item_text(sel_idx)
			if not txt.begins_with("("):
				return txt
	return _detect_current_target_script()

func _on_attach_pressed() -> void:
	file_dialog.popup_centered_ratio(0.7)

func _on_files_selected(paths: PackedStringArray) -> void:
	for p in paths:
		if not attached_scripts.has(p):
			attached_scripts.append(p)
	_update_chips_ui()
	_refresh_target_dropdown()

func _on_attach_open_pressed() -> void:
	if plugin_ref:
		var ei = plugin_ref.get_editor_interface()
		var se = ei.get_script_editor()
		if se:
			var open_scripts = se.get_open_scripts()
			for scr in open_scripts:
				if scr and not scr.resource_path.is_empty():
					var p = scr.resource_path
					if not attached_scripts.has(p):
						attached_scripts.append(p)
	_update_chips_ui()
	_refresh_target_dropdown()

func _on_attach_node_pressed() -> void:
	var target_p = ""
	if plugin_ref:
		var ei = plugin_ref.get_editor_interface()
		var selection = ei.get_selection().get_selected_nodes()
		if not selection.is_empty():
			var scr = selection[0].get_script()
			if scr and scr is Script and not scr.resource_path.is_empty():
				target_p = scr.resource_path
				if not attached_scripts.has(target_p):
					attached_scripts.append(target_p)
	_update_chips_ui()
	_refresh_target_dropdown(target_p)

func _on_clear_scripts_pressed() -> void:
	attached_scripts.clear()
	_update_chips_ui()
	_refresh_target_dropdown()

func _update_chips_ui() -> void:
	for child in chips_container.get_children():
		child.queue_free()

	if attached_scripts.is_empty():
		return

	for path in attached_scripts:
		var chip_btn = Button.new()
		chip_btn.text = "📄 " + path.get_file() + " ✕"
		chip_btn.tooltip_text = path + " (Clic para desadjuntar)"
		var target_path = path
		chip_btn.pressed.connect(func():
			attached_scripts.erase(target_path)
			_update_chips_ui()
			_refresh_target_dropdown()
		)
		chips_container.add_child(chip_btn)

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
			status_label.text = "● Claude Listo"
			status_label.modulate = Color(0.2, 0.9, 0.3)
		Provider.OPENAI:
			key_container.visible = true
			key_label.text = "OpenAI Key:"
			key_input.placeholder_text = "sk-..."
			refresh_btn.visible = false
			for m in OPENAI_MODELS:
				model_dropdown.add_item(m)
			status_label.text = "● OpenAI Listo"
			status_label.modulate = Color(0.2, 0.9, 0.3)

func _refresh_ollama_models() -> void:
	if not tags_request:
		return
	status_label.text = "● Conectando..."
	status_label.modulate = Color(0.9, 0.8, 0.2)
	var err = tags_request.request(OLLAMA_HOST + "/api/tags")
	if err != OK:
		_set_status_disconnected("Error al conectar con Ollama")

func _on_refresh_pressed() -> void:
	if current_provider == Provider.OLLAMA:
		_refresh_ollama_models()
	_refresh_target_dropdown()

func _on_tags_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if response_code != 200:
		_set_status_disconnected("Ollama no responde (Código: %d)" % response_code)
		return

	var json = JSON.new()
	var parse_err = json.parse(body.get_string_from_utf8())
	if parse_err != OK:
		_set_status_disconnected("Respuesta JSON inválida")
		return

	var data = json.data
	var models: Array = data.get("models", [])
	model_dropdown.clear()

	if models.is_empty():
		model_dropdown.add_item("(Sin modelos instalados)")
		_set_status_disconnected("Sin modelos instalados")
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
		if (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER) and not event.shift_pressed:
			get_viewport().set_input_as_handled()
			_on_send_pressed()

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

func _on_send_pressed() -> void:
	if is_requesting:
		return

	var text = prompt_input.text.strip_edges()
	if text.is_empty():
		return

	prompt_input.clear()

	var target_file = _get_current_target_file()
	var target_code = _read_file_text(target_file)

	chat_display.append_text("[b][color=#5cb3ff]Tú:[/color][/b] " + text + "\n")
	if not target_file.is_empty():
		chat_display.append_text("[color=#88bbff][size=12]🎯 Archivo destino: " + target_file + "[/size][/color]\n\n")
	else:
		chat_display.append_text("[color=#aaaaaa][size=12]🎯 Sin archivo destino seleccionado (Modo general)[/size][/color]\n\n")

	var system_content = "Eres Shiro AI Assistant, un asistente de desarrollo y programación experto en Godot 4 y GDScript, integrado directamente en el editor de Godot.\n"
	system_content += "REGLA SUPREMA PARA MODIFICAR O CREAR ARCHIVOS:\n"
	system_content += "El usuario espera que tus respuestas MODIFIQUEN DIRECTAMENTE los archivos en su proyecto, no que solo des explicaciones.\n"
	system_content += "Siempre que generes o modifiques código, DEBES incluir el bloque con la ruta exacta del archivo destino con este formato:\n"
	system_content += "```write_file:res://nombre_archivo.gd\n"
	system_content += "[CÓDIGO COMPLETO LISTO PARA EJECUTARSE]\n"
	system_content += "```\n"
	system_content += "El editor de Godot leerá ese bloque y escribirá el archivo en disco automáticamente.\n"

	if not target_file.is_empty():
		system_content += "El archivo principal objetivo seleccionado por el usuario es: " + target_file + "\n"
		if not target_code.is_empty():
			system_content += "\n[CÓDIGO ACTUAL DEL ARCHIVO DESTINO " + target_file + "]:\n```gdscript\n" + target_code + "\n```\n"
	else:
		system_content += "No hay ningún archivo objetivo seleccionado actualmente. Si vas a crear o modificar código, define tú mismo la ruta adecuada en ```write_file:res://...```.\n"

	if not attached_scripts.is_empty():
		system_content += "\n[OTROS SCRIPTS ADJUNTOS POR EL USUARIO]:\n"
		for p in attached_scripts:
			if p != target_file:
				var code = _read_file_text(p)
				system_content += "--- INICIO: " + p + " ---\n```gdscript\n" + code + "\n```\n--- FIN: " + p + " ---\n\n"
		system_content += "Si tus modificaciones afectan a varios de estos archivos, incluye un bloque ```write_file:res://...``` por cada archivo modificado.\n"

	if ctx_checkbox.button_pressed:
		system_content += "\n[CONTEXTO GENERAL DEL EDITOR]:\n" + _gather_scene_context()

	var selected_model = model_dropdown.get_item_text(model_dropdown.selected)
	if selected_model.is_empty() or selected_model.begins_with("("):
		chat_display.append_text("[color=red][b]Error:[/b] No hay ningún modelo seleccionado.[/color]\n\n")
		return

	var user_msg = {"role": "user", "content": text}
	messages.append(user_msg)

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
	for m in messages:
		prompt_messages.append(m)

	var body_dict = {
		"model": model_name,
		"messages": prompt_messages,
		"stream": false
	}

	var json_body = JSON.stringify(body_dict)
	var headers = PackedStringArray(["Content-Type: application/json"])

	_dispatch_http(OLLAMA_HOST + "/api/chat", headers, HTTPClient.METHOD_POST, json_body, "Ollama", model_name)

func _send_claude_request(system_content: String, model_name: String) -> void:
	var api_key = key_input.text.strip_edges()
	if api_key.is_empty():
		chat_display.append_text("[color=red][b]Error:[/b] Ingresa tu API Key de Claude en el campo superior.[/color]\n\n")
		return

	var anthropic_messages: Array = []
	for m in messages:
		anthropic_messages.append({
			"role": m.get("role", "user"),
			"content": m.get("content", "")
		})

	var body_dict = {
		"model": model_name,
		"max_tokens": 4096,
		"system": system_content,
		"messages": anthropic_messages
	}

	var json_body = JSON.stringify(body_dict)
	var headers = PackedStringArray([
		"Content-Type: application/json",
		"x-api-key: " + api_key,
		"anthropic-version: 2023-06-01"
	])

	_dispatch_http(CLAUDE_ENDPOINT, headers, HTTPClient.METHOD_POST, json_body, "Claude", model_name)

func _send_openai_request(system_content: String, model_name: String) -> void:
	var api_key = key_input.text.strip_edges()
	if api_key.is_empty():
		chat_display.append_text("[color=red][b]Error:[/b] Ingresa tu API Key de OpenAI en el campo superior.[/color]\n\n")
		return

	var prompt_messages: Array = []
	prompt_messages.append({"role": "system", "content": system_content})
	for m in messages:
		prompt_messages.append(m)

	var body_dict = {
		"model": model_name,
		"messages": prompt_messages
	}

	var json_body = JSON.stringify(body_dict)
	var headers = PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer " + api_key
	])

	_dispatch_http(OPENAI_ENDPOINT, headers, HTTPClient.METHOD_POST, json_body, "OpenAI", model_name)

func _dispatch_http(url: String, headers: PackedStringArray, method: int, json_body: String, provider_name: String, model_name: String) -> void:
	is_requesting = true
	send_btn.disabled = true
	send_btn.text = "..."
	chat_display.append_text("[b][color=#a37acc]" + provider_name + " (" + model_name + "):[/color][/b] [i]Analizando y procesando...[/i]\n")

	var err = http_request.request(url, headers, method, json_body)
	if err != OK:
		_finish_request_with_error("No se pudo iniciar la solicitud HTTP: " + str(err))

func _on_chat_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	is_requesting = false
	send_btn.disabled = false
	send_btn.text = "Enviar"

	var raw_str = body.get_string_from_utf8()

	if response_code != 200:
		_finish_request_with_error("Error del servidor (HTTP %d): %s" % [response_code, raw_str])
		return

	var json = JSON.new()
	var parse_err = json.parse(raw_str)
	if parse_err != OK:
		_finish_request_with_error("Respuesta no válida: " + json.get_error_message())
		return

	var data = json.data
	var assistant_content: String = ""

	match current_provider:
		Provider.OLLAMA:
			var msg_obj = data.get("message", {})
			assistant_content = msg_obj.get("content", "")
		Provider.CLAUDE:
			var content_list = data.get("content", [])
			for item in content_list:
				if item.get("type", "") == "text":
					assistant_content += item.get("text", "")
		Provider.OPENAI:
			var choices = data.get("choices", [])
			if not choices.is_empty():
				var choice_msg = choices[0].get("message", {})
				assistant_content = choice_msg.get("content", "")

	if assistant_content.is_empty():
		assistant_content = "(Respuesta vacía)"

	messages.append({"role": "assistant", "content": assistant_content})
	_process_and_display_response(assistant_content)

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

func _process_and_display_response(content: String) -> void:
	var current_target = _get_current_target_file()
	var applied_files: Array = []
	var blocks = _extract_code_blocks(content)

	for b in blocks:
		var header: String = b.get("header", "")
		var code: String = b.get("body", "")
		if code.is_empty():
			continue

		var target_path = ""
		if header.begins_with("write_file:") or header.begins_with("file:"):
			var parts = header.split(":", false, 1)
			if parts.size() > 1:
				target_path = parts[1].strip_edges()
		elif header.ends_with(".gd"):
			target_path = header.strip_edges()
		else:
			target_path = current_target

		if target_path.is_empty():
			chat_display.append_text("[color=yellow]⚠ Código generado pero no hay archivo destino seleccionado ni especificado. Selecciona un nodo o script para aplicarlo automáticamente.[/color]\n")
			continue

		if not target_path.begins_with("res://") and not target_path.begins_with("user://"):
			target_path = "res://" + target_path

		action_counter += 1
		var action_id = str(action_counter)
		code_actions[action_id] = {"path": target_path, "code": code}

		if auto_apply_checkbox.button_pressed and not target_path.is_empty():
			var ok = _apply_file_content(target_path, code)
			if ok and not applied_files.has(target_path):
				applied_files.append(target_path)

	var formatted = _format_bbcode(content)
	chat_display.append_text(formatted + "\n")

	for p in applied_files:
		chat_display.append_text("[color=#55ff88][b]✔ Archivo editado y guardado en Godot:[/b] " + p + "[/color]\n")

	for act_id in code_actions.keys():
		var act = code_actions[act_id]
		chat_display.append_text("[url=apply:" + act_id + "][color=#5cb3ff][b]💾 [Guardar en " + act.path + "][/b][/color][/url]  ")
	chat_display.append_text("\n\n")

func _apply_file_content(file_path: String, content: String) -> bool:
	if file_path.is_empty() or content.is_empty():
		return false

	if not file_path.begins_with("res://") and not file_path.begins_with("user://"):
		file_path = "res://" + file_path

	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if not file:
		var err = FileAccess.get_open_error()
		chat_display.append_text("[color=red][b]Error al escribir " + file_path + ":[/b] " + str(err) + "[/color]\n")
		return false

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

	print("[Shiro AI Assistant] Archivo escrito y recargado con éxito: ", file_path)
	return true

func _on_chat_meta_clicked(meta: Variant) -> void:
	var meta_str = str(meta)
	if meta_str.begins_with("apply:"):
		var act_id = meta_str.substr(6)
		if code_actions.has(act_id):
			var act = code_actions[act_id]
			var ok = _apply_file_content(act.path, act.code)
			if ok:
				chat_display.append_text("[color=#55ff88][b]✔ Código aplicado manualmente a:[/b] " + act.path + "[/color]\n")

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
		var body = inside
		if first_newline != -1:
			body = inside.substr(first_newline + 1).strip_edges()
		result += "[code][color=#c3e88d]" + body + "[/color][/code]"
		start_pos = end_idx + 3
	return result

func _gather_scene_context() -> String:
	var info = ""
	if plugin_ref:
		var ei = plugin_ref.get_editor_interface()
		var open_scenes = ei.get_open_scenes()
		info += "- Escenas abiertas: " + str(open_scenes) + "\n"

		var selection = ei.get_selection().get_selected_nodes()
		if selection.is_empty():
			info += "- Nodos seleccionados: Ninguno\n"
		else:
			info += "- Nodos seleccionados:\n"
			for node in selection:
				var scr_info = ""
				var s = node.get_script()
				if s and s is Script:
					scr_info = " (Script: " + s.resource_path + ")"
				info += "  * " + node.name + " [" + node.get_class() + "]" + scr_info + " en " + str(node.get_path()) + "\n"

	return info

func _on_clear_pressed() -> void:
	messages.clear()
	code_actions.clear()
	chat_display.clear()
	chat_display.append_text("[color=#888888][i]Chat limpiado.[/i][/color]\n\n")

func _save_config() -> void:
	var cfg = {
		"provider": provider_dropdown.selected,
		"key": key_input.text,
		"model_index": model_dropdown.selected,
		"auto_apply": auto_apply_checkbox.button_pressed
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
