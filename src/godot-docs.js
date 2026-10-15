/**
 * Godot Engine 4.x Reference, Best Practices, and Syntax Rules for LLMs.
 */

export const GODOT4_SYNTAX_RULES = [
  {
    rule: "Use @export instead of export()",
    godot3: "export(int) var speed = 100",
    godot4: "@export var speed: int = 100",
  },
  {
    rule: "Use @onready instead of onready",
    godot3: "onready var sprite = $Sprite",
    godot4: "@onready var sprite: Sprite2D = $Sprite2D",
  },
  {
    rule: "Use CharacterBody2D / CharacterBody3D instead of KinematicBody",
    godot3: "extends KinematicBody2D",
    godot4: "extends CharacterBody2D",
  },
  {
    rule: "move_and_slide() in Godot 4 takes NO arguments and uses velocity property",
    godot3: "velocity = move_and_slide(velocity, Vector2.UP)",
    godot4: "move_and_slide() # reads and writes self.velocity automatically",
  },
  {
    rule: "Use await instead of yield",
    godot3: "yield(get_tree().create_timer(1.0), 'timeout')",
    godot4: "await get_tree().create_timer(1.0).timeout",
  },
  {
    rule: "Signal connection syntax using Callable",
    godot3: "button.connect('pressed', self, '_on_button_pressed')",
    godot4: "button.pressed.connect(_on_button_pressed)",
  },
  {
    rule: "2D nodes now have '2D' suffix",
    godot3: "Sprite, Position2D, VisibilityNotifier2D",
    godot4: "Sprite2D, Marker2D, VisibleOnScreenNotifier2D",
  },
  {
    rule: "Use Vector2i / Vector3i for integer coordinates (like tilemap cells)",
    godot3: "tilemap.get_cellv(Vector2(x, y))",
    godot4: "tilemap.get_cell_source_id(0, Vector2i(x, y))",
  },
  {
    rule: "Instantiating scenes uses .instantiate() not .instance()",
    godot3: "var obj = scene.instance()",
    godot4: "var obj = scene.instantiate()",
  },
  {
    rule: "Random numbers use randf_range / randi_range",
    godot3: "rand_range(1.0, 5.0)",
    godot4: "randf_range(1.0, 5.0) / randi_range(1, 10)",
  }
];

