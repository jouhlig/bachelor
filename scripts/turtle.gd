extends CharacterBody2D
class_name Turtle

const TurtleTrailCanvasScript := preload("res://scripts/turtle_trail_canvas.gd")

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
var snap_after_transition := false
var snap_after_transition_position := Vector2.ZERO
var break_trail_after_transition := false

var move_start_beat := 0.0
var move_duration := 1.0


var trail_enabled := true
var active_trail_point_index := -1


# ------------------------------------------------------------
# TRAIL
# ------------------------------------------------------------

@onready var trail: Line2D = $Trail

var trail_lines: Array[Line2D] = []
var trail_canvas: Node2D
var active_trail: Line2D = null
var trail_break_pending := false
var trail_redraw_queued := false
var trail_prune_elapsed := 0.0


# ------------------------------------------------------------
# READY
# ------------------------------------------------------------

func _ready() -> void:
	_create_player()


# ------------------------------------------------------------
# PROCESS
# ------------------------------------------------------------

func _process(delta: float) -> void:
	trail_prune_elapsed += delta

	if trail_prune_elapsed >= config.turtle_trail_prune_update_interval:
		trail_prune_elapsed = 0.0
		_prune_trail_history()

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
		global_position = move_from.lerp(move_to, _get_varied_move_progress(t))

	if not hidden_during_transition and not flashing_during_transition and trail_enabled:
		_update_trail(global_position)

	if t >= 1.0:
		moving = false
		if trail_enabled and active_trail_point_index >= 0:
			_set_active_trail_point(active_trail_point_index, move_to)
			active_trail_point_index = -1
			if break_trail_after_transition:
				trail_break_pending = true

		if snap_after_transition:
			global_position = snap_after_transition_position
			snap_after_transition = false

		break_trail_after_transition = false

		if hidden_during_transition:
			hidden_during_transition = false
			_set_visual_visible(not stay_hidden_after_transition)
			collision_layer = 0 if stay_hidden_after_transition else 1
			stay_hidden_after_transition = false

		if flashing_during_transition:
			flashing_during_transition = false
			collision_layer = 1
			_reset_flash_visual()

		if hide_after_transition:
			_set_visual_visible(false)
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

	var anchor_target: Vector2 = next_event["anchor"].get_center()
	move_to = current_event.get("wrap_transition_target", anchor_target)
	snap_after_transition = current_event.has("wrap_transition_target")
	snap_after_transition_position = anchor_target
	break_trail_after_transition = bool(current_event.get("break_trail_after_transition", false))

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
	_set_visual_visible(not hidden_during_transition)
	collision_layer = 1

	if hidden_during_transition:
		global_position = move_to
		collision_layer = 0
	elif flashing_during_transition:
		global_position = move_to
		collision_layer = 0
		_set_visual_visible(true)
		_start_flash_tween()

	if bool(current_event.get("reset_trail_before_transition", false)):
		reset_trail(move_from)

	if trail_enabled and not hidden_during_transition and not flashing_during_transition:
		_start_trail_segment(move_from)
	else:
		active_trail_point_index = -1
		trail_break_pending = true

	moving = true

func clear_path(
	start_position: Vector2 = global_position,
	add_start_dot: bool = true,
	show_visual: bool = true
) -> void:
	moving = false
	trail_enabled = true
	_set_visual_visible(show_visual)
	collision_layer = 1 if show_visual else 0
	global_position = start_position
	reset_trail(start_position, add_start_dot)

func hide_turtle() -> void:
	moving = false
	trail_enabled = false
	collision_layer = 0
	_set_visual_visible(false)
	reset_trail(global_position, false)

func stop_after_current_target() -> void:
	moving = false
	_set_visual_visible(true)
	collision_layer = 1

func pause_at_event(event: Dictionary) -> void:
	moving = false
	trail_enabled = true
	_set_visual_visible(not bool(event.get("hide_turtle_at_event", false)))
	collision_layer = 1 if $Visuals.visible else 0
	global_position = event["anchor"].get_center()
	active_trail_point_index = -1

func set_voice_color(color: Color) -> void:
	turtle_down_color = color

	_apply_visual_color()
	_apply_trail_color()

func set_visual_radius_offset(offset_px: float) -> void:
	var base_radius : float= max(1.0, config.player_radius)
	var scale_factor : float = (base_radius + max(0.0, offset_px)) / base_radius
	$Visuals.scale = base_visual_scale * scale_factor

func should_play_node_audio() -> bool:
	return play_collision_audio

func should_play_triangle_audio() -> bool:
	return play_collision_audio

func _set_visual_visible(_visible: bool) -> void:
	$Visuals.visible = false

