extends CharacterBody2D
class_name Turtle

@onready var config: TonnetzConfig = Config.config

@export var play_collision_audio := false

var turtle_down_color = Color.CHARTREUSE
var turtle_up_color = Color.GRAY


# ------------------------------------------------------------
# MOVEMENT
# ------------------------------------------------------------

var moving := false

var move_from := Vector2.ZERO
var move_to := Vector2.ZERO

var move_start_beat := 0.0
var move_duration := 1.0


# ------------------------------------------------------------
# PEN
# ------------------------------------------------------------

var pen_down := true
var trail_enabled := true


# ------------------------------------------------------------
# TRAIL
# ------------------------------------------------------------

class TrailDot:
	extends Node2D

	var radius := 4.0
	var color := Color.WHITE

	func _draw() -> void:
		draw_circle(Vector2.ZERO, radius, color)


@export var trail_dot_radius := 4.0
@export var trail_dot_spacing := 10.0
@export var trail_fade_duration := 2.0
@export var trail_fade_delay := 0.0

@onready var trail: Line2D = $Trail

var trail_dots: Array[TrailDot] = []

var last_dot_position := Vector2.INF


# ------------------------------------------------------------
# READY
# ------------------------------------------------------------

func _ready() -> void:
	
	_create_player()


# ------------------------------------------------------------
# PROCESS
# ------------------------------------------------------------

func _process(delta: float) -> void:

	if not moving:
		return

	var beat : float = CL.get_time_beat()

	var t := (
		(beat - move_start_beat)
		/ move_duration
	)

	t = clamp(t, 0.0, 1.0)

	global_position = move_from.lerp(
		move_to,
		t
	)

	if trail_enabled:
		_update_trail(global_position)

	if t >= 1.0:
		moving = false


# ------------------------------------------------------------
# TRANSITIONS
# ------------------------------------------------------------
func start_transition(
	current_event: Dictionary,
	next_event: Dictionary
) -> void:

	move_from = current_event["anchor"].get_center()

	move_to = next_event["anchor"].get_center()

	move_start_beat = current_event["start_beat"]

	move_duration = (
		next_event["start_beat"]
		- current_event["start_beat"]
	)

	if move_duration <= 0.0:
		move_duration = 0.001

	global_position = move_from

	_apply_pen_state(
		current_event["pen_status"]
	)

	trail_enabled = current_event.get("draw_trail", true)
	$Visuals.visible = trail_enabled

	if not trail_enabled:
		last_dot_position = Vector2.INF

	moving = true

func clear_path(start_position: Vector2 = global_position) -> void:
	moving = false
	trail_enabled = true
	$Visuals.visible = true
	global_position = start_position
	reset_trail(start_position)

func stop_after_current_target() -> void:
	moving = false
	$Visuals.visible = true

func pause_at_event(event: Dictionary) -> void:
	moving = false
	trail_enabled = true
	$Visuals.visible = true
	global_position = event["anchor"].get_center()
	last_dot_position = Vector2.INF

	_apply_pen_state(
		event.get("pen_status", true)
	)

func set_voice_color(color: Color) -> void:
	turtle_down_color = color
	turtle_up_color = color.darkened(0.55)

	if pen_down:
		$Visuals/MeshInstance2D.modulate = turtle_down_color
	else:
		$Visuals/MeshInstance2D.modulate = turtle_up_color

func should_play_node_audio() -> bool:
	return play_collision_audio and pen_down

func should_play_triangle_audio() -> bool:
	return play_collision_audio and pen_down


# ------------------------------------------------------------
# PEN
# ------------------------------------------------------------

func _apply_pen_state(state) -> void:

	pen_down = bool(state)

	if pen_down:
		collision_layer = 1

		$Visuals/MeshInstance2D.modulate = (
			turtle_down_color
		)
	else:
		collision_layer = 0

		$Visuals/MeshInstance2D.modulate = (
			turtle_up_color
		)


# ------------------------------------------------------------
# TRAIL
# ------------------------------------------------------------

func reset_trail(
	start_position: Vector2
) -> void:

	trail.clear_points()

	for dot in trail_dots:
		if is_instance_valid(dot):
			dot.queue_free()

	trail_dots.clear()

	last_dot_position = Vector2.INF

	_add_trail_dot(start_position)


func _update_trail(pos: Vector2) -> void:

	if last_dot_position == Vector2.INF:
		_add_trail_dot(pos)
		return

	if (
		last_dot_position.distance_to(pos)
		>= trail_dot_spacing
	):
		_add_trail_dot(pos)


func _add_trail_dot(
	dot_position: Vector2
) -> void:

	var dot = TrailDot.new()

	add_child(dot)

	dot.top_level = true

	dot.global_position = dot_position

	dot.radius = trail_dot_radius

	dot.color = config.trail_color

	dot.z_index = 5

	trail_dots.append(dot)

	last_dot_position = dot_position

	_fade_trail_dot(dot)


func _fade_trail_dot(
	dot: TrailDot
) -> void:

	var tween = dot.create_tween()

	if trail_fade_delay > 0.0:
		tween.tween_interval(
			trail_fade_delay
		)

	tween.tween_property(
		dot,
		"modulate:a",
		0.0,
		trail_fade_duration
	)

	tween.tween_callback(
		Callable(dot, "queue_free")
	)


# ------------------------------------------------------------
# PLAYER SETUP
# ------------------------------------------------------------

func _create_player():

	var shape = CircleShape2D.new()

	shape.radius = config.player_radius

	$CollisionShape2D.shape = shape

	var sphere = SphereMesh.new()

	sphere.radius = config.player_radius

	sphere.height = (
		config.player_radius * 2.0
	)

	$Visuals/MeshInstance2D.mesh = sphere

	$Visuals/MeshInstance2D.modulate = (
		turtle_down_color
	)

	$Visuals/MeshInstance2D.z_index = 10

	trail.visible = false

	collision_layer = 1
	collision_mask = 0
	$Visuals.visible = false
