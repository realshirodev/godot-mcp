#!/usr/bin/env node
import readline from "readline";
import path from "path";
import { fileURLToPath } from "url";
import { spawn } from "child_process";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const OLLAMA_HOST = process.env.OLLAMA_HOST || "http://localhost:11434";
const DEFAULT_MODEL = process.env.OLLAMA_MODEL || "qwen2.5-coder:latest";

// Tool definitions for Ollama function calling format
const GODOT_TOOLS = [
  {
    type: "function",
    function: {
      name: "godot_set_project_path",
      description: "Sets the active Godot project directory path.",
      parameters: {
        type: "object",
        properties: {
          path: { type: "string", description: "Absolute path to Godot project" }
        },
        required: ["path"]
      }
    }
  },
  {
    type: "function",
    function: {
      name: "godot_get_project_info",
      description: "Reads project.godot to get name, main scene, and Godot configuration.",
      parameters: {
        type: "object",
        properties: {
          projectPath: { type: "string", description: "Optional project path" }
        }
      }
    }
  },
  {
    type: "function",
    function: {
      name: "godot_list_files",
      description: "Lists all scenes (.tscn), scripts (.gd), resources (.tres), shaders in the Godot project.",
      parameters: {
        type: "object",
        properties: {
          filter: {
            type: "string",
            enum: ["all", "scenes", "scripts", "resources", "shaders"],
            description: "Filter file type"
          }
        }
      }
    }
  },
  {
    type: "function",
    function: {
      name: "godot_read_scene",
      description: "Reads and inspects a Godot scene (.tscn) node tree and attached scripts.",
      parameters: {
        type: "object",
        properties: {
          scenePath: { type: "string", description: "res:// path or filename of the scene" }
        },
        required: ["scenePath"]
      }
    }
  },
  {
    type: "function",
    function: {
      name: "godot_create_scene",
      description: "Creates a new Godot 4 scene (.tscn) with root node and optional child nodes/scripts.",
      parameters: {
        type: "object",
        properties: {
          scenePath: { type: "string", description: "Path to create, e.g. 'res://player.tscn'" },
          rootName: { type: "string", description: "Root node name, e.g. 'Player'" },
          rootType: { type: "string", description: "Root node type, e.g. 'CharacterBody2D'" },
          scriptResPath: { type: "string", description: "Optional script path, e.g. 'res://player.gd'" },
          children: {
            type: "array",
            items: {
              type: "object",
              properties: {
                name: { type: "string" },
                type: { type: "string" },
                parent: { type: "string" }
              },
              required: ["name", "type"]
            }
          }
        },
        required: ["scenePath", "rootName", "rootType"]
      }
    }
  },
  {
    type: "function",
    function: {
      name: "godot_read_script",
      description: "Reads GDScript code from a .gd file.",
      parameters: {
        type: "object",
        properties: {
          scriptPath: { type: "string", description: "Path to script, e.g. 'res://player.gd'" }
        },
        required: ["scriptPath"]
      }
    }
  },
  {
    type: "function",
    function: {
      name: "godot_write_script",
      description: "Writes GDScript code to a .gd file with Godot 4 syntax validation.",
      parameters: {
        type: "object",
        properties: {
          scriptPath: { type: "string", description: "Path to script file, e.g. 'res://player.gd'" },
          content: { type: "string", description: "Valid GDScript code" }
        },
        required: ["scriptPath", "content"]
      }
    }
  },
  {
    type: "function",
    function: {
      name: "godot_api_docs",
      description: "Queries Godot 4 API documentation, node properties, and Godot 3 vs Godot 4 syntax rules.",
      parameters: {
        type: "object",
        properties: {
          nodeType: { type: "string", description: "Node class name e.g. 'CharacterBody2D'" }
        }
      }
    }
  }
];

