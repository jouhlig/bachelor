extends Node
var TriangleScene = preload("res://Triangle.tscn")

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	#spawn triangles
	for i in range(0,10):
		var pos = Vector2(i*200, 200)
		spawn_triangle(pos, i)
	

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func spawn_triangle(position: Vector2, element_id: int):
	var triangle = TriangleScene.instantiate()
	add_child(triangle)
	triangle.position = position
