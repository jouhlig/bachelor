extends Control
class_name TonnetzTileLayer

@onready var config: TonnetzConfig = Config.config

var tonnetz_viewport: SubViewport
var builder: TonnetzBuilder

const WRAP_LINE_DIRECTIONS = [
	Vector2i(1, -1), Vector2i(0, -1), Vector2i(1, 0)
]
const NOTE_LABEL_SIZE := 13
const CENTRAL_TILE_FILL_ALPHA := 0.035

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), config.tonnetz_background_color, true)

	if not tonnetz_viewport or not builder or builder.nodes.is_empty():
		return

	_draw_central_tile_area()

	for tile in _get_tiles():
		_draw_tonnetz_tile(tile)

func refresh_tonnetz() -> void:
	queue_redraw()

func _draw_tonnetz_tile(tile: Vector2i) -> void:
	var tile_offset := builder.get_tile_offset(tile)

	_draw_world_connections(tile, tile_offset)

	for node in builder.nodes.values():
		_draw_world_node(node, tile_offset)

func _draw_world_connections(tile: Vector2i, tile_offset: Vector2) -> void:
	for node in builder.nodes.values():
		for direction in WRAP_LINE_DIRECTIONS:
			_draw_world_connection(node, direction, tile, tile_offset)

func _draw_world_connection(
	node: TonnetzNode,
	direction: Vector2i,
	tile: Vector2i,
	tile_offset: Vector2
) -> void:
	var neighbor = node.neighbors.get(direction)
	var neighbor_position: Vector2

	if neighbor:
		neighbor_position = neighbor.get_center() + tile_offset
	else:
		neighbor = builder.get_wrapped_node_neighbor(node, direction)

		if not neighbor:
			return

		var target_row_column := builder._get_row_column(Vector2i(node.q, node.r) + direction)
		var neighbor_tile := tile + builder.get_wrap_tile_for_row_column(target_row_column)
		neighbor_position = neighbor.get_center() + builder.get_tile_offset(neighbor_tile)

	var points := builder._get_line_endpoints(node.get_center() + tile_offset, neighbor_position)
	_draw_world_line(points[0], points[1])

func _draw_central_tile_area() -> void:
	var origin_coord := builder._coord_from_row_column(0, 0)
	var right_coord := builder._coord_from_row_column(
		0,
		int(config.column_count)
	)
	var bottom_coord := builder._coord_from_row_column(
		builder._get_wrap_row_period(),
		# Use the same row tile vector as wrapping, otherwise the marked
		# central tile drifts away from the actual repeated pitchclasses.
		builder.get_row_tile_column_shift()
	)
	var origin := builder.get_coord_center(origin_coord)
	var right := builder.get_coord_center(right_coord)
	var bottom := builder.get_coord_center(bottom_coord)
	var points := PackedVector2Array([
		tonnetz_viewport.canvas_transform * origin,
		tonnetz_viewport.canvas_transform * right,
		tonnetz_viewport.canvas_transform * (right + bottom - origin),
		tonnetz_viewport.canvas_transform * bottom
	])
	var fill_color := config.tonnetz_border_color
	fill_color.a = CENTRAL_TILE_FILL_ALPHA
	draw_colored_polygon(points, fill_color)

func _draw_world_line(start: Vector2, end: Vector2) -> void:
	var scale := _get_view_scale()
	var color := config.line_color
	draw_line(
		tonnetz_viewport.canvas_transform * start,
		tonnetz_viewport.canvas_transform * end,
		color,
		config.line_width * scale,
		true
	)

func _draw_world_node(node: TonnetzNode, tile_offset: Vector2) -> void:
	var scale := _get_view_scale()
	var center: Vector2 = tonnetz_viewport.canvas_transform * (node.get_center() + tile_offset)
	var radius := config.note_radius * scale
	var border_radius := (config.note_radius + config.outline_width + 1.0) * scale
	var border_color := config.line_color
	var fill_color := config.note_color
	var label_color := config.note_label_color

	draw_circle(center, border_radius, border_color, true, -1.0, true)
	draw_circle(center, radius, fill_color, true, -1.0, true)

	var font_size := maxi(8, roundi(NOTE_LABEL_SIZE * scale))
	var label_width := radius * 2.0
	draw_string(
		config.font,
		center + Vector2(-label_width * 0.5, font_size * 0.35),
		node.note_name,
		HORIZONTAL_ALIGNMENT_CENTER,
		label_width,
		font_size,
		label_color
	)

func _get_tiles() -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	var radius := TonnetzConfig.TONNETZ_VIEWPORT_TILING_RADIUS

	for row in range(-radius, radius + 1):
		for column in range(-radius, radius + 1):
			tiles.append(Vector2i(column, row))

	tiles.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return max(abs(a.x), abs(a.y)) > max(abs(b.x), abs(b.y))
	)
	return tiles

func _get_view_scale() -> float:
	return max(
		tonnetz_viewport.canvas_transform.x.length(),
		tonnetz_viewport.canvas_transform.y.length()
	)