// Helper to spawn MCP server process or call tools directly
import { parseProjectGodot, scanProjectFiles, parseTscn, generateTscn } from "./src/godot-parser.js";
import { GODOT4_SYNTAX_RULES, COMMON_NODE_DOCS, validateGDScript } from "./src/godot-docs.js";
import fs from "fs/promises";

let currentProjectPath = process.env.GODOT_PROJECT_PATH || process.cwd();

async function executeMcpTool(name, args) {
  try {
    switch (name) {
      case "godot_set_project_path": {
        currentProjectPath = path.resolve(args.path);
        const info = await parseProjectGodot(currentProjectPath);
        return JSON.stringify({ success: true, project: info });
      }
      case "godot_get_project_info": {
        const info = await parseProjectGodot(args.projectPath ? path.resolve(args.projectPath) : currentProjectPath);
        return JSON.stringify(info);
      }
      case "godot_list_files": {
        const files = await scanProjectFiles(currentProjectPath);
        return JSON.stringify(files);
      }
      case "godot_read_scene": {
        const clean = args.scenePath.replace("res://", "");
        const absPath = path.isAbsolute(clean) ? clean : path.resolve(currentProjectPath, clean);
        const parsed = await parseTscn(absPath);
        return JSON.stringify(parsed);
      }
      case "godot_create_scene": {
        const clean = args.scenePath.replace("res://", "");
        const absPath = path.isAbsolute(clean) ? clean : path.resolve(currentProjectPath, clean);
        await fs.mkdir(path.dirname(absPath), { recursive: true });
        const content = generateTscn({
          rootName: args.rootName,
          rootType: args.rootType,
          scriptResPath: args.scriptResPath,
          children: args.children || []
        });
        await fs.writeFile(absPath, content, "utf-8");
        return JSON.stringify({ success: true, path: absPath });
      }
      case "godot_read_script": {
        const clean = args.scriptPath.replace("res://", "");
        const absPath = path.isAbsolute(clean) ? clean : path.resolve(currentProjectPath, clean);
        const code = await fs.readFile(absPath, "utf-8");
        return JSON.stringify({ code, warnings: validateGDScript(code) });
      }
      case "godot_write_script": {
        const clean = args.scriptPath.replace("res://", "");
        const absPath = path.isAbsolute(clean) ? clean : path.resolve(currentProjectPath, clean);
        await fs.mkdir(path.dirname(absPath), { recursive: true });
        await fs.writeFile(absPath, args.content, "utf-8");
        return JSON.stringify({ success: true, path: absPath, warnings: validateGDScript(args.content) });
      }
      case "godot_api_docs": {
        if (args.nodeType && COMMON_NODE_DOCS[args.nodeType]) {
          return JSON.stringify(COMMON_NODE_DOCS[args.nodeType]);
        }
        return JSON.stringify({ rules: GODOT4_SYNTAX_RULES, nodes: Object.keys(COMMON_NODE_DOCS) });
      }
      default:
        return JSON.stringify({ error: `Tool ${name} not found` });
    }
  } catch (err) {
    return JSON.stringify({ error: err.message });
  }
}

async function getAvailableOllamaModels() {
  try {
    const res = await fetch(`${OLLAMA_HOST}/api/tags`);
    if (!res.ok) return [];
    const data = await res.json();
    return (data.models || []).map(m => m.name);
  } catch {
    return [];
  }
}

