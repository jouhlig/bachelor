extends Area2D
class_name TriangleArea

var nodes: Array[TonnetzNode] = []
@onready var config: TonnetzConfig = Config.config

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
	
	# Collision
	var coll = CollisionPolygon2D.new()
	coll.polygon = points
	add_child(coll)
	
	# Visual
	var vis = Polygon2D.new()
	vis.polygon = points
	vis.z_index = 0
	vis.color = config.triangle_color
	#var pitches := get_pitches()
	
	#vis.color = config.triangle_color_for_pitches(pitches)
	add_child(vis)
	
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	
	# Set collision layer and mask
	collision_layer = 3
	collision_mask = 1  # Detect player
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



func get_node_coords() -> Array[Vector2i]:
	var coords: Array[Vector2i] = []
	for n in nodes:
		coords.append(Vector2i(n.q, n.r))
	return coords
