extends CharacterBody2D
class_name Turtle

@onready var config: TonnetzConfig = Config.config

@export var play_collision_audio := false

var turtle_down_color = Color.CHARTREUSE
var base_visual_scale := Vector2.ONE


# ------------------------------------------------------------
# MOVEMENT
# ------------------------------------------------------------

var moving := false
var hidden_during_transition := false
var stay_hidden_after_transition := false
var hide_after_transition := false
var flashing_during_transition := false
var flash_tween: Tween = null

var move_from := Vector2.ZERO
var move_to := Vector2.ZERO

var move_start_beat := 0.0
var move_duration := 1.0


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

	if hidden_during_transition or flashing_during_transition:
		global_position = move_to
	else:
		global_position = move_from.lerp(
			move_to,
			t
		)

	if not hidden_during_transition and not flashing_during_transition and trail_enabled:
		_update_trail(global_position)

	if t >= 1.0:
		moving = false

		if hidden_during_transition:
			hidden_during_transition = false
			$Visuals.visible = not stay_hidden_after_transition
			collision_layer = 0 if stay_hidden_after_transition else 1
			stay_hidden_after_transition = false

		if flashing_during_transition:
			flashing_during_transition = false
			collision_layer = 1
			_reset_flash_visual()

		if hide_after_transition:
			$Visuals.visible = false
			collision_layer = 0
			hide_after_transition = false


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

	_stop_flash_tween()
	global_position = move_from

	trail_enabled = current_event.get("draw_trail", true)
	hidden_during_transition = bool(current_event.get("hide_turtle_during_transition", false))
	flashing_during_transition = bool(current_event.get("flash_turtle_during_transition", false))
	stay_hidden_after_transition = bool(current_event.get("stay_hidden_after_transition", false))
	hide_after_transition = bool(current_event.get("hide_after_transition", false))
	$Visuals.visible = not hidden_during_transition
	collision_layer = 1

	if hidden_during_transition:
		global_position = move_to
		collision_layer = 0
	elif flashing_during_transition:
		global_position = move_to
		collision_layer = 0
		$Visuals.visible = true
		_start_flash_tween()

	if not trail_enabled:
		last_dot_position = Vector2.INF
	elif current_event.get("skip_initial_trail_dot", false):
		last_dot_position = move_from

	moving = true

func clear_path(
	start_position: Vector2 = global_position,
	add_start_dot: bool = true,
	show_visual: bool = true
) -> void:
	moving = false
	trail_enabled = true
	$Visuals.visible = show_visual
	collision_layer = 1 if show_visual else 0
	global_position = start_position
	reset_trail(start_position, add_start_dot)

func hide_turtle() -> void:
	moving = false
	trail_enabled = false
	collision_layer = 0
	$Visuals.visible = false
	reset_trail(global_position, false)

func stop_after_current_target() -> void:
	moving = false
	$Visuals.visible = true
	collision_layer = 1

func pause_at_event(event: Dictionary) -> void:
	moving = false
	trail_enabled = true
	$Visuals.visible = not bool(event.get("hide_turtle_at_event", false))
	collision_layer = 1 if $Visuals.visible else 0
	global_position = event["anchor"].get_center()
	last_dot_position = Vector2.INF

func set_voice_color(color: Color) -> void:
	turtle_down_color = color

	_apply_visual_color()

func set_visual_radius_offset(offset_px: float) -> void:
	var base_radius : float= max(1.0, config.player_radius)
	var scale_factor : float = (base_radius + max(0.0, offset_px)) / base_radius
	$Visuals.scale = base_visual_scale * scale_factor

func should_play_node_audio() -> bool:
	return play_collision_audio

func should_play_triangle_audio() -> bool:
	return play_collision_audio

func _apply_visual_color() -> void:
	$Visuals/MeshInstance2D.modulate = turtle_down_color

func _start_flash_tween() -> void:
	var mesh: MeshInstance2D = $Visuals/MeshInstance2D
	var base_color: Color = mesh.modulate
	var flash_color := base_color.lightened(0.55)
	flash_color.a = 1.0
	var dim_color := base_color
	dim_color.a = 0.35
	mesh.modulate = flash_color

	flash_tween = create_tween()
	flash_tween.tween_property(mesh, "modulate", dim_color, 0.08)
	flash_tween.tween_property(mesh, "modulate", base_color, 0.12)

func _stop_flash_tween() -> void:
	if flash_tween:
		flash_tween.kill()
		flash_tween = null

func _reset_flash_visual() -> void:
	_stop_flash_tween()
	$Visuals/MeshInstance2D.modulate.a = 1.0


# ------------------------------------------------------------
# TRAIL
# ------------------------------------------------------------

func reset_trail(
	start_position: Vector2,
	add_start_dot: bool = true
) -> void:

	trail.clear_points()

	for dot in trail_dots:
		if is_instance_valid(dot):
			dot.queue_free()

	trail_dots.clear()

	last_dot_position = Vector2.INF

	if add_start_dot:
		_add_trail_dot(start_position)


func _update_trail(pos: Vector2) -> void:

	if last_dot_position == Vector2.INF:
		_add_trail_dot(pos)
		return

	if (
		last_dot_position.distance_to(pos)
		>= config.trail_dot_spacing
	):
		_add_trail_dot(pos)


func _add_trail_dot(
	dot_position: Vector2
) -> void:

	var dot = TrailDot.new()

	add_child(dot)

	dot.top_level = true

	dot.global_position = dot_position

	dot.radius = config.trail_dot_radius

	dot.color = config.trail_color

	dot.z_index = 5

	trail_dots.append(dot)

	last_dot_position = dot_position

	_fade_trail_dot(dot)


func _fade_trail_dot(
	dot: TrailDot
) -> void:

	var tween = dot.create_tween()

	if config.trail_fade_delay > 0.0:
		tween.tween_interval(
			config.trail_fade_delay
		)

	tween.tween_property(
		dot,
		"modulate:a",
		0.0,
		config.trail_fade_duration
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
