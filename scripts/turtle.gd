extends Node2D
class_name Turtle

# draws the turtle path

@onready var config: TonnetzConfig = Config.config

var turtle_down_color := Color.CHARTREUSE


# ------------------------------------------------------------
# MOVEMENT
# ------------------------------------------------------------

var moving := false
var wrapping_visual := false

var move_from := Vector2.ZERO
var move_to := Vector2.ZERO
var facing_direction := Vector2.RIGHT
var turtle_alpha := 1.0
var wrap_entry_trail_started := false

var move_start_beat := 0.0
var move_duration := 1.0


var trail_enabled := true
var active_trail_point_index := -1


# ------------------------------------------------------------
# TRAIL
# ------------------------------------------------------------

@onready var trail: Line2D = $Trail

var trail_lines: Array[Line2D] = []
var active_trail: Line2D = null
var trail_break_pending := false
var trail_prune_elapsed := 0.0


# ------------------------------------------------------------
# READY
# ------------------------------------------------------------

func _ready() -> void:
	z_index = 30
	_setup_trail()

func _draw() -> void:
	var direction := facing_direction.normalized()
	var side := direction.orthogonal()
	var tip := direction * config.turtle_arrow_length
	var tail := -direction * config.turtle_arrow_length * 0.45
	var half_width := config.turtle_arrow_width * 0.5
	var arrow_color := turtle_down_color
	arrow_color.a *= turtle_alpha
	var points := PackedVector2Array([
		tip,
		tail + side * half_width,
		tail - side * half_width
	])

	draw_colored_polygon(points, arrow_color)
	draw_polyline(
		PackedVector2Array([points[0], points[1], points[2], points[0]]),
		arrow_color,
		1.5,
		true
	)

# ------------------------------------------------------------
# PROCESS
# ------------------------------------------------------------

func _process(delta: float) -> void:
	trail_prune_elapsed += delta

	if trail_prune_elapsed >= config.turtle_trail_prune_update_interval:
		trail_prune_elapsed = 0.0
		_prune_trail_history()

	if wrapping_visual:
		_update_wrap_visual()
		return

	if not moving:
		return

	var beat : float = CL.get_time_beat()

	var t := (
		(beat - move_start_beat)
		/ move_duration
	)

	t = clamp(t, 0.0, 1.0)

	global_position = move_from.lerp(move_to, t)

	if trail_enabled:
		_update_trail(global_position)

	if t >= 1.0:
		moving = false
		if trail_enabled and active_trail_point_index >= 0:
			_set_active_trail_point(active_trail_point_index, move_to)
			active_trail_point_index = -1

func _update_wrap_visual() -> void:
	var beat : float = CL.get_time_beat()
	var t: float = clamp((beat - move_start_beat) / move_duration, 0.0, 1.0)
	var direction: Vector2 = facing_direction.normalized()
	var wrap_distance: float = config.turtle_wrap_visual_distance

	if t < 0.5:
		var local_t: float = t * 2.0
		global_position = move_from.lerp(move_from + direction * wrap_distance, local_t)
		turtle_alpha = 1.0 - local_t
		_update_trail(global_position)
	else:
		var local_t: float = (t - 0.5) * 2.0
		var entry_start := move_to - direction * wrap_distance
		if not wrap_entry_trail_started:
			trail_break_pending = true
			_start_trail_segment(entry_start)
			active_trail.gradient = _create_wrap_entry_trail_gradient()
			wrap_entry_trail_started = true

		global_position = entry_start.lerp(move_to, local_t)
		turtle_alpha = local_t
		_update_trail(global_position)

	queue_redraw()

	if t >= 1.0:
		wrapping_visual = false
		turtle_alpha = 1.0
		global_position = move_to
		active_trail_point_index = -1
		trail_break_pending = true
		wrap_entry_trail_started = false
		queue_redraw()


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

	trail_enabled = current_event.get("draw_trail", true)
	var uses_wrap_visual := (
		not trail_enabled
		or bool(current_event.get("hide_turtle_during_transition", false))
	)

	if uses_wrap_visual:
		_start_trail_segment(move_from)
		active_trail.gradient = _create_wrap_exit_trail_gradient()
		moving = false
		wrapping_visual = true
		wrap_entry_trail_started = false
		queue_redraw()
		return

	var movement_direction := move_to - move_from
	if movement_direction.length_squared() > 0.001:
		facing_direction = movement_direction.normalized()

	global_position = move_from

	if bool(current_event.get("reset_trail_before_transition", false)):
		reset_trail(move_from)

	_start_trail_segment(move_from)
	moving = true
	wrapping_visual = false
	turtle_alpha = 1.0
	wrap_entry_trail_started = false
	queue_redraw()

func clear_path(
	start_position: Vector2 = global_position,
	add_start_dot: bool = true
) -> void:
	moving = false
	wrapping_visual = false
	trail_enabled = true
	turtle_alpha = 1.0
	wrap_entry_trail_started = false
	global_position = start_position
	reset_trail(start_position, add_start_dot)
	queue_redraw()

func stop_after_current_target() -> void:
	moving = false
	wrapping_visual = false
	turtle_alpha = 1.0
	wrap_entry_trail_started = false

