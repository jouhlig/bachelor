extends CharacterBody2D

@export var config: TonnetzConfig

func _ready() -> void:
	if not config:
		config = TonnetzConfig.new()
	
	var radius = config.player_radius
	var shape = CircleShape2D.new()
	shape.radius = radius
	$CollisionShape2D.shape = shape
	
	var sphere = SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	$Visuals/MeshInstance2D.mesh = sphere
	$Visuals/MeshInstance2D.modulate = config.player_color
	$Visuals/MeshInstance2D.z_index = 2  # Player above notes and triangles
	
	# Set collision layer and mask
	collision_layer = 1
	collision_mask = 0  # Player doesn't need to detect others, only be detected
	
func _physics_process(delta: float) -> void:
	var direction : Vector2 = Vector2.ZERO
	direction.x = Input.get_action_strength("right") - Input.get_action_strength("left")
	direction.y = Input.get_action_strength("down") - Input.get_action_strength("up")
	velocity = direction * config.player_speed
	move_and_slide()
