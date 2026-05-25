extends CharacterBody2D
class_name Turtle

signal stopped_at_target

@onready var config: TonnetzConfig = Config.config

var turtle_down_color = Color.CHARTREUSE
var turtle_up_color = Color.GRAY


class TrailDot:
	extends Node2D

	var radius := 4.0
	var color := Color.WHITE

	func _draw() -> void:
		draw_circle(Vector2.ZERO, radius, color)


var actions: Array = []
var current_index := 0

var pen_down := true

@export var trail_dot_radius := 4.0
@export var trail_dot_spacing := 10.0
@export var trail_fade_duration := 2.0
@export var trail_fade_delay := 0.0

@onready var trail: Line2D = $Trail

var trail_dots: Array[TrailDot] = []
var last_dot_position := Vector2.INF

var start_pos := Vector2.ZERO
var target_pos := Vector2.ZERO

var stopped := true
var stop_at_next_target := false


func _ready() -> void:
	_create_player()

func _process(delta: float) -> void:
	if actions.size() < 2:
		return

	if stopped:
		return

	# last action has no next target
	if current_index >= actions.size() - 1:
		global_position = actions[-1]["anchor"].get_center()
		return

	var beat: float = CL.get_time_beat()

	var action = actions[current_index]
	var next_action = actions[current_index + 1]

	var start_beat: float = next_action["start_beat"]
	var duration: float = next_action["duration_beats"]

	if duration <= 0.0:
		duration = 0.001

	var t = (beat - start_beat) / duration
	t = clamp(t, 0.0, 1.0)

	var start_anchor = action["anchor"]
	var target_anchor = next_action["anchor"]

	start_pos = start_anchor.get_center()
	target_pos = target_anchor.get_center()

	global_position = start_pos.lerp(target_pos, t)

	_apply_pen_state(action["pen_status"])

	_update_trail()

	# move to next action
	if beat >= start_beat + duration:
		if stop_at_next_target:
			_stop_at_current_target()
			return

		current_index += 1

		# stop at end instead of looping
		if current_index >= actions.size() - 1:
			stopped = true
# ------------------------------------------------------------
# ACTION SYSTEM
# ------------------------------------------------------------

func set_actions(new_actions: Array, start_position: Vector2) -> void:
	actions = new_actions

	current_index = 0

	stopped = false
	stop_at_next_target = false

	if actions.is_empty():
		return

	global_position = start_position

	var first_anchor = actions[0]["anchor"]

	start_pos = first_anchor.get_center()
	target_pos = first_anchor.get_center()

	_apply_pen_state(actions[0]["pen_status"])

	_reset_trail(start_position)


func _apply_pen_state(state: bool) -> void:
	pen_down = state

	if pen_down:
		collision_layer = 1
		collision_mask = 0
		$Visuals/MeshInstance2D.modulate = turtle_down_color
	else:
		collision_layer = 0
		collision_mask = 0
		$Visuals/MeshInstance2D.modulate = turtle_up_color


# ------------------------------------------------------------
# STOP LOGIC
# ------------------------------------------------------------

func stop_after_current_target():
	if stopped or actions.is_empty():
		return

	stop_at_next_target = true


func clear_path(position: Vector2 = global_position) -> void:
	actions.clear()

	stopped = true
	stop_at_next_target = false

	current_index = 0

	start_pos = position
	target_pos = position

	global_position = position

	_apply_pen_state(true)

	_reset_trail(position)


func _stop_at_current_target() -> void:
	global_position = target_pos

	_update_trail()

	actions.clear()

	stopped = true
	stop_at_next_target = false

	stopped_at_target.emit()


# ------------------------------------------------------------
# TRAIL SYSTEM
# ------------------------------------------------------------

func _update_trail() -> void:
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

	tween.tween_property(
		dot,
		"modulate:a",
		0.0,
		trail_fade_duration
	)

	tween.tween_callback(
		Callable(dot, "queue_free")
	)


func _prune_trail_dots() -> void:
	trail_dots = trail_dots.filter(
		func(dot):
			return is_instance_valid(dot)
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
	sphere.height = config.player_radius * 2.0

	$Visuals/MeshInstance2D.mesh = sphere
	$Visuals/MeshInstance2D.modulate = turtle_down_color
	$Visuals/MeshInstance2D.z_index = 10

	trail.visible = false

	collision_layer = 1
	collision_mask = 0
