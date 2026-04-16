extends Node2D

@onready var lsystem = $LSystem
@onready var turtle = $TurtlePath
@onready var builder: TonnetzBuilder = $TonnetzBuilder
@onready var player_scene = preload("res://Player.tscn")
@onready var player: CharacterBody2D = $Player

var rules = {
	"F": "F[+F]F[-F]F"
}

var actions = []

func _ready() -> void:
	builder.build(5)

func _unhandled_input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var click_pos = get_global_mouse_position()
		var start_anchor = builder.get_nearest_spawn_anchor(click_pos)
		if not start_anchor:
			return

		var snapped_pos = start_anchor.get_center()
		print("Click detected: ", click_pos, " snapped to: ", snapped_pos)

		# L-System → Actions
		var instructions = lsystem.generate("F", rules, 3)
		actions = turtle.build_actions(instructions, builder, start_anchor)

		if not player:
			player = player_scene.instantiate()
			add_child(player)

		player.global_position = snapped_pos
		player.set_actions(actions, snapped_pos)
		
		
