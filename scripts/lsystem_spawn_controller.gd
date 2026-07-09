class_name LSystemSpawnController
extends RefCounted

class SpawnDragMarker:
	extends Node2D

	const OUTLINE_SEGMENTS := 48
	const LINE_WIDTH := 3.0

	var radius := 0.0
	var target_radius := 0.0
	var target := Vector2.ZERO
	var color := Color.WHITE

	func configure(new_radius: float, new_target_radius: float, new_color: Color) -> void:
		radius = new_radius
		target_radius = new_target_radius
		color = new_color
		queue_redraw()

	func set_target(world_target: Vector2) -> void:
		target = world_target - global_position
		queue_redraw()

	func _draw() -> void:
		if radius <= 0.0:
			return

		draw_arc(Vector2.ZERO, radius, 0.0, TAU, OUTLINE_SEGMENTS, color, LINE_WIDTH, true)

		if target.length() <= radius:
			return

		var direction := target.normalized()
		var start := direction * radius
		draw_line(start, target, color, LINE_WIDTH, true)
		draw_circle(target, target_radius, color, true, -1.0, true)

const SPAWN_MARKER_Z_INDEX := 60
const DIRECTION_HIGHLIGHT_Z_INDEX := 59

var builder: TonnetzBuilder
var tonnetz_world: Node2D
var config: TonnetzConfig
var drag_origin_anchor = null
var drag_marker: SpawnDragMarker = null
var direction_highlight_layer: Node2D = null
var valid_direction_anchors: Array = []

func _init(
	new_builder: TonnetzBuilder,
	new_tonnetz_world: Node2D,
	new_config: TonnetzConfig
) -> void:
	builder = new_builder
	tonnetz_world = new_tonnetz_world
	config = new_config

func is_dragging() -> bool:
	return is_instance_valid(drag_marker)

func begin_drag(click_pos: Vector2, color: Color) -> void:
	cancel_drag()
	drag_origin_anchor = builder.get_nearest_spawn_anchor(click_pos)

	if not drag_origin_anchor:
		return

	drag_marker = SpawnDragMarker.new()
	drag_marker.z_index = SPAWN_MARKER_Z_INDEX
	drag_marker.configure(max(1.0, config.note_radius), max(1.0, config.player_radius), color)
	tonnetz_world.add_child(drag_marker)
	drag_marker.global_position = drag_origin_anchor.get_center()
	drag_marker.set_target(click_pos)
	_update_direction_highlights(color)

func update_target(click_pos: Vector2) -> void:
	if is_instance_valid(drag_marker):
		drag_marker.set_target(click_pos)

func cancel_drag() -> void:
	drag_origin_anchor = null
	valid_direction_anchors.clear()
	_clear_direction_highlights()

	if is_instance_valid(drag_marker):
		drag_marker.queue_free()

	drag_marker = null

	if is_instance_valid(direction_highlight_layer):
		direction_highlight_layer.queue_free()

	direction_highlight_layer = null

func release_drag(click_pos: Vector2) -> Dictionary:
	if not drag_origin_anchor:
		return {}

	var origin_anchor = drag_origin_anchor
	var direction_anchor = _get_clicked_valid_direction_anchor(click_pos)
	cancel_drag()

	var spawn_direction := _get_spawn_direction(origin_anchor, direction_anchor)

	if not spawn_direction.is_empty():
		spawn_direction["origin"] = origin_anchor
		return spawn_direction

	return {}

func _update_direction_highlights(color: Color) -> void:
	valid_direction_anchors.clear()
	_clear_direction_highlights()

	if not drag_origin_anchor:
		return

	for next_anchor in _get_next_anchor_candidates(drag_origin_anchor):
		if drag_origin_anchor is TonnetzNode and not (next_anchor is TonnetzNode):
			continue

		if drag_origin_anchor is TriangleArea and not (next_anchor is TriangleArea):
			continue

		if valid_direction_anchors.has(next_anchor):
			continue

		valid_direction_anchors.append(next_anchor)
		_add_direction_highlight(next_anchor, color)

func _get_next_anchor_candidates(anchor) -> Array:
	var candidates := []

	if not anchor:
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

func _get_clicked_valid_direction_anchor(click_pos: Vector2):
	var nearest = null
	var nearest_distance := INF

	for anchor in valid_direction_anchors:
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

func _add_direction_highlight(anchor, color: Color) -> void:
	if not is_instance_valid(direction_highlight_layer):
		direction_highlight_layer = Node2D.new()
		direction_highlight_layer.name = "SpawnDirectionHighlights"
		direction_highlight_layer.z_index = DIRECTION_HIGHLIGHT_Z_INDEX
		tonnetz_world.add_child(direction_highlight_layer)

	var highlight := AnchorHighlight.new()
	highlight.position = anchor.get_center()
	var highlight_color = color
	highlight_color.a = config.walk_highlight_alpha
	highlight.configure(
		max(1.0, config.note_radius),
		highlight_color,
		0.0,
		0.0
	)
	direction_highlight_layer.add_child(highlight)

func _clear_direction_highlights() -> void:
	if not is_instance_valid(direction_highlight_layer):
		return

	for child in direction_highlight_layer.get_children():
		child.queue_free()

func _get_spawn_direction(origin_anchor, direction_anchor) -> Dictionary:
	if not origin_anchor or not direction_anchor or origin_anchor == direction_anchor:
		return {}

	if origin_anchor is TonnetzNode and direction_anchor is TonnetzNode:
		var direction = _get_neighbor_key_between(origin_anchor, direction_anchor)

		if typeof(direction) == TYPE_VECTOR2I:
			return {
				"initial_dir": direction,
				"initial_edge": 0
			}

		return {}

	if origin_anchor is TriangleArea and direction_anchor is TriangleArea:
		var edge = _get_neighbor_key_between(origin_anchor, direction_anchor)

		if typeof(edge) == TYPE_INT:
			return {
				"initial_dir": Vector2i(1, 0),
				"initial_edge": int(edge)
			}

	return {}

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
