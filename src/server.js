#!/usr/bin/env node
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import path from "path";
import fs from "fs/promises";
import { spawn } from "child_process";
import {
  parseProjectGodot,
  scanProjectFiles,
  parseTscn,
  generateTscn
} from "./godot-parser.js";
import {
  GODOT4_SYNTAX_RULES,
  COMMON_NODE_DOCS,
  validateGDScript
} from "./godot-docs.js";
import { sendCommandToEditor } from "./live-bridge.js";

// Active project path (can be initialized via env GODOT_PROJECT_PATH or arg or tool)
let currentProjectPath = process.env.GODOT_PROJECT_PATH || process.cwd();
let godotExecutablePath = process.env.GODOT_PATH || "godot";

const server = new Server(
  {
    name: "godot-mcp-server",
    version: "1.0.0",
  },
  {
    capabilities: {
      tools: {},
    },
  }
);

// Define tool schemas
const TOOLS = [
  {
    name: "godot_set_project_path",
    description: "Sets or updates the active Godot project directory path.",
    inputSchema: {
      type: "object",
      properties: {
        path: {
          type: "string",
          description: "Absolute or relative path to the Godot project root (containing project.godot)"
        }
      },
      required: ["path"]
    }
  },
  {
    name: "godot_get_project_info",
    description: "Inspects project.godot and returns project metadata, config version, main scene, and autoloads.",
    inputSchema: {
      type: "object",
      properties: {
        projectPath: {
          type: "string",
          description: "Optional override of the Godot project path. Defaults to active project."
        }
      }
    }
  },
  {
    name: "godot_list_files",
    description: "Lists all scenes (.tscn), scripts (.gd), resources (.tres), and shaders in the Godot project.",
    inputSchema: {
      type: "object",
      properties: {
        filter: {
          type: "string",
          enum: ["all", "scenes", "scripts", "resources", "shaders"],
          description: "Filter file type (default: 'all')"
        }
      }
    }
  },
  {
    name: "godot_read_scene",
    description: "Reads and parses a Godot scene (.tscn) into structured node hierarchy, properties, and scripts.",
    inputSchema: {
      type: "object",
      properties: {
        scenePath: {
          type: "string",
          description: "Path to scene, e.g. 'res://player.tscn' or 'player.tscn' or absolute path"
        }
      },
      required: ["scenePath"]
    }
  },
  {
    name: "godot_create_scene",
    description: "Creates a new Godot 4 scene (.tscn) with a root node, attached script, and optional child nodes.",
    inputSchema: {
      type: "object",
      properties: {
        scenePath: {
          type: "string",
          description: "Destination path for .tscn, e.g. 'res://scenes/player.tscn' or relative 'player.tscn'"
        },
        rootName: {
          type: "string",
          description: "Name of the root node (e.g. 'Player', 'Enemy', 'World')"
        },
        rootType: {
          type: "string",
          description: "Type of the root node (e.g. 'CharacterBody2D', 'Node2D', 'Area2D', 'Control', 'Node3D')"
        },
        scriptResPath: {
          type: "string",
          description: "Optional res:// path to a script to attach to the root node (e.g. 'res://player.gd')"
        },
        children: {
          type: "array",
          description: "Array of child nodes to add",
          items: {
            type: "object",
            properties: {
              name: { type: "string" },
              type: { type: "string" },
              parent: { type: "string", description: "Parent node path, '.' for root node" },
              properties: {
                type: "object",
                description: "Key-value map of properties, e.g. { 'position': 'Vector2(0, 0)' }"
              }
            },
            required: ["name", "type"]
          }
        }
      },
      required: ["scenePath", "rootName", "rootType"]
    }
  },
  {
    name: "godot_read_script",
    description: "Reads the content of a GDScript file (.gd).",
    inputSchema: {
      type: "object",
      properties: {
        scriptPath: {
          type: "string",
          description: "Path to script, e.g. 'res://player.gd' or 'player.gd' or absolute path"
        }
      },
      required: ["scriptPath"]
    }
  },
  {
    name: "godot_write_script",
    description: "Creates or overwrites a GDScript (.gd) file. Automatically validates Godot 4 syntax rules.",
    inputSchema: {
      type: "object",
      properties: {
        scriptPath: {
          type: "string",
          description: "Path to script, e.g. 'res://player.gd' or relative 'player.gd'"
        },
        content: {
          type: "string",
          description: "GDScript code content"
        }
      },
      required: ["scriptPath", "content"]
    }
  },
  {
    name: "godot_api_docs",
    description: "Provides Godot 4 reference documentation, syntax rules, and examples for nodes (CharacterBody2D, Area2D, etc.).",
    inputSchema: {
      type: "object",
      properties: {
        nodeType: {
          type: "string",
          description: "Name of node to inspect (e.g. 'CharacterBody2D', 'Area2D', 'Camera2D', 'AnimationPlayer') or leave empty for general Godot 4 syntax rules."
        }
      }
    }
  },
  {
    name: "godot_run_project",
    description: "Launches the Godot project or a specific scene using the Godot engine executable.",
    inputSchema: {
      type: "object",
      properties: {
        godotExecutable: {
          type: "string",
          description: "Optional custom path to godot.exe if not in PATH"
        },
        scenePath: {
          type: "string",
          description: "Optional specific scene to run (e.g. 'res://scenes/test.tscn'). Defaults to main scene."
        },
        mode: {
          type: "string",
          enum: ["window", "debug", "headless"],
          description: "Launch mode ('window' runs normally, 'debug' collects logs, 'headless' runs without rendering for testing)"
        }
      }
    }
  },
  {
    name: "godot_live_editor_command",
    description: "Sends a command to the running Godot Editor (requires godot_mcp_bridge plugin active in editor).",
    inputSchema: {
      type: "object",
      properties: {
        command: {
          type: "string",
          description: "Command name (e.g. 'ping', 'get_open_scenes', 'get_selected_nodes', 'reload_scripts')"
        },
        payload: {
          type: "object",
          description: "Optional parameters for the command"
        }
      },
      required: ["command"]
    }
  }
];

