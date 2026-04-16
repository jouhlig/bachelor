extends CharacterBody2D

@export var config: TonnetzConfig
@export var speed := 5.0
@onready var trail: Line2D = $Trail

var actions: Array = []
var index := 0
var pos := Vector2.ZERO

func _ready() -> void:
	if not config:
		config = TonnetzConfig.new()

	# Collision
	var shape = CircleShape2D.new()
	shape.radius = config.player_radius
	$CollisionShape2D.shape = shape

	# Visual (ONLY ONCE, NICHT DUPLIZIEREN!)
	var sphere = SphereMesh.new()
	sphere.radius = config.player_radius
	sphere.height = config.player_radius * 2.0

	$Visuals/MeshInstance2D.mesh = sphere
	$Visuals/MeshInstance2D.modulate = config.player_color
	$Visuals/MeshInstance2D.z_index = 10

	trail.top_level = true
	trail.width = max(config.player_radius * 0.4, 2.0)
	trail.default_color = Color.WHITE
	trail.antialiased = true
	trail.z_index = 5

	# Collision layers
	collision_layer = 1
	collision_mask = 0  

func set_actions(new_actions: Array, start_position: Vector2 = global_position) -> void:
	actions = []
	index = 0
	global_position = start_position
	trail.clear_points()
	trail.add_point(start_position)

	if new_actions.is_empty():
		return

	var offset = start_position - new_actions[0]["from"]

	for action in new_actions:
		actions.append({
			"from": action["from"] + offset,
			"to": action["to"] + offset
		})

func _process(delta: float) -> void:
	if actions.is_empty():
		return

	var target = actions[index]["to"]

	global_position = global_position.lerp(target, speed * delta)
	_update_trail()

	if global_position.distance_to(target) < 2.0:
		index += 1

		if index >= actions.size():
			index = 0  # loop

func _on_area_entered(area):
	if area.has_method("on_player_enter"):
		area.on_player_enter(self)

func _update_trail() -> void:
	if trail.points.is_empty():
		trail.add_point(global_position)
		return

	if trail.points[-1].distance_to(global_position) >= 4.0:
		trail.add_point(global_position)
