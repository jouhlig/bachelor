extends StaticBody2D



# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var shape = ConvexPolygonShape2D.new()
	shape.points = PackedVector2Array([
		Vector2(0, -50),
		Vector2(100, 100),
		Vector2(-100, 100)
	])
	$CollisionShape2D.shape = shape
	$Visuals/Polygon2D.polygon = shape.points
	


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
