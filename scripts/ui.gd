extends Control

signal toggle_animation
signal toggle_lsystem(toggled_on: bool)
signal bpm_changed(new_value: int)
signal instrument_changed(index: int)
signal iterations_changed(new_value: int)

@export var config : TonnetzConfig
@onready var LSystemLabel = $UIContainer/VBoxContainer/RichTextLabel
@onready var root = get_node("/root/Game")
@onready var samplerButton = $UIContainer/VBoxContainer/SamplerButton
@onready var animationButton = $UIContainer/VBoxContainer/AnimationSwitch
@onready var bpmValueLabel = $UIContainer/VBoxContainer/BPMContainer/BPMValueLabel
@onready var bpmSlider = $UIContainer/VBoxContainer/BPMContainer/BPMSlider
@onready var iterationsValueLabel = $UIContainer/VBoxContainer/IterationsContainer/IterationsValue
@onready var piano_roll_container = $FoldableContainer
@onready var piano_roll = $FoldableContainer/PianoRoll



func _ready() -> void:	
	var lsystem = root.get_lsystem()
	LSystemLabel.append_text(str(lsystem.rules))
	piano_roll_container.size = piano_roll.get_required_size() + Vector2i(0, 55)
	instrument_changed.connect(AM.change_instrument)
	

func changeInstrument(index: int):
	emit_signal("instrument_changed", index)
	print("sending signal from UI")
func toggleAnimation(toggled_on: bool) -> void:
	emit_signal("toggle_animation")
func toggleLSystem(toggled_on: bool) -> void:
	emit_signal("toggle_lsystem", toggled_on)
func on_bpm_changed(ended: bool ) -> void:
	var new_value = bpmSlider.value
	emit_signal("bpm_changed", new_value)
	bpmValueLabel.text = str(new_value)
func on_iterations_changed(new_value: int) -> void:
	emit_signal("iterations_changed", new_value)
	iterationsValueLabel.text = str(new_value)
