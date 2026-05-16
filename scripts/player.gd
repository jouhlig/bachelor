extends CharacterBody2D

@onready var config: TonnetzConfig = Config.config
var beat_time: float
@onready var trail: Line2D = $Trail
var actions: Array = []
var index := 0
var stop_at_next_target := false

var start_pos: Vector2
var target_pos: Vector2

var last_beat:= -1
var progress_beats := 0.0

func _ready() -> void:
	if not config:
		config = TonnetzConfig.new()

	_create_player()
	
func _process(delta: float) -> void:

	if actions.is_empty():
		return
	var progress = CL.get_progress()
	var current_beat = CL.get_current_beat()
	
	while last_beat < current_beat:
		last_beat += 1
		_on_beat_reached()
	var t = clamp(progress, 0.0, 1.0)
	global_position = start_pos.lerp(target_pos, t)

	_update_trail()
	
func _on_beat_reached():
	if last_beat == 0 and index == 0:
		_start_next_action()
		return

	if stop_at_next_target:
		actions = []
		index = 0
		stop_at_next_target = false
		return

	index += 1

	if index >= actions.size():
		index = 0

	_start_next_action()
	
func _start_next_action():
	var action = actions[index]

	start_pos = action["from_pos"]
	target_pos = action["to_pos"]

	progress_beats = 0.0
	
	
func set_actions(new_actions: Array, start_position: Vector2 = global_position) -> void:
	actions = []
	index = 0
	stop_at_next_target = false
	global_position = start_position
	_reset_trail(start_position)

	if new_actions.is_empty():
		return

	var offset = start_position - new_actions[0]["from_pos"]

	for action in new_actions:
		actions.append({
			
			"from_pos": action["from_pos"] + offset,
			"to_pos": action["to_pos"] + offset,
			
			"duration": action["duration_beats"],
		})

func stop_after_current_target() -> void:
	if actions.is_empty():
		return
	stop_at_next_target = true


func _on_area_entered(area):
	if area.has_method("on_player_enter"):
		area.on_player_enter(self)

func _update_trail() -> void:
	if trail.points.is_empty():
		trail.add_point(global_position)
		return

	if trail.points[-1].distance_to(global_position) >= 4.0:
		trail.add_point(global_position)

func _reset_trail(start_position: Vector2) -> void:
	trail.clear_points()
	trail.add_point(start_position)

func _create_player():
	# Collision
	var shape = CircleShape2D.new()
	shape.radius = config.player_radius
	$CollisionShape2D.shape = shape

	# Visual 
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
