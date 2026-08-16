class_name WalkRecorder
extends RefCounted

#records a user walk on the Tonnetz

var config: TonnetzConfig
var builder: TonnetzBuilder
var tonnetz_world: Node2D

var recording := false
var current_anchor = null
var events: Array = []
var selected_duration := 1.0
var valid_next_anchors: Array = []
var highlight_layer: Node2D = null
var preview_line: Line2D = null
var recording_color := Color.WHITE
var selected_node: TonnetzNode = null

func _init(
	new_config: TonnetzConfig,
	new_builder: TonnetzBuilder,
	new_tonnetz_world: Node2D
) -> void:
	config = new_config
	builder = new_builder
	tonnetz_world = new_tonnetz_world

func start(color: Color) -> void:
	cancel()
	recording = true
	recording_color = color
	highlight_layer = Node2D.new()
	highlight_layer.name = "WalkRecorderHighlights"
	highlight_layer.z_index = config.walk_highlight_z_index
	tonnetz_world.add_child(highlight_layer)

func cancel() -> void:
	recording = false
	current_anchor = null
	events.clear()
	valid_next_anchors.clear()
	_clear_selected_node()
	_clear_highlights()

	if is_instance_valid(highlight_layer):
		highlight_layer.queue_free()

	highlight_layer = null

	if is_instance_valid(preview_line):
		preview_line.queue_free()

	preview_line = null
	recording_color = Color.WHITE

func finish() -> void:
	recording = false
	current_anchor = null
	valid_next_anchors.clear()
	_clear_selected_node()
	_clear_highlights()

	if is_instance_valid(highlight_layer):
		highlight_layer.queue_free()

	highlight_layer = null

func set_duration(duration_beats: float) -> void:
	selected_duration = max(config.recorded_walk_min_step_duration, duration_beats)

func undo_step() -> void:
	if not recording or events.is_empty():
		return

	events.pop_back()

	if preview_line != null and preview_line.get_point_count() > 0:
		preview_line.remove_point(preview_line.get_point_count() - 1)

	if events.is_empty():
		current_anchor = null
		_clear_selected_node()
		_clear_highlights()
		return

	current_anchor = events[-1]["anchor"]
	_set_selected_anchor(current_anchor)

	_update_valid_next_anchors()

func handle_click(click_pos: Vector2):
	if not recording:
		return null

	if events.is_empty():
		var start_anchor = builder.get_nearest_spawn_anchor(click_pos)

		if start_anchor == null:
			return null

		current_anchor = start_anchor
		_set_selected_anchor(current_anchor)
		_append_anchor(start_anchor)
		_create_preview_line(start_anchor)
		_update_valid_next_anchors()
		return start_anchor

	var next_anchor = _get_clicked_valid_anchor(click_pos)

	if next_anchor == null:
		return null

	var previous_event = events[-1]
	previous_event["duration_beats"] = selected_duration

	events[-1] = previous_event
	_append_anchor(next_anchor)
	current_anchor = next_anchor
	_set_selected_anchor(current_anchor)

	if is_instance_valid(preview_line):
		preview_line.add_point(next_anchor.get_center())

	_update_valid_next_anchors()
	return next_anchor

func build_score() -> Array:
	if not has_recorded_step():
		return []

	return events.duplicate(true)

func get_origin():
	return events[0]["anchor"] if not events.is_empty() else null

func get_color() -> Color:
	return recording_color

func has_recorded_step() -> bool:
	return events.size() > 1

func is_recording() -> bool:
	return recording

func _append_anchor(anchor) -> void:
	events.append({
		"anchor": anchor,
		"duration_beats": selected_duration,
		"draw_trail": true
	})

func _create_preview_line(start_anchor) -> void:
	preview_line = Line2D.new()
	preview_line.name = "WalkRecorderPreviewLine"
	preview_line.width = config.walk_preview_line_width
	preview_line.default_color = Color.BLACK
	preview_line.antialiased = false
	preview_line.z_index = config.walk_preview_line_z_index
	tonnetz_world.add_child(preview_line)
	preview_line.add_point(start_anchor.get_center())

func _update_valid_next_anchors() -> void:
	valid_next_anchors.clear()
	_clear_highlights()

	if not current_anchor:
		return

	for next_anchor in _get_next_anchor_candidates(current_anchor):
		if current_anchor is TonnetzNode and not (next_anchor is TonnetzNode):
			continue

		if current_anchor is TonnetzTriangle and not (next_anchor is TonnetzTriangle):
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

	var highlight := Node2D.new()
	var radius: float = max(1.0, config.note_radius + config.outline_width + 3.0)
	highlight.position = anchor.get_center()
	highlight.draw.connect(
		func():
			highlight.draw_circle(Vector2.ZERO, radius, Color.BLACK, false, config.line_width, true)
	)
	highlight_layer.add_child(highlight)
	highlight.queue_redraw()

func _clear_highlights() -> void:
	if not is_instance_valid(highlight_layer):
		return

	for child in highlight_layer.get_children():
		child.queue_free()

func _set_selected_anchor(anchor) -> void:
	_clear_selected_node()

	if anchor is TonnetzNode:
		selected_node = anchor
		selected_node.set_selected(true)

func _clear_selected_node() -> void:
	if is_instance_valid(selected_node):
		selected_node.set_selected(false)

	selected_node = null

func _build_random_walk(length: int, start_anchors: Array) -> Array[Dictionary]:
	var random_walk: Array[Dictionary] = []

	if start_anchors.is_empty() or config.random_walk_durations.is_empty():
		return random_walk

	var current_anchor = start_anchors.pick_random()
	var random_duration := float(config.random_walk_durations.pick_random())
	random_walk.append({
		"anchor": current_anchor,
		"duration_beats": random_duration
	})

	for i in range(length - 1):
		if current_anchor == null:
			break

		var next_anchors: Array = current_anchor.neighbors.values()
		if next_anchors.is_empty():
			break

		var next_anchor = next_anchors.pick_random()
		current_anchor = next_anchor
		random_duration = float(config.random_walk_durations.pick_random())
		random_walk.append({
			"anchor": current_anchor,
			"duration_beats": random_duration
		})

	return random_walk

func generate_walks(size: int) -> Array[Dictionary]:
	var generated_random_walks: Array[Dictionary] = []
	var pair_count := size / 2
	for i in range(pair_count):
		#length of the walk is randomly generated with a normal distribution around a mean length
		var node_walk := _build_random_walk(_get_random_walk_length(), builder.nodes.values())
		generated_random_walks.append({
			"name": "random_node_walk_%d" % i,
			"score": node_walk
		})

		var triangle_walk := _build_random_walk(_get_random_walk_length(), builder.triangles)
		generated_random_walks.append({
			"name": "random_triangle_walk_%d" % i,
			"score": triangle_walk
		})

	if size % 2 != 0:
		var node_walk := _build_random_walk(_get_random_walk_length(), builder.nodes.values())
		generated_random_walks.append({
			"name": "random_node_walk_%d" % pair_count,
			"score": node_walk
		})
	return generated_random_walks

func _get_random_walk_length() -> int:
	return int(clamp(
		round(randfn(config.random_walk_mean_length, config.random_walk_length_deviation)),
		config.random_walk_min_length,
		config.random_walk_max_length
	))