// Resolves a path that might be "res://foo" to an absolute local filesystem path
function resolveResPath(p, projectDir = currentProjectPath) {
  if (!p) return "";
  let clean = p.trim();
  if (clean.startsWith("res://")) {
    clean = clean.replace("res://", "");
  }
  if (path.isAbsolute(clean)) {
    return clean;
  }
  return path.resolve(projectDir, clean);
}

server.setRequestHandler(ListToolsRequestSchema, async () => {
  return { tools: TOOLS };
});

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args = {} } = request.params;

  try {
    switch (name) {
      case "godot_set_project_path": {
        const target = path.resolve(args.path);
        const info = await parseProjectGodot(target);
        if (!info.exists) {
          return {
            content: [
              {
                type: "text",
                text: JSON.stringify({
                  success: false,
                  message: `No project.godot found at ${target}. Please make sure this directory is a Godot project.`,
                  path: target
                }, null, 2)
              }
            ],
            isError: true
          };
        }
        currentProjectPath = target;
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify({
                success: true,
                message: `Active Godot project set to ${currentProjectPath}`,
                project: info
              }, null, 2)
            }
          ]
        };
      }

      case "godot_get_project_info": {
        const target = args.projectPath ? path.resolve(args.projectPath) : currentProjectPath;
        const info = await parseProjectGodot(target);
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(info, null, 2)
            }
          ]
        };
      }

      case "godot_list_files": {
        const files = await scanProjectFiles(currentProjectPath);
        const filter = args.filter || "all";
        let result = files;
        if (filter !== "all") {
          result = { [filter]: files[filter] || [] };
        }
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify({
                projectPath: currentProjectPath,
                counts: {
                  scenes: files.scenes.length,
                  scripts: files.scripts.length,
                  resources: files.resources.length,
                  shaders: files.shaders.length,
                  others: files.others.length
                },
                files: result
              }, null, 2)
            }
          ]
        };
      }

      case "godot_read_scene": {
        const absPath = resolveResPath(args.scenePath);
        const parsed = await parseTscn(absPath);
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(parsed, null, 2)
            }
          ]
        };
      }

      case "godot_create_scene": {
        const absPath = resolveResPath(args.scenePath);
        await fs.mkdir(path.dirname(absPath), { recursive: true });

        const tscnContent = generateTscn({
          rootName: args.rootName,
          rootType: args.rootType,
          scriptResPath: args.scriptResPath,
          children: args.children || []
        });

        await fs.writeFile(absPath, tscnContent, "utf-8");

        return {
          content: [
            {
              type: "text",
              text: JSON.stringify({
                success: true,
                message: `Scene created successfully at ${absPath}`,
                resPath: "res://" + path.relative(currentProjectPath, absPath).replace(/\\/g, "/"),
                content: tscnContent
              }, null, 2)
            }
          ]
        };
      }

      case "godot_read_script": {
        const absPath = resolveResPath(args.scriptPath);
        const code = await fs.readFile(absPath, "utf-8");
        const issues = validateGDScript(code);
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify({
                path: absPath,
                code: code,
                godot4LintWarnings: issues
              }, null, 2)
            }
          ]
        };
      }

      case "godot_write_script": {
        const absPath = resolveResPath(args.scriptPath);
        await fs.mkdir(path.dirname(absPath), { recursive: true });

        const validationIssues = validateGDScript(args.content);
        await fs.writeFile(absPath, args.content, "utf-8");

        return {
          content: [
            {
              type: "text",
              text: JSON.stringify({
                success: true,
                message: `Script written to ${absPath}`,
                warnings: validationIssues
              }, null, 2)
            }
          ]
        };
      }

      case "godot_api_docs": {
        if (args.nodeType && COMMON_NODE_DOCS[args.nodeType]) {
          return {
            content: [
              {
                type: "text",
                text: JSON.stringify({
                  node: args.nodeType,
                  details: COMMON_NODE_DOCS[args.nodeType]
                }, null, 2)
              }
            ]
          };
        }

        return {
          content: [
            {
              type: "text",
              text: JSON.stringify({
                godot4SyntaxRules: GODOT4_SYNTAX_RULES,
                availableDocNodes: Object.keys(COMMON_NODE_DOCS)
              }, null, 2)
            }
          ]
        };
      }

      case "godot_run_project": {
        const exe = args.godotExecutable || godotExecutablePath;
        const runArgs = ["--path", currentProjectPath];

        if (args.scenePath) {
          runArgs.push(args.scenePath);
        }
        if (args.mode === "headless") {
          runArgs.push("--headless");
        }

        try {
          const proc = spawn(exe, runArgs, {
            cwd: currentProjectPath,
            detached: args.mode !== "headless",
            stdio: args.mode === "headless" ? ["ignore", "pipe", "pipe"] : "ignore"
          });

          if (args.mode !== "headless") {
            proc.unref();
            return {
              content: [
                {
                  type: "text",
                  text: JSON.stringify({
                    success: true,
                    message: `Godot launched in window mode with pid ${proc.pid}`,
                    executable: exe,
                    args: runArgs
                  }, null, 2)
                }
              ]
            };
          }

          // In headless mode, wait briefly or capture output
          let output = "";
          proc.stdout?.on("data", d => output += d.toString());
          proc.stderr?.on("data", d => output += d.toString());

          await new Promise((resolve) => {
            const timeout = setTimeout(() => {
              proc.kill();
              resolve();
            }, 3000);
            proc.on("close", () => {
              clearTimeout(timeout);
              resolve();
            });
          });

          return {
            content: [
              {
                type: "text",
                text: JSON.stringify({
                  success: true,
                  message: "Godot headless execution completed or timed out (3s).",
                  output: output.trim() || "No output produced"
                }, null, 2)
              }
            ]
          };
        } catch (err) {
          return {
            content: [
              {
                type: "text",
                text: JSON.stringify({
                  success: false,
                  error: err.message,
                  tip: "Ensure Godot executable path is specified or added to Windows PATH."
                }, null, 2)
              }
            ],
            isError: true
          };
        }
      }

      case "godot_live_editor_command": {
        const result = await sendCommandToEditor(args.command, args.payload || {});
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(result, null, 2)
            }
          ]
        };
      }

      default:
        throw new Error(`Unknown tool: ${name}`);
    }
  } catch (err) {
    return {
      content: [
        {
          type: "text",
          text: JSON.stringify({
            error: err.message,
            stack: err.stack
          }, null, 2)
        }
      ],
      isError: true
    };
  }
});

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("Godot MCP Server running on stdio transport.");
}

main().catch((err) => {
  console.error("Fatal error starting Godot MCP Server:", err);
  process.exit(1);
});