func _get_varied_move_progress(t: float) -> float:
	var wave: float = sin(t * TAU + turtle_down_color.h * TAU + config.turtle_speed_variation_phase)
	var envelope: float = sin(t * PI)
	var varied_t: float = t + wave * envelope * config.turtle_speed_variation
	return clamp(varied_t, 0.0, 1.0)

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

	if is_instance_valid(trail):
		trail.clear_points()

	for line in trail_lines:
		if is_instance_valid(line) and line != trail:
			line.queue_free()

	trail_lines = [trail]
	active_trail = trail
	active_trail_point_index = -1
	trail_break_pending = false

	if add_start_dot:
		active_trail.add_point(start_position)

	_queue_trail_redraw()


func _update_trail(pos: Vector2) -> void:
	if (
		active_trail == null
		or active_trail_point_index < 0
		or active_trail_point_index >= active_trail.get_point_count()
	):
		_start_trail_segment(pos)
		return

	_set_active_trail_point(active_trail_point_index, pos)
	_queue_trail_redraw()

func _start_trail_segment(start_position: Vector2) -> void:
	if active_trail == null:
		active_trail = trail

	if trail_break_pending and active_trail.get_point_count() > 0:
		active_trail = _create_trail_line()
		trail_lines.append(active_trail)
		_queue_trail_redraw()

	trail_break_pending = false

	if active_trail.get_point_count() == 0:
		active_trail.add_point(start_position)

	active_trail.add_point(start_position)
	active_trail_point_index = active_trail.get_point_count() - 1
	_queue_trail_redraw()

func _set_active_trail_point(index: int, point: Vector2) -> void:
	active_trail.set_point_position(index, point)

func _prune_trail_history() -> void:
	var surplus_length := _get_trail_length() - _get_max_trail_length()

	if surplus_length <= 0.0:
		return

	for index in range(trail_lines.size() - 1, -1, -1):
		var line := trail_lines[index]

		if not is_instance_valid(line):
			trail_lines.remove_at(index)
			_queue_trail_redraw()
			return

	for index in range(trail_lines.size()):
		var line := trail_lines[index]

		if not is_instance_valid(line):
			trail_lines.remove_at(index)
			_queue_trail_redraw()
			return

		if line == active_trail and active_trail_point_index >= 0:
			return

		var line_length := _get_trail_line_length(line)

		if line_length > surplus_length:
			return

		trail_lines.remove_at(index)
		if line == trail:
			line.clear_points()
		else:
			line.queue_free()
		_queue_trail_redraw()
		return

func _get_trail_length() -> float:
	var length := 0.0

	for line in trail_lines:
		if is_instance_valid(line):
			length += _get_trail_line_length(line)

	return length

func _get_trail_line_length(line: Line2D) -> float:
	var length := 0.0

	for point_index in range(1, line.get_point_count()):
		length += line.get_point_position(point_index - 1).distance_to(
			line.get_point_position(point_index)
		)

	return length

func _get_max_trail_length() -> float:
	return max(1.0, float(config.turtle_trail_max_points)) * float(config.offset)

func _queue_trail_redraw() -> void:
	if trail_redraw_queued:
		return

	trail_redraw_queued = true
	call_deferred("_flush_trail_redraw")

func _flush_trail_redraw() -> void:
	trail_redraw_queued = false

	if trail_canvas:
		trail_canvas.queue_redraw()

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
	$Visuals/MeshInstance2D.visible = false

	trail.top_level = true
	trail.global_position = Vector2.ZERO
	_configure_trail_line(trail)
	trail_lines = [trail]
	active_trail = trail
	trail_canvas = TurtleTrailCanvasScript.new()
	trail_canvas.name = "TurtleTrailCanvas"
	trail_canvas.source = self
	add_child(trail_canvas)

	collision_layer = 1
	collision_mask = 0
	$Visuals.visible = false

func _create_trail_line() -> Line2D:
	var line := Line2D.new()
	line.name = "Trail"
	line.top_level = true
	line.global_position = Vector2.ZERO
	_configure_trail_line(line)
	add_child(line)
	return line

func _configure_trail_line(line: Line2D) -> void:
	line.width = max(2.0, config.trail_dot_radius)
	line.antialiased = true
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.z_index = 20
	line.visible = false
	line.default_color = _get_trail_color()

func _apply_trail_color() -> void:
	for line in trail_lines:
		if is_instance_valid(line):
			line.default_color = _get_trail_color()

	_queue_trail_redraw()

func _get_trail_color() -> Color:
	var color: Color = turtle_down_color
	color.a = 1.0
	return color
