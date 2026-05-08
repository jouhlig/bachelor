extends CharacterBody2D
class_name Turtle

signal stopped_at_target

class TrailDot:
	extends Node2D

	var radius := 4.0
	var color := Color.WHITE

	func _draw() -> void:
		draw_circle(Vector2.ZERO, radius, color)

@export var config: TonnetzConfig

var angle_triangles := 120.0
var step_distance := 100.0
var pen_down := true
@export var trail_dot_radius := 4.0
@export var trail_dot_spacing := 10.0
@export var trail_fade_duration := 2.0
@export var trail_fade_delay := 0.0

@onready var trail: Line2D = $Trail
var trail_dots: Array[TrailDot] = []
var last_dot_position := Vector2.INF

var path: Array[Vector2] = []

var current_pos := Vector2.ZERO
var dir := Vector2.RIGHT

var current_index := 0

var start_pos := Vector2.ZERO
var target_pos := Vector2.ZERO

var last_beat := -1

var stopped = true
var stop_at_next_target := false


func _ready() -> void:
	if not config:
		config = TonnetzConfig.new()

	_create_player()


func _process(delta: float) -> void:
	if path.is_empty():
		return

	var progress: float = CL.get_progress()
	var current_beat : int= CL.get_current_beat()

	if current_beat != last_beat and not stopped:
		last_beat = current_beat
		if stop_at_next_target:
			_stop_at_current_target()
			return
		_advance_path()

	var t : float= clamp(progress, 0.0, 1.0)

	global_position = start_pos.lerp(target_pos, t)

	#draw trail for path
	_update_trail()


func build_path(instructions: String, start_position: Vector2) -> void:
	path.clear()
	stopped = false
	stop_at_next_target = false
	current_pos = start_position
	dir = Vector2.RIGHT

	path.append(current_pos)

	for c in instructions:
		match c:
			"s":
				current_pos += dir * step_distance
				path.append(current_pos)

			"l":
				rotate_left()

			"r":
				rotate_right()

	current_index = 0
	last_beat = CL.get_current_beat()

	if path.size() >= 2:
		start_pos = start_position
		target_pos = start_position

	global_position = start_position

	_reset_trail(start_position)
	for i in path:
		print(i)


func rotate_left():
	dir = dir.rotated(deg_to_rad(angle_triangles))


func rotate_right():
	dir = dir.rotated(deg_to_rad(-angle_triangles))

func put_pen_up() -> void:
	pen_down = false
	collision_layer = 0

func put_pen_down(start_position: Vector2 = global_position) -> void:
	pen_down = true
	last_dot_position = Vector2.INF
	_add_trail_dot(start_position)
	collision_layer = 1


func stop_after_current_target():
	if stopped or path.is_empty():
		return
	stop_at_next_target = true

func clear_path(position: Vector2 = global_position) -> void:
	path.clear()
	stopped = true
	stop_at_next_target = false
	current_index = 0
	start_pos = position
	target_pos = position
	global_position = position
	pen_down = true
	_reset_trail(position)

func _stop_at_current_target() -> void:
	global_position = target_pos
	_update_trail()
	path.clear()
	stopped = true
	stop_at_next_target = false
	stopped_at_target.emit()
	
#called on every new beat
func _advance_path():
	#print("Advanced from ", current_index, " at pos: ", path[current_index], " to ", current_index+1, " at ", path[current_index+1])
	
	#if only 1 node is inside path, we have nowhere to go
	if path.size() < 2:
		return
	

	current_index += 1
	
	#if we are out of bounds, travel back to the first point without drawing.
	if current_index >= path.size():
		put_pen_up()
		start_pos = path[path.size() - 1]
		target_pos = path[0]
		current_index = 0
		return

	start_pos = path[current_index - 1]
	target_pos = path[current_index]
	put_pen_down(start_pos)


func _update_trail() -> void:
	if not pen_down:
		return

	if last_dot_position == Vector2.INF:
		_add_trail_dot(global_position)
		return

	if last_dot_position.distance_to(global_position) >= trail_dot_spacing:
		_add_trail_dot(global_position)


func _reset_trail(start_position: Vector2) -> void:
	trail.clear_points()
	for dot in trail_dots.duplicate():
		if is_instance_valid(dot):
			dot.queue_free()
	trail_dots.clear()
	last_dot_position = Vector2.INF
	_add_trail_dot(start_position)

func _add_trail_dot(dot_position: Vector2) -> void:
	var dot = TrailDot.new()
	add_child(dot)
	dot.top_level = true
	dot.global_position = dot_position
	dot.radius = trail_dot_radius
	dot.color = config.trail_color
	dot.z_index = 5
	dot.tree_exited.connect(_prune_trail_dots)
	trail_dots.append(dot)
	last_dot_position = dot_position
	_fade_trail_dot(dot)

func _fade_trail_dot(dot: TrailDot) -> void:
	var tween = dot.create_tween()
	if trail_fade_delay > 0.0:
		tween.tween_interval(trail_fade_delay)
	tween.tween_property(dot, "modulate:a", 0.0, trail_fade_duration)
	tween.tween_callback(Callable(dot, "queue_free"))

func _prune_trail_dots() -> void:
	trail_dots = trail_dots.filter(func(dot):
		return is_instance_valid(dot)
	)


func _create_player():
	var shape = CircleShape2D.new()
	shape.radius = config.player_radius
	$CollisionShape2D.shape = shape

	var sphere = SphereMesh.new()
	sphere.radius = config.player_radius
	sphere.height = config.player_radius * 2.0

	$Visuals/MeshInstance2D.mesh = sphere
	$Visuals/MeshInstance2D.modulate = config.player_color
	$Visuals/MeshInstance2D.z_index = 10

	trail.visible = false

	collision_layer = 1
	collision_mask = 0
