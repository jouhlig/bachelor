extends Node2D

@onready var turtle = $Turtle
@onready var builder: TonnetzBuilder = $TonnetzBuilder
@onready var piano_roll: PianoRoll = $UI/PianoRoll
@onready var interpreter = $Interpreter

@export var animations_on := false
@export var lsystem_on := true

var config: TonnetzConfig
var lsystem: LSystem
@onready var ui = $UI
var actions := []


func _ready() -> void:
	config = Config.config

	builder.animation_on = animations_on

	turtle.stopped_at_target.connect(CL.stop_clock)

	# Build Tonnetz first
	await builder.build()

	# Generate initial L-System
	lsystem = LSystemFactory.random(config)
	ui.update_lsystem_ui(lsystem)


func _unhandled_input(event) -> void:
	if (
		event is InputEventMouseButton
		and event.pressed
		and event.button_index == MOUSE_BUTTON_LEFT
	):
		var click_pos := get_global_mouse_position()

		var start_anchor = builder.get_nearest_spawn_anchor(click_pos)

		if not start_anchor:
			return

		var snapped_pos = start_anchor.get_center()

		if not lsystem_on:
			actions.clear()

			turtle.clear_path(snapped_pos)

			return

		# L-System → Turtle + Actions

		var instructions := lsystem.generated_string

		actions = interpreter.set_actions(
			instructions,
			snapped_pos
		)

		#print("actions: ", actions)

		piano_roll.update_roll(actions)

		piano_roll.auto_follow = true

		CL.start_clock()
		
		turtle.set_actions(actions, snapped_pos)


func get_lsystem() -> LSystem:
	return lsystem


func set_lsystem(new_lsystem: LSystem) -> void:
	lsystem = new_lsystem

	#print("New LSystem assigned.")


func regenerate_lsystem_string() -> void:
	LSystemFactory.regenerate_string(
		lsystem,
		config.number_iterations
	)


#func regenerate_lsystem_rules() -> void:
	#LSystemFactory.regenerate_rules(
		#lsystem,
		#config
	#)


func get_action_pitch_sequence() -> Array:
	var pitch_sequence := []

	for action in actions:
		pitch_sequence.append(
			action.get("pitches", [])
		)

	return pitch_sequence


func on_lsystem_toggled(toggled_state: bool) -> void:
	lsystem_on = toggled_state

	if not lsystem_on and turtle:
		actions.clear()

		turtle.stop_after_current_target()


func on_bpm_changed(new_value: int) -> void:
	CL.bpm = new_value

	#piano_roll.refresh_view()


func on_iterations_changed(new_value: int) -> void:
	config.number_iterations = new_value

	regenerate_lsystem_string()

	#print("Regenerated string with iterations: ",new_value)


func on_animation_toggled(toggled_state: bool) -> void:
	animations_on = toggled_state

	builder._on_ui_toggle_animation()
