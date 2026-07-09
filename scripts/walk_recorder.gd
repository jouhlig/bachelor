class_name WalkRecorder
extends RefCounted

const HIGHLIGHT_LAYER_Z_INDEX := 50
const PREVIEW_LINE_Z_INDEX := 49
const PREVIEW_TURTLE_RADIUS_OFFSET := 4.0
const PREVIEW_LINE_WIDTH := 4.0

var config: TonnetzConfig
var builder: TonnetzBuilder
var tonnetz_world: Node2D
var turtle_scene: PackedScene

var recording := false
var anchor_mode := ""
var current_anchor = null
var events: Array = []
var selected_duration := 1.0
var valid_next_anchors: Array = []
var highlight_layer: Node2D = null
var preview_turtle: Turtle = null
var preview_line: Line2D = null
var recording_color := Color.WHITE

func _init(
	new_config: TonnetzConfig,
	new_builder: TonnetzBuilder,
	new_tonnetz_world: Node2D,
	new_turtle_scene: PackedScene
) -> void:
	config = new_config
	builder = new_builder
	tonnetz_world = new_tonnetz_world
	turtle_scene = new_turtle_scene

func start(color: Color) -> void:
	cancel()
	recording = true
	recording_color = color
	highlight_layer = Node2D.new()
	highlight_layer.name = "WalkRecorderHighlights"
	highlight_layer.z_index = HIGHLIGHT_LAYER_Z_INDEX
	tonnetz_world.add_child(highlight_layer)

func cancel() -> void:
	recording = false
	anchor_mode = ""
	current_anchor = null
	events.clear()
	valid_next_anchors.clear()
	_clear_highlights()

	if is_instance_valid(highlight_layer):
		highlight_layer.queue_free()

	highlight_layer = null

	if is_instance_valid(preview_turtle):
		preview_turtle.queue_free()

	preview_turtle = null

	if is_instance_valid(preview_line):
		preview_line.queue_free()

	preview_line = null
	recording_color = Color.WHITE

func set_duration(duration_beats: float) -> void:
	selected_duration = max(config.recorded_walk_min_step_duration, duration_beats)

func undo_step() -> void:
	if not recording or events.is_empty():
		return

	events.pop_back()

	if preview_line != null and preview_line.get_point_count() > 0:
		preview_line.remove_point(preview_line.get_point_count() - 1)

	if events.is_empty():
		anchor_mode = ""
		current_anchor = null
		_clear_highlights()

		if is_instance_valid(preview_turtle):
			preview_turtle.queue_free()

		preview_turtle = null
		return

	current_anchor = events[-1]["anchor"]

	if is_instance_valid(preview_turtle):
		preview_turtle.global_position = current_anchor.get_center()

	_update_valid_next_anchors()

func handle_click(click_pos: Vector2) -> void:
	if not recording:
		return

	if events.is_empty():
		var start_anchor = builder.get_nearest_spawn_anchor(click_pos)

		if start_anchor == null:
			return

		anchor_mode = "node" if start_anchor is TonnetzNode else "triangle"
		current_anchor = start_anchor
		_append_anchor(start_anchor)
		_create_preview(start_anchor)
		_update_valid_next_anchors()
		return

	var next_anchor = _get_clicked_valid_anchor(click_pos)

	if next_anchor == null:
		return

	var previous_event = events[-1]
	previous_event["duration_beats"] = selected_duration
	var step_key = _get_neighbor_key_between(previous_event["anchor"], next_anchor)

	if _is_wrapped_step(previous_event["anchor"], step_key, next_anchor):
		previous_event["hide_turtle_during_transition"] = true
		previous_event["draw_trail"] = false

	events[-1] = previous_event
	_append_anchor(next_anchor)
	current_anchor = next_anchor

	if is_instance_valid(preview_turtle):
		preview_turtle.global_position = next_anchor.get_center()

	if is_instance_valid(preview_line):
		preview_line.add_point(next_anchor.get_center())

	_update_valid_next_anchors()

func build_score() -> Array:
	if not has_recorded_step():
		return []

	return events.duplicate(true)

func get_origin():
	return events[0]["anchor"] if not events.is_empty() else null

func get_anchor_mode() -> String:
	return anchor_mode

func get_color() -> Color:
	return recording_color

func has_recorded_step() -> bool:
	return get_step_count() > 0

func get_step_count() -> int:
	return max(0, events.size() - 1)

func is_recording() -> bool:
	return recording

func _append_anchor(anchor) -> void:
	events.append({
		"anchor": anchor,
		"duration_beats": selected_duration,
		"draw_trail": true
	})

