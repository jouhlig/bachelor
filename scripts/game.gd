extends Node2D

#@onready var lsystem = $LSystem
@onready var turtle = $Turtle
@onready var builder: TonnetzBuilder = $TonnetzBuilder
@onready var piano_roll: PianoRoll = $UI/PianoRoll
@onready var interpreter = $Interpreter
@export var animations_on = false
@export var lsystem_on: bool = true


#only for mvp
var current_lsystem = LSystem.new(
	"s",
	{"l": "lsr", "r": "sl", "s": "sl"},
	3
)

var actions = []

func _ready() -> void:

	builder.animation_on = animations_on
	turtle.stopped_at_target.connect(CL.stop_clock)
	#build Tonnetz
	await builder.build()


func _unhandled_input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var click_pos = get_global_mouse_position()
		var start_anchor = builder.get_nearest_spawn_anchor(click_pos)
		if not start_anchor:
			return

		var snapped_pos = start_anchor.get_center()
		#print("Click detected: ", click_pos, " snapped to: ", snapped_pos)


		if not lsystem_on:
			actions = []
			turtle.clear_path(snapped_pos)
			return
		
		# L-System → Actions
		var instructions = current_lsystem.generate()
		turtle.build_path(instructions, snapped_pos)
		var action_list = interpreter.set_actions(instructions, snapped_pos)
		piano_roll.update_roll(action_list)
		piano_roll.auto_follow = true
		turtle.global_position = snapped_pos
		CL.start_clock()
		

func get_lsystem():
	return current_lsystem

func get_action_pitch_sequence() -> Array:
	var pitch_sequence = []
	for action in actions:
		pitch_sequence.append(action.get("pitches", []))
	return pitch_sequence

func on_lsystem_toggled(toggled_state: bool) -> void:
	lsystem_on = toggled_state
	if not lsystem_on and turtle:
		actions = []
		turtle.stop_after_current_target()
	
func on_bpm_changed(new_value: int) -> void:
	CL.bpm = new_value
	piano_roll.refresh_view()
	
func on_iterations_changed(new_value: int) -> void:
	current_lsystem.iterations = new_value
	current_lsystem.generate()
	
func on_animation_toggled(toggled_state: bool) -> void:
	animations_on = toggled_state
	builder._on_ui_toggle_animation()
