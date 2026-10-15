import fs from "fs/promises";
import path from "path";

/**
 * Helper to parse project.godot into a structured object
 */
export async function parseProjectGodot(projectPath) {
  const filePath = path.join(projectPath, "project.godot");
  try {
    const content = await fs.readFile(filePath, "utf-8");
    const sections = {};
    let currentSection = "default";
    sections[currentSection] = {};

    const lines = content.split("\n");
    for (const rawLine of lines) {
      const line = rawLine.trim();
      if (!line || line.startsWith(";")) continue;

      if (line.startsWith("[") && line.endsWith("]")) {
        currentSection = line.slice(1, -1);
        if (!sections[currentSection]) sections[currentSection] = {};
        continue;
      }

      const eqIdx = line.indexOf("=");
      if (eqIdx !== -1) {
        const key = line.slice(0, eqIdx).trim();
        let val = line.slice(eqIdx + 1).trim();
        // Remove surrounding quotes if any
        if (val.startsWith('"') && val.endsWith('"')) {
          val = val.slice(1, -1);
        }
        sections[currentSection][key] = val;
      }
    }

    return {
      exists: true,
      path: filePath,
      projectName: sections["application"]?.["config/name"] || path.basename(projectPath),
      mainScene: sections["application"]?.["run/main_scene"] || null,
      configVersion: sections["default"]?.["config_version"] || 5,
      features: sections["application"]?.["config/features"] || null,
      rawSections: sections
    };
  } catch (err) {
    return {
      exists: false,
      error: err.message
    };
  }
}

/**
 * Scan directory recursively for Godot files (.tscn, .gd, .tres, .gdshader, etc.)
 */
export async function scanProjectFiles(dir, baseDir = dir) {
  const results = {
    scenes: [],
    scripts: [],
    resources: [],
    shaders: [],
    others: []
  };

  async function walk(current) {
    let entries;
    try {
      entries = await fs.readdir(current, { withFileTypes: true });
    } catch {
      return;
    }

    for (const entry of entries) {
      // Ignore .git, .godot folder (cache), node_modules
      if (entry.name === ".git" || entry.name === ".godot" || entry.name === "node_modules") {
        continue;
      }

      const fullPath = path.join(current, entry.name);
      const relPath = "res://" + path.relative(baseDir, fullPath).replace(/\\/g, "/");

      if (entry.isDirectory()) {
        await walk(fullPath);
      } else {
        const ext = path.extname(entry.name).toLowerCase();
        const fileInfo = {
          name: entry.name,
          resPath: relPath,
          fullPath: fullPath,
          ext: ext
        };

        if (ext === ".tscn") results.scenes.push(fileInfo);
        else if (ext === ".gd") results.scripts.push(fileInfo);
        else if (ext === ".tres") results.resources.push(fileInfo);
        else if (ext === ".gdshader") results.shaders.push(fileInfo);
        else results.others.push(fileInfo);
      }
    }
  }

  await walk(dir);
  return results;
}

/**
 * Parse a .tscn file into structured nodes and resources
 */
export async function parseTscn(filePath) {
  const content = await fs.readFile(filePath, "utf-8");
  const lines = content.split("\n");

  const headerMatch = content.match(/\[gd_scene\s+([^\]]+)\]/);
  const extResources = [];
  const nodes = [];
  let currentBlock = null;

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim();
    if (!line) continue;

    if (line.startsWith("[ext_resource")) {
      const match = line.match(/\[ext_resource\s+type="([^"]+)"\s+path="([^"]+)"\s+id="([^"]+)"\]/);
      if (match) {
        extResources.push({ type: match[1], path: match[2], id: match[3] });
      }
      continue;
    }

    if (line.startsWith("[node")) {
      // e.g. [node name="Player" type="CharacterBody2D"] or [node name="Sprite" type="Sprite2D" parent="."]
      const nameMatch = line.match(/name="([^"]+)"/);
      const typeMatch = line.match(/type="([^"]+)"/);
      const parentMatch = line.match(/parent="([^"]+)"/);
      const instanceMatch = line.match(/instance=ExtResource\("([^"]+)"\)/);

      const nodeObj = {
        name: nameMatch ? nameMatch[1] : "Unnamed",
        type: typeMatch ? typeMatch[1] : (instanceMatch ? "Instance" : "Node"),
        parent: parentMatch ? parentMatch[1] : null, // null means root node
        instanceId: instanceMatch ? instanceMatch[1] : null,
        properties: {}
      };
      nodes.push(nodeObj);
      currentBlock = nodeObj;
      continue;
    }

    // Properties inside current node block
    if (currentBlock && line.includes("=")) {
      const eqIdx = line.indexOf("=");
      const key = line.slice(0, eqIdx).trim();
      const val = line.slice(eqIdx + 1).trim();
      currentBlock.properties[key] = val;
    }
  }

  return {
    filePath,
    header: headerMatch ? headerMatch[0] : "[gd_scene format=3]",
    extResources,
    nodes,
    rootNode: nodes.find(n => n.parent === null) || nodes[0] || null
  };
}

/**
 * Generate a valid Godot 4 .tscn file content
 */
export function generateTscn({ rootName, rootType, scriptResPath, children = [] }) {
  const lines = [];
  const extResources = [];

  let scriptExtId = null;
  if (scriptResPath) {
    scriptExtId = "1_script";
    extResources.push({
      type: "Script",
      path: scriptResPath,
      id: scriptExtId
    });
  }

  // Header
  const loadSteps = extResources.length > 0 ? ` load_steps=${extResources.length + 1}` : "";
  lines.push(`[gd_scene${loadSteps} format=3]`);
  lines.push("");

  // Ext resources
  for (const res of extResources) {
    lines.push(`[ext_resource type="${res.type}" path="${res.path}" id="${res.id}"]`);
  }
  if (extResources.length > 0) lines.push("");

  // Root Node
  lines.push(`[node name="${rootName}" type="${rootType}"]`);
  if (scriptExtId) {
    lines.push(`script = ExtResource("${scriptExtId}")`);
  }
  lines.push("");

  // Children
  for (const child of children) {
    const parentPath = child.parent || ".";
    lines.push(`[node name="${child.name}" type="${child.type}" parent="${parentPath}"]`);
    if (child.properties) {
      for (const [k, v] of Object.entries(child.properties)) {
        lines.push(`${k} = ${v}`);
      }
    }
    lines.push("");
  }

  return lines.join("\n");
}
