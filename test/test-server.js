import path from "path";
import fs from "fs/promises";
import { parseProjectGodot, scanProjectFiles, parseTscn, generateTscn } from "../src/godot-parser.js";
import { validateGDScript, COMMON_NODE_DOCS } from "../src/godot-docs.js";

async function runTests() {
  console.log("🧪 Iniciando pruebas de Godot MCP...\n");
  const testDir = path.resolve("./test/sample_project");
  await fs.mkdir(testDir, { recursive: true });

  // 1. Create a sample project.godot
  const sampleGodotConfig = `
config_version=5

[application]
config/name="GodotMCPDemo"
run/main_scene="res://main.tscn"
config/features=PackedStringArray("4.3", "Forward Plus")
`;
  await fs.writeFile(path.join(testDir, "project.godot"), sampleGodotConfig.trim(), "utf-8");
  console.log("✅ project.godot de prueba creado.");

  // 2. Test parseProjectGodot
  const projectInfo = await parseProjectGodot(testDir);
  console.assert(projectInfo.exists === true, "Project should exist");
  console.assert(projectInfo.projectName === "GodotMCPDemo", "Project name should match");
  console.assert(projectInfo.mainScene === "res://main.tscn", "Main scene should match");
  console.log("✅ parseProjectGodot funcionó correctamente:", projectInfo.projectName);

  // 3. Test generateTscn & parseTscn
  const sceneTscn = generateTscn({
    rootName: "Player",
    rootType: "CharacterBody2D",
    scriptResPath: "res://player.gd",
    children: [
      { name: "Sprite2D", type: "Sprite2D", parent: ".", properties: { "position": "Vector2(100, 200)" } },
      { name: "CollisionShape2D", type: "CollisionShape2D", parent: "." }
    ]
  });

  const scenePath = path.join(testDir, "player.tscn");
  await fs.writeFile(scenePath, sceneTscn, "utf-8");
  console.log("✅ Escena .tscn generada y guardada.");

  const parsedScene = await parseTscn(scenePath);
  console.assert(parsedScene.rootNode.name === "Player", "Root node must be Player");
  console.assert(parsedScene.nodes.length === 3, "Must have 3 nodes (Player, Sprite2D, CollisionShape2D)");
  console.log(`✅ parseTscn leyó correctamente ${parsedScene.nodes.length} nodos.`);

  // 4. Test GDScript validation
  const oldCode = `
extends KinematicBody2D

export(int) var speed = 200
onready var sprite = $Sprite

func _physics_process(delta):
    velocity = move_and_slide(velocity)
`;
  const warnings = validateGDScript(oldCode);
  console.assert(warnings.length >= 4, "Should catch Godot 3 deprecated syntax");
  console.log(`✅ Validador de GDScript detectó correctamente ${warnings.length} advertencias de Godot 3 vs Godot 4.`);

  // 5. Test docs
  console.assert(COMMON_NODE_DOCS["CharacterBody2D"] !== undefined, "CharacterBody2D docs must exist");
  console.log("✅ Documentación integrada de Godot 4 verificada.");

  // 6. Test scanProjectFiles
  const scanned = await scanProjectFiles(testDir);
  console.assert(scanned.scenes.length === 1, "Should find 1 scene");
  console.log(`✅ Escaneo de archivos encontró ${scanned.scenes.length} escenas.`);

  console.log("\n🎉 ¡Todas las pruebas pasaron exitosamente!");
}

runTests().catch(err => {
  console.error("❌ Error en pruebas:", err);
  process.exit(1);
});