export const COMMON_NODE_DOCS = {
  "CharacterBody2D": {
    category: "2D Physics",
    description: "2D physics body specialized for characters moved via player input or AI code.",
    inherits: "CollisionObject2D > Node2D > CanvasItem > Node",
    essential_properties: [
      "velocity: Vector2 - Linear velocity in pixels per second.",
      "up_direction: Vector2 - Vector pointing up for floor detection (default: Vector2(0, -1)).",
      "floor_stop_on_slope: bool - Stop sliding down slopes.",
      "motion_mode: MotionMode - MOTION_MODE_GROUNDED (gravity/floors) or MOTION_MODE_FLOATING (space, top-down)."
    ],
    essential_methods: [
      "move_and_slide() -> bool: Moves the body based on velocity.",
      "is_on_floor() -> bool: Returns true if body collided with floor on last move.",
      "is_on_wall() -> bool: Returns true if body collided with wall.",
      "is_on_ceiling() -> bool: Returns true if body collided with ceiling."
    ],
    sample_code: `extends CharacterBody2D

@export var speed: float = 300.0
@export var jump_velocity: float = -400.0
var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")

func _physics_process(delta: float) -> void:
    if not is_on_floor():
        velocity.y += gravity * delta

    if Input.is_action_just_pressed("ui_accept") and is_on_floor():
        velocity.y = jump_velocity

    var direction: float = Input.get_axis("ui_left", "ui_right")
    if direction:
        velocity.x = direction * speed
    else:
        velocity.x = move_toward(velocity.x, 0, speed)

    move_and_slide()`
  },
  "CharacterBody3D": {
    category: "3D Physics",
    description: "3D physics body specialized for characters controlled by script.",
    inherits: "CollisionObject3D > Node3D > Node",
    essential_properties: [
      "velocity: Vector3 - Linear velocity in meters per second.",
      "up_direction: Vector3 - Vector pointing up for floor detection (default: Vector3.UP).",
      "motion_mode: MotionMode - MOTION_MODE_GROUNDED or MOTION_MODE_FLOATING."
    ],
    essential_methods: [
      "move_and_slide() -> bool: Moves the body based on velocity.",
      "is_on_floor() -> bool: Returns true if body is on floor.",
      "is_on_wall() -> bool: Returns true if body collided with a wall."
    ],
    sample_code: `extends CharacterBody3D

@export var speed: float = 5.0
@export var jump_velocity: float = 4.5
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

func _physics_process(delta: float) -> void:
    if not is_on_floor():
        velocity.y -= gravity * delta

    if Input.is_action_just_pressed("ui_accept") and is_on_floor():
        velocity.y = jump_velocity

    var input_dir: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
    var direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
    if direction:
        velocity.x = direction.x * speed
        velocity.z = direction.z * speed
    else:
        velocity.x = move_toward(velocity.x, 0, speed)
        velocity.z = move_toward(velocity.z, 0, speed)

    move_and_slide()`
  },
  "Area2D": {
    category: "2D Physics / Triggers",
    description: "Region of 2D space that detects 2D collision objects entering or exiting.",
    inherits: "CollisionObject2D > Node2D > CanvasItem > Node",
    signals: [
      "body_entered(body: Node2D)",
      "body_exited(body: Node2D)",
      "area_entered(area: Area2D)",
      "area_exited(area: Area2D)"
    ],
    sample_code: `extends Area2D

func _ready() -> void:
    body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
    if body.is_in_group("player"):
        print("Player entered trigger!")
        queue_free()`
  },
  "Camera2D": {
    category: "2D Viewport",
    description: "Camera node for 2D scenes with zoom, limits, and smoothing.",
    inherits: "Node2D > CanvasItem > Node",
    essential_properties: [
      "zoom: Vector2 - Camera zoom level (default: Vector2(1, 1)).",
      "position_smoothing_enabled: bool - Smooth camera motion toward target.",
      "limit_left, limit_right, limit_top, limit_bottom: int - Boundaries in pixels."
    ]
  },
  "AnimationPlayer": {
    category: "Animation",
    description: "Plays back animations containing position, rotation, properties, and method tracks.",
    inherits: "Node",
    essential_methods: [
      "play(name: StringName = &\"\", custom_blend: float = -1, custom_speed: float = 1.0)",
      "stop(keep_state: bool = false)",
      "has_animation(name: StringName) -> bool"
    ],
    signals: [
      "animation_finished(anim_name: StringName)"
    ]
  }
};

/**
 * Validate GDScript code for common Godot 3 vs 4 pitfalls.
 * Returns an array of suggestions / warnings.
 */
export function validateGDScript(code) {
  const issues = [];
  const lines = code.split("\n");

  lines.forEach((line, index) => {
    const lineNum = index + 1;
    const trimmed = line.trim();

    if (/\bexport\s*\([^)]*\)\s*var\b/.test(trimmed)) {
      issues.push({
        line: lineNum,
        type: "warning",
        message: "Found Godot 3 syntax `export(...) var`. In Godot 4 use `@export var name: Type`."
      });
    }

    if (/\bonready\s+var\b/.test(trimmed) && !trimmed.startsWith("@onready")) {
      issues.push({
        line: lineNum,
        type: "warning",
        message: "Found Godot 3 syntax `onready var`. In Godot 4 use `@onready var`."
      });
    }

    if (/\byield\s*\(/.test(trimmed)) {
      issues.push({
        line: lineNum,
        type: "warning",
        message: "Found `yield()`. In Godot 4 use `await <signal_or_coroutine>`."
      });
    }

    if (/\bextends\s+KinematicBody2D\b/.test(trimmed)) {
      issues.push({
        line: lineNum,
        type: "warning",
        message: "KinematicBody2D was renamed to CharacterBody2D in Godot 4."
      });
    }

    if (/\bextends\s+KinematicBody\b/.test(trimmed)) {
      issues.push({
        line: lineNum,
        type: "warning",
        message: "KinematicBody was renamed to CharacterBody3D in Godot 4."
      });
    }

    if (/\.instance\s*\(\s*\)/.test(trimmed)) {
      issues.push({
        line: lineNum,
        type: "warning",
        message: "`.instance()` was renamed to `.instantiate()` in Godot 4."
      });
    }

    if (/\bmove_and_slide\s*\([^)]+\)/.test(trimmed)) {
      issues.push({
        line: lineNum,
        type: "warning",
        message: "`move_and_slide()` takes no arguments in Godot 4. Assign to `velocity` beforehand instead."
      });
    }
  });

  return issues;
}