func _create_preview(start_anchor) -> void:
	preview_turtle = turtle_scene.instantiate() as Turtle

	if preview_turtle != null:
		tonnetz_world.add_child(preview_turtle)
		preview_turtle.global_position = start_anchor.get_center()
		preview_turtle.clear_path(start_anchor.get_center())
		preview_turtle.set_voice_color(recording_color)
		preview_turtle.set_visual_radius_offset(PREVIEW_TURTLE_RADIUS_OFFSET)

	preview_line = Line2D.new()
	preview_line.name = "WalkRecorderPreviewLine"
	preview_line.width = PREVIEW_LINE_WIDTH
	preview_line.default_color = _get_color_with_alpha(config.walk_preview_alpha)
	preview_line.antialiased = true
	preview_line.z_index = PREVIEW_LINE_Z_INDEX
	tonnetz_world.add_child(preview_line)
	preview_line.add_point(start_anchor.get_center())

func _update_valid_next_anchors() -> void:
	valid_next_anchors.clear()
	_clear_highlights()

	if not current_anchor:
		return

	for next_anchor in _get_next_anchor_candidates(current_anchor):
		if anchor_mode == "node" and not (next_anchor is TonnetzNode):
			continue

		if anchor_mode == "triangle" and not (next_anchor is TriangleArea):
			continue

		if valid_next_anchors.has(next_anchor):
			continue

		valid_next_anchors.append(next_anchor)
		_add_highlight(next_anchor)

func _get_next_anchor_candidates(anchor) -> Array:
	var candidates := []

	if anchor == null:
		return candidates

	for next_anchor in anchor.neighbors.values():
		candidates.append(next_anchor)

	if anchor is TonnetzNode:
		for direction in TonnetzBuilder.AXIAL_DIRECTIONS:
			var wrapped_neighbor = builder.get_wrapped_node_neighbor(anchor, direction)

			if wrapped_neighbor and not candidates.has(wrapped_neighbor):
				candidates.append(wrapped_neighbor)

	if anchor is TriangleArea:
		for edge_index in range(3):
			var wrapped_neighbor = builder.get_wrapped_triangle_neighbor(anchor, edge_index)

			if wrapped_neighbor and not candidates.has(wrapped_neighbor):
				candidates.append(wrapped_neighbor)

	return candidates

func _get_clicked_valid_anchor(click_pos: Vector2):
	var nearest = null
	var nearest_distance := INF

	for anchor in valid_next_anchors:
		var distance = click_pos.distance_squared_to(anchor.get_center())

		if distance < nearest_distance:
			nearest = anchor
			nearest_distance = distance

	if not nearest:
		return null

	if nearest_distance > _get_click_radius_squared(nearest):
		return null

	return nearest

func _get_click_radius_squared(anchor) -> float:
	var radius = config.offset * config.anchor_click_radius_factor

	if anchor is TonnetzNode:
		radius = max(config.note_radius * config.node_click_radius_multiplier, radius * 0.5)

	return radius * radius

func _add_highlight(anchor) -> void:
	if not is_instance_valid(highlight_layer):
		return

	var highlight := AnchorHighlight.new()
	highlight.position = anchor.get_center()
	highlight.configure(
		max(1.0, config.note_radius),
		_get_color_with_alpha(config.walk_highlight_alpha),
		0.0,
		0.0
	)
	highlight_layer.add_child(highlight)

func _get_color_with_alpha(alpha: float) -> Color:
	return Color(
		recording_color.r,
		recording_color.g,
		recording_color.b,
		alpha
	)

func _clear_highlights() -> void:
	if not is_instance_valid(highlight_layer):
		return

	for child in highlight_layer.get_children():
		child.queue_free()

func _is_wrapped_step(current_anchor, step_key, next_anchor) -> bool:
	return step_key != null and next_anchor and current_anchor.neighbors.get(step_key) != next_anchor

func _get_neighbor_key_between(current_anchor, next_anchor):
	for key in current_anchor.neighbors.keys():
		if current_anchor.neighbors[key] == next_anchor:
			return key

	if current_anchor is TonnetzNode:
		for direction in TonnetzBuilder.AXIAL_DIRECTIONS:
			if builder.get_wrapped_node_neighbor(current_anchor, direction) == next_anchor:
				return direction

	if current_anchor is TriangleArea:
		for edge_index in range(3):
			if builder.get_wrapped_triangle_neighbor(current_anchor, edge_index) == next_anchor:
				return edge_index

	return null