async function runOllamaAgent(userPrompt, selectedModel) {
  console.log(`\n\x1b[36m[Ollama Godot Agent]\x1b[0m Usando modelo: \x1b[33m${selectedModel}\x1b[0m`);
  console.log(`\x1b[36m[Ollama Godot Agent]\x1b[0m Proyecto Godot activo: \x1b[32m${currentProjectPath}\x1b[0m\n`);

  const messages = [
    {
      role: "system",
      content: `Eres un asistente experto en desarrollo de videojuegos con Godot Engine 4.x y GDScript.
Tienes a tu disposición herramientas MCP para inspeccionar el proyecto de Godot, crear escenas (.tscn), leer y escribir scripts (.gd) y consultar documentación de la API.
Reglas obligatorias:
1. Siempre usa sintaxis de Godot 4 (@export, @onready, CharacterBody2D, await, move_and_slide() sin argumentos).
2. Usa las herramientas provistas cuando el usuario te pida crear o modificar archivos en el proyecto.
3. Explica claramente los cambios realizados.`
    },
    {
      role: "user",
      content: userPrompt
    }
  ];

  let keepGoing = true;
  let iterations = 0;
  const maxIterations = 8;

  while (keepGoing && iterations < maxIterations) {
    iterations++;

    process.stdout.write("\x1b[90mConsultando Ollama...\x1b[0m\r");
    const response = await fetch(`${OLLAMA_HOST}/api/chat`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        model: selectedModel,
        messages: messages,
        tools: GODOT_TOOLS,
        stream: false
      })
    });

    if (!response.ok) {
      const errText = await response.text();
      console.error(`\x1b[31mError en Ollama (${response.status}): ${errText}\x1b[0m`);
      return;
    }

    const data = await response.json();
    const assistantMessage = data.message;
    messages.push(assistantMessage);

    if (assistantMessage.content) {
      console.log(`\n\x1b[32m🤖 Ollama:\x1b[0m\n${assistantMessage.content}\n`);
    }

    if (assistantMessage.tool_calls && assistantMessage.tool_calls.length > 0) {
      for (const call of assistantMessage.tool_calls) {
        const toolName = call.function.name;
        const toolArgs = call.function.arguments;
        console.log(`\x1b[35m⚙️  Ejecutando herramienta MCP:\x1b[0m \x1b[1m${toolName}\x1b[0m`);
        console.log(`   Argumentos:`, JSON.stringify(toolArgs));

        const result = await executeMcpTool(toolName, toolArgs);
        console.log(`   Resultado: \x1b[90m${result.slice(0, 150)}${result.length > 150 ? "..." : ""}\x1b[0m`);

        messages.push({
          role: "tool",
          content: result
        });
      }
    } else {
      keepGoing = false;
    }
  }
}

async function main() {
  const models = await getAvailableOllamaModels();
  if (models.length === 0) {
    console.log(`\x1b[33m⚠️  No se pudo conectar a Ollama en ${OLLAMA_HOST}.\x1b[0m`);
    console.log(`   Por favor, asegúrate de que Ollama esté ejecutándose ('ollama serve').`);
    console.log(`   Puedes descargar e instalar modelos recomendados con:`);
    console.log(`   > ollama run qwen2.5-coder`);
    console.log(`   > ollama run llama3.1\n`);
  }

  const modelToUse = models.find(m => m.includes("qwen") || m.includes("llama")) || models[0] || DEFAULT_MODEL;

  const argPrompt = process.argv.slice(2).join(" ");
  if (argPrompt) {
    await runOllamaAgent(argPrompt, modelToUse);
    return;
  }

  console.log(`=======================================================`);
  console.log(`🎮 Godot Engine 4.x + Ollama MCP Agent Console`);
  console.log(`=======================================================`);
  console.log(`Modelos detectados en Ollama: ${models.join(", ") || "(Ninguno detectado)"}`);
  console.log(`Modelo activo: ${modelToUse}`);
  console.log(`Escribe tu petición para Godot o 'salir' para terminar.\n`);

  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout
  });

  const promptUser = () => {
    rl.question("\x1b[1m\x1b[34mTu petición para Godot > \x1b[0m", async (input) => {
      const trimmed = input.trim();
      if (!trimmed || trimmed.toLowerCase() === "salir" || trimmed.toLowerCase() === "exit") {
        rl.close();
        return;
      }
      try {
        await runOllamaAgent(trimmed, modelToUse);
      } catch (err) {
        console.error("\x1b[31mError ejecutando agente:\x1b[0m", err);
      }
      promptUser();
    });
  };

  promptUser();
}

main();
