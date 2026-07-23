extends CharacterBody2D
class_name Turtle

@onready var config: TonnetzConfig = Config.config

@export var play_collision_audio := false

const TRAIL_MEET_GROUP := "trail_turtles"
const TRAIL_MEET_EPSILON := 2.5
const TRAIL_BLOOM_DURATION := 0.8
const TRAIL_BLOOM_RADIUS := 52.0

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
var active_trail_point_index := -1
var active_trail_segment_start := Vector2.ZERO


# ------------------------------------------------------------
# TRAIL
# ------------------------------------------------------------

class TrailBloom:
	extends Node2D

	var color := Color.WHITE
	var age := 0.0
	var duration := 0.55
	var max_radius := 34.0

	func _process(delta: float) -> void:
		age += delta

		if age >= duration:
			queue_free()
			return

		queue_redraw()

	func _draw() -> void:
		var t: float = clamp(age / duration, 0.0, 1.0)
		var radius: float = lerp(4.0, max_radius, t)
		var inner_radius: float = lerp(3.0, max_radius * 0.5, t)
		var draw_color: Color = color
		draw_circle(Vector2.ZERO, radius, draw_color, false, 5.0, true)
		draw_circle(Vector2.ZERO, inner_radius, draw_color, false, 3.0, true)

@onready var trail: Line2D = $Trail

var trail_segments: Array[Dictionary] = []
var trail_bloom_keys := {}
var trail_lines: Array[Line2D] = []
var active_trail: Line2D = null
var trail_break_pending := false


# ------------------------------------------------------------
# READY
# ------------------------------------------------------------

func _ready() -> void:
	add_to_group(TRAIL_MEET_GROUP)
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
		if trail_enabled and active_trail_point_index >= 0:
			active_trail.set_point_position(active_trail_point_index, move_to)
			_finish_trail_segment(active_trail_segment_start, move_to)
			active_trail_point_index = -1

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
	for index in range(1, trail_lines.size()):
		if is_instance_valid(trail_lines[index]):
			trail_lines[index].queue_free()

	trail_lines = [trail]
	active_trail = trail
	trail_segments.clear()
	trail_bloom_keys.clear()
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

	active_trail.set_point_position(active_trail_point_index, pos)

func _start_trail_segment(start_position: Vector2) -> void:
	if active_trail == null:
		active_trail = trail

	if trail_break_pending and active_trail.get_point_count() > 0:
		active_trail = _create_trail_line()

	trail_break_pending = false

	if active_trail.get_point_count() == 0:
		active_trail.add_point(start_position)

	active_trail.add_point(start_position)
	active_trail_point_index = active_trail.get_point_count() - 1
	active_trail_segment_start = start_position

func _finish_trail_segment(from_position: Vector2, to_position: Vector2) -> void:
	if from_position.distance_to(to_position) <= TRAIL_MEET_EPSILON:
		return

	for meet_point in _get_trail_meet_points(from_position, to_position):
		_add_trail_bloom(meet_point)

	trail_segments.append({
		"from": from_position,
		"to": to_position
	})

func _get_trail_meet_points(from_position: Vector2, to_position: Vector2) -> Array[Vector2]:
	var points: Array[Vector2] = []

	for turtle in get_tree().get_nodes_in_group(TRAIL_MEET_GROUP):
		if turtle == self or not is_instance_valid(turtle):
			continue

		if not turtle.has_method("get_trail_segments"):
			continue

		for segment in turtle.get_trail_segments():
			var hit := _get_segment_intersection(
				from_position,
				to_position,
				segment["from"],
				segment["to"]
			)

			if bool(hit.get("hit", false)):
				var point: Vector2 = hit["point"]

				if not _has_nearby_meet_point(points, point):
					points.append(point)

	return points

func get_trail_segments() -> Array[Dictionary]:
	return trail_segments

func _get_segment_intersection(
	a: Vector2,
	b: Vector2,
	c: Vector2,
	d: Vector2
) -> Dictionary:
	var r := b - a
	var s := d - c
	var denominator := r.cross(s)

	if abs(denominator) <= 0.001:
		return _get_parallel_segment_meet(a, b, c, d)

	var t := (c - a).cross(s) / denominator
	var u := (c - a).cross(r) / denominator

	if t < 0.0 or t > 1.0 or u < 0.0 or u > 1.0:
		return {"hit": false}

	return {
		"hit": true,
		"point": a + r * t
	}

func _get_parallel_segment_meet(
	a: Vector2,
	b: Vector2,
	c: Vector2,
	d: Vector2
) -> Dictionary:
	var best_point := Vector2.ZERO
	var best_progress := -INF

	for point in [a, b, c, d]:
		if not _point_is_on_segment(point, a, b):
			continue

		if not _point_is_on_segment(point, c, d):
			continue

		var progress := _get_segment_progress(a, b, point)

		if progress > best_progress:
			best_progress = progress
			best_point = point

	if best_progress >= 0.0:
		return {
			"hit": true,
			"point": best_point
		}

	return {"hit": false}

func _point_is_on_segment(point: Vector2, a: Vector2, b: Vector2) -> bool:
	var segment: Vector2 = b - a
	var segment_length_squared: float = segment.length_squared()

	if segment_length_squared <= 0.001:
		return point.distance_to(a) <= TRAIL_MEET_EPSILON

	var t: float = clamp((point - a).dot(segment) / segment_length_squared, 0.0, 1.0)
	var closest: Vector2 = a + segment * t
	return point.distance_to(closest) <= TRAIL_MEET_EPSILON

func _has_nearby_meet_point(points: Array[Vector2], point: Vector2) -> bool:
	for existing_point in points:
		if existing_point.distance_to(point) <= TRAIL_MEET_EPSILON:
			return true

	return false

func _get_segment_progress(from_position: Vector2, to_position: Vector2, point: Vector2) -> float:
	var segment: Vector2 = to_position - from_position
	var segment_length_squared: float = segment.length_squared()

	if segment_length_squared <= 0.001:
		return 0.0

	return clamp(
		(point - from_position).dot(segment) / segment_length_squared,
		0.0,
		1.0
	)

func _add_trail_bloom(point: Vector2) -> void:
	var key := "%d:%d" % [
		int(round(point.x / TRAIL_MEET_EPSILON)),
		int(round(point.y / TRAIL_MEET_EPSILON))
	]

	if trail_bloom_keys.has(key):
		return

	trail_bloom_keys[key] = true

	var bloom := TrailBloom.new()
	bloom.top_level = true
	bloom.global_position = point
	bloom.color = turtle_down_color
	bloom.duration = TRAIL_BLOOM_DURATION
	bloom.max_radius = TRAIL_BLOOM_RADIUS
	bloom.z_index = 8
	add_child(bloom)


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

	trail.top_level = true
	trail.global_position = Vector2.ZERO
	_configure_trail_line(trail)
	trail_lines = [trail]
	active_trail = trail

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
	trail_lines.append(line)
	return line

func _configure_trail_line(line: Line2D) -> void:
	line.width = max(2.0, config.trail_dot_radius)
	line.antialiased = true
	line.z_index = 5
	line.visible = true
	line.default_color = _get_trail_color()

func _apply_trail_color() -> void:
	for line in trail_lines:
		if is_instance_valid(line):
			line.default_color = _get_trail_color()

func _get_trail_color() -> Color:
	var color: Color = turtle_down_color
	color.a = 0.85
	return color