func pause_at_event(event: Dictionary) -> void:
	moving = false
	wrapping_visual = false
	trail_enabled = true
	turtle_alpha = 1.0
	wrap_entry_trail_started = false
	global_position = event["anchor"].get_center()
	active_trail_point_index = -1
	queue_redraw()

func set_voice_color(color: Color) -> void:
	turtle_down_color = color
	_apply_trail_color()
	queue_redraw()


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


func _update_trail(pos: Vector2) -> void:
	if (
		active_trail == null
		or active_trail_point_index < 0
		or active_trail_point_index >= active_trail.get_point_count()
	):
		_start_trail_segment(pos)
		return

	_set_active_trail_point(active_trail_point_index, pos)

func _start_trail_segment(start_position: Vector2) -> void:
	if active_trail == null:
		active_trail = trail

	if trail_break_pending and active_trail.get_point_count() > 0:
		active_trail = _create_trail_line()
		trail_lines.append(active_trail)

	trail_break_pending = false

	if active_trail.get_point_count() == 0:
		active_trail.add_point(start_position)

	active_trail.add_point(start_position)
	active_trail_point_index = active_trail.get_point_count() - 1

func _set_active_trail_point(index: int, point: Vector2) -> void:
	active_trail.set_point_position(index, point)

func _prune_trail_history() -> void:
	var surplus_length := _get_trail_length() - _get_max_trail_length()
	var max_prune_length: float = (
		float(config.offset)
		* max(0.01, config.turtle_trail_prune_max_step_fraction)
	)
	surplus_length = min(surplus_length, max_prune_length)

	if surplus_length <= 0.0:
		return

	for index in range(trail_lines.size() - 1, -1, -1):
		if not is_instance_valid(trail_lines[index]):
			trail_lines.remove_at(index)

	while surplus_length > 0.0 and not trail_lines.is_empty():
		var line := trail_lines[0]
		if not is_instance_valid(line):
			trail_lines.remove_at(0)
			continue

		surplus_length = _trim_trail_line_start(line, surplus_length)

		if line.get_point_count() > 1:
			return

		if line == active_trail:
			if active_trail_point_index >= line.get_point_count():
				active_trail_point_index = line.get_point_count() - 1
			return

		trail_lines.remove_at(0)
		if line == trail:
			line.clear_points()
		else:
			line.queue_free()

func _trim_trail_line_start(line: Line2D, length_to_remove: float) -> float:
	while length_to_remove > 0.0 and line.get_point_count() > 1:
		var start := line.get_point_position(0)
		var next := line.get_point_position(1)
		var segment_length := start.distance_to(next)

		if segment_length <= 0.001:
			line.remove_point(0)
			if line == active_trail:
				active_trail_point_index -= 1
			continue

		if segment_length <= length_to_remove:
			line.remove_point(0)
			length_to_remove -= segment_length
			if line == active_trail:
				active_trail_point_index -= 1
			continue

		var new_start := start.lerp(next, length_to_remove / segment_length)
		line.set_point_position(0, new_start)
		return 0.0

	return length_to_remove

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
	return max(1.0, float(config.turtle_trail_max_steps)) * float(config.offset)

# ------------------------------------------------------------
# TRAIL SETUP
# ------------------------------------------------------------

func _setup_trail() -> void:
	trail.top_level = true
	trail.global_position = Vector2.ZERO
	_configure_trail_line(trail)
	trail_lines = [trail]
	active_trail = trail

func _create_trail_line() -> Line2D:
	var line := Line2D.new()
	line.name = "Trail"
	line.top_level = true
	line.global_position = Vector2.ZERO
	_configure_trail_line(line)
	add_child(line)
	return line

func _configure_trail_line(line: Line2D) -> void:
	line.modulate.a = 1.0
	line.width = max(2.0, config.trail_width)
	line.antialiased = true
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.z_index = 20
	line.visible = true
	line.default_color = _get_trail_color()
	line.gradient = null

func _apply_trail_color() -> void:
	for line in trail_lines:
		if is_instance_valid(line):
			line.default_color = _get_trail_color()

func _get_trail_color() -> Color:
	var color: Color = turtle_down_color
	color.a = 1.0
	return color

func _create_wrap_exit_trail_gradient() -> Gradient:
	var visible_color := _get_trail_color()
	var invisible_color := visible_color
	invisible_color.a = 0.0
	var fade_fraction: float = clamp(config.turtle_wrap_fade_fraction, 0.01, 0.45)

	var gradient := Gradient.new()
	gradient.set_color(0, visible_color)
	gradient.set_color(1, invisible_color)
	gradient.add_point(1.0 - fade_fraction, visible_color)
	return gradient

func _create_wrap_entry_trail_gradient() -> Gradient:
	var visible_color := _get_trail_color()
	var invisible_color := visible_color
	invisible_color.a = 0.0
	var fade_fraction: float = clamp(config.turtle_wrap_fade_fraction, 0.01, 0.45)

	var gradient := Gradient.new()
	gradient.set_color(0, invisible_color)
	gradient.set_color(1, visible_color)
	gradient.add_point(fade_fraction, visible_color)
	return gradient
