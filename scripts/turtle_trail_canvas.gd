extends Node2D
class_name TurtleTrailCanvas

@onready var config: TonnetzConfig = Config.config
@onready var builder: TonnetzBuilder = get_node("/root/Game/UI/TonnetzViewportContainer/TonnetzViewport/TonnetzWorld/TonnetzBuilder")

const TRAIL_MIN_ALPHA := 0.12

var source: Turtle
var tile_offsets: Array[Vector2] = []
var cached_tiling_radius := -1

func _ready() -> void:
	top_level = true
	global_position = Vector2.ZERO
	z_index = 20
	_update_tile_offsets()

func _draw() -> void:
	if not source:
		return

	_update_tile_offsets()
	var total_length := _get_total_trail_length()
	var visible_length = min(total_length, _get_max_trail_length())
	var hidden_length = max(0.0, total_length - visible_length)
	var drawn_before := 0.0

	for line in source.trail_lines:
		if not is_instance_valid(line):
			continue

		var line_length := _get_line_length(line)

		if hidden_length >= line_length:
			hidden_length -= line_length
			continue

		for tile_offset in tile_offsets:
			_draw_trail_line(line, tile_offset, hidden_length, drawn_before, visible_length)

		drawn_before += max(0.0, line_length - hidden_length)
		hidden_length = 0.0

func _get_total_trail_length() -> float:
	var total_length := 0.0

	for line in source.trail_lines:
		if is_instance_valid(line):
			total_length += _get_line_length(line)

	return total_length

func _get_max_trail_length() -> float:
	return max(1.0, float(config.turtle_trail_max_points)) * float(config.offset)

func _get_line_length(line: Line2D) -> float:
	var length := 0.0

	for point_index in range(1, line.get_point_count()):
		length += line.get_point_position(point_index - 1).distance_to(
			line.get_point_position(point_index)
		)

	return length

func _draw_trail_line(
	line: Line2D,
	tile_offset: Vector2,
	hidden_length: float,
	drawn_before: float,
	visible_length: float
) -> void:
	if line.get_point_count() < 2:
		return

	var drawn_length := drawn_before
	var drew_segment := false

	for point_index in range(1, line.get_point_count()):
		var start := line.get_point_position(point_index - 1)
		var end := line.get_point_position(point_index)
		var segment_length := start.distance_to(end)

		if segment_length <= 0.001:
			continue

		if hidden_length >= segment_length:
			hidden_length -= segment_length
			continue

		if hidden_length > 0.0:
			start = start.lerp(end, hidden_length / segment_length)
			segment_length = start.distance_to(end)
			hidden_length = 0.0

		var progress := 1.0
		if visible_length > 0.0:
			progress = clamp((drawn_length + segment_length * 0.5) / visible_length, 0.0, 1.0)

		var color := _get_faded_color(line.default_color, progress)
		var from_point := start + tile_offset
		var to_point := end + tile_offset

		draw_line(from_point, to_point, color, line.width, true)
		if not drew_segment:
			draw_circle(from_point, line.width * 0.5, color, true, -1.0, true)
			drew_segment = true

		draw_circle(to_point, line.width * 0.5, color, true, -1.0, true)
		drawn_length += segment_length

func _get_faded_color(color: Color, progress: float) -> Color:
	var faded_color := color
	faded_color.a *= lerp(TRAIL_MIN_ALPHA, 1.0, progress)
	return faded_color

func _update_tile_offsets() -> void:
	var tiling_radius := TonnetzConfig.TONNETZ_VIEWPORT_TILING_RADIUS

	if (
		cached_tiling_radius == tiling_radius
		and not tile_offsets.is_empty()
	):
		return

	cached_tiling_radius = tiling_radius
	tile_offsets = [Vector2.ZERO]

	for row in range(-tiling_radius, tiling_radius + 1):
		for column in range(-tiling_radius, tiling_radius + 1):
			if row == 0 and column == 0:
				continue

			tile_offsets.append(builder.get_tile_offset(Vector2i(column, row)))
