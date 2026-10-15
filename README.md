# 🎮 Godot Engine 4.x + Ollama MCP Server

Un servidor completo basado en el **Model Context Protocol (MCP)** para permitir que modelos de lenguaje locales (vía **Ollama**) y asistentes de IA (Antigravity IDE, Claude Desktop, Cursor) interactúen, creen, lean y modifiquen proyectos de **Godot Engine 4.x**.

---

## ✨ Características

1. **Gestión de escenas (`.tscn`)**:
   - Crear escenas completas con nodo raíz, jerarquía de hijos, propiedades y scripts asociados.
   - Parsear e inspeccionar escenas existentes y su árbol de nodos.
2. **Gestión de scripts (`.gd`) y validación de sintaxis**:
   - Leer y escribir scripts GDScript.
   - **Linter de sintaxis Godot 4**: detecta automáticamente errores comunes de sintaxis antigua de Godot 3 (como `export(...) var`, `onready`, `yield`, `KinematicBody`, `.instance()`, `move_and_slide(velocity)`) y sugiere la sintaxis moderna de Godot 4 (`@export`, `@onready`, `await`, `CharacterBody2D`, `.instantiate()`, `move_and_slide()`).
3. **Exploración del proyecto**:
   - Inspecciona `project.godot`, escena principal, versión de configuración y autoloads.
   - Escaneo recursivo de escenas, scripts, recursos (`.tres`) y shaders (`.gdshader`).
4. **Referencia de API Godot 4 integrada**:
   - Documentación y snippets para nodos clave como `CharacterBody2D`, `CharacterBody3D`, `Area2D`, `Camera2D`, `AnimationPlayer` y señales.
5. **Ejecución y pruebas del juego**:
   - Lanzamiento de Godot en modo ventana, debug o `--headless` para validar que el proyecto compila y no tiene errores.
6. **Agente interactivo para Ollama (`ollama-agent.js`)**:
   - Conecta directamente el endpoint `/api/chat` de Ollama con soporte nativo de **function calling / tool use** para que el modelo ejecute acciones sobre tu juego automáticamente.
7. **Addon en vivo opcional para el Editor de Godot (`addons/godot_mcp_bridge`)**:
   - Permite que el servidor MCP consulte escenas abiertas, nodos seleccionados en el árbol y recargue el sistema de archivos del editor en tiempo real.

---

## 🚀 Requisitos Previos

- **Node.js** v18 o superior (detectado v22.x).
- **Godot Engine 4.x** (opcional para ejecución directa o el editor live bridge).
- **Ollama** ejecutándose localmente (`http://localhost:11434`) con un modelo que soporte llamadas a herramientas (Recomendados: `qwen2.5-coder`, `llama3.1` o `mistral`).
  ```bash
  ollama run qwen2.5-coder
  ```

---

## 🛠️ Modos de Uso

### Modo 1: Consola Interactiva con Ollama

Puedes pedirle a Ollama directamente en lenguaje natural que trabaje sobre tu proyecto de Godot:

```bash
cd C:\Users\TuUser\.gemini\antigravity-ide\scratch\godot-mcp
node ollama-agent.js
```

O enviando la orden directamente:
```bash
node ollama-agent.js "Crea un script para un CharacterBody2D con movimiento en 8 direcciones y velocidad configurable"
```

El agente:
1. Consultará tu proyecto Godot activo.
2. Generará el código GDScript con validación de sintaxis Godot 4.
3. Creará la escena `.tscn` o el script `.gd` automáticamente.

---

### Modo 2: Como Servidor MCP Estándar (Antigravity IDE / Claude Desktop / Cursor)

Puedes registrar este servidor en tu archivo de configuración de MCP (por ejemplo `mcp_config.json` en Antigravity IDE o `claude_desktop_config.json` en Claude Desktop):

```json
{
  "mcpServers": {
    "godot-mcp": {
      "command": "node",
      "args": [
        "C:\\Users\\Shiro\\.gemini\\antigravity-ide\\scratch\\godot-mcp\\src\\server.js"
      ],
      "env": {
        "GODOT_PROJECT_PATH": "C:\\Ruta\\A\\Tu\\Proyecto\\Godot",
        "GODOT_PATH": "godot"
      }
    }
  }
}
```

---

### Modo 3: Plugin en Vivo para el Editor de Godot (Opcional)

Si deseas sincronización bidireccional en tiempo real mientras el editor de Godot está abierto:

1. Copia la carpeta `addons/godot_mcp` a la carpeta `addons/` de tu proyecto de Godot.
2. Abre tu proyecto en Godot Engine.
3. Ve a **Proyecto > Configuración del Proyecto > Plugins** (Project Settings > Plugins).
4. Activa la casilla de **Godot MCP Bridge**.
5. Verás en la consola de Godot: `[Godot MCP Bridge] Listening on 127.0.0.1:6008`.

*Nota: Si el plugin no está instalado o el editor está cerrado, el servidor MCP funciona perfectamente en modo directo sobre los archivos del proyecto.*

---

## 📋 Lista de Herramientas MCP Disponibles

| Herramienta | Descripción |
|---|---|
| `godot_set_project_path` | Cambia el directorio del proyecto Godot activo. |
| `godot_get_project_info` | Lee `project.godot` (nombre, escena principal, configuración). |
| `godot_list_files` | Lista escenas, scripts, recursos y shaders del proyecto. |
| `godot_read_scene` | Lee e inspecciona la jerarquía y propiedades de un `.tscn`. |
| `godot_create_scene` | Genera una nueva escena `.tscn` con nodo raíz e hijos. |
| `godot_read_script` | Lee el contenido de un script `.gd`. |
| `godot_write_script` | Escribe un script `.gd` aplicando validación de sintaxis Godot 4. |
| `godot_api_docs` | Consulta documentación y buenas prácticas de nodos Godot 4. |
| `godot_run_project` | Ejecuta el juego o una escena específica (normal o headless). |
| `godot_live_editor_command` | Envía comandos al editor en vivo vía TCP (ping, reload, selección). |

---

## 🧪 Pruebas Automatizadas

Para validar que todos los módulos y herramientas funcionan correctamente:
```bash
npm test
```
