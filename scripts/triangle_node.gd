extends Area2D
class_name TriangleArea

#nodes are ordered CLOCKWISE
var nodes: Array[TonnetzNode] = []
enum Orientation {UP, DOWN}
var orientation: int
var neighbors := {}
var visual_points := PackedVector2Array()

@onready var config: TonnetzConfig = Config.config
@onready var builder = get_node("/root/Game/UI/TonnetzViewportContainer/TonnetzViewport/TonnetzWorld/TonnetzBuilder")

func shares_edge(
	other: TriangleArea,
	edge_index: int
) -> bool:

	var edge = get_edge_nodes(edge_index)

	var a = edge[0]
	var b = edge[1]

	return (
		other.nodes.has(a)
		and other.nodes.has(b)
	)
	
func get_edge_nodes(edge_index: int) -> Array[TonnetzNode]:
	return [
		nodes[edge_index],
		nodes[(edge_index + 1) % 3]
	]
	
func set_nodes(node_array: Array[TonnetzNode]):
	nodes = node_array
	
	# Compute average position
	var avg_pos = Vector2.ZERO
	for n in nodes:
		avg_pos += n.position
	avg_pos /= 3
	position = avg_pos
	
	# Compute relative points and shrink triangle slightly toward its center
	var points = PackedVector2Array()
	for n in nodes:
		points.append((n.position - position) * config.triangle_scale)
	visual_points = points
	
	# Collision
	var coll = CollisionPolygon2D.new()
	coll.polygon = points
	add_child(coll)
	
	
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	
	# Set collision layer and mask
	collision_layer = 3
	collision_mask = 1  # Detect player
	queue_redraw()

func _draw() -> void:
	if visual_points.size() < 3:
		return
#
	#var outline = PackedVector2Array(visual_points)
	#outline.append(visual_points[0])
	#draw_polyline(outline, config.line_color, config.line_width, true)
	
func get_pitches()->Array[int]:
	var pitches : Array[int] = []
	for n in nodes:
		pitches.append(n.pitch)
	return pitches
		
func _on_body_entered(body):
	if body is CharacterBody2D:
		if body.has_method("should_play_triangle_audio") and not body.should_play_triangle_audio():
			return
		
		AM.play_notes(nodes)

func _on_body_exited(body):
	if body is CharacterBody2D:
		if body.has_method("should_play_triangle_audio") and not body.should_play_triangle_audio():
			return
		#print("Exited triangle")
		#for n in nodes:
			#AM.stop_note(n.pitch)

func get_center() -> Vector2:
	return global_position

func get_next(edge_index: int) -> TriangleArea:
	return neighbors.get(edge_index)


func get_node_coords() -> Array[Vector2i]:
	var coords: Array[Vector2i] = []
	for n in nodes:
		coords.append(Vector2i(n.q, n.r))
	return coords
