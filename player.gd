extends CharacterBody2D


const SPEED = 100.0
#const JUMP_VELOCITY = -400.0

func _ready() -> void:
	var shape = CircleShape2D.new()
	shape.radius = 20
	$CollisionShape2D.shape = shape
	
	var points = create_circle_points(20)
	$Visuals/Polygon2D.polygon = points
	
func _physics_process(delta: float) -> void:
	var direction : Vector2 = Vector2.ZERO
	direction.x = Input.get_action_strength("right") - Input.get_action_strength("left")
	direction.y = Input.get_action_strength("down") - Input.get_action_strength("up")
	velocity = direction*SPEED
	move_and_slide()
	
#approximate circle shape for the visual polygon2D	
func create_circle_points(radius: float, segments: int = 32):
	var pts = PackedVector2Array()
	for i in range(segments):
		var angle = i * TAU / segments
		pts.append(Vector2(cos(angle), sin(angle)) * radius)
	return pts
