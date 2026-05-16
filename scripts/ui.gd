extends Control

signal toggle_animation
signal toggle_lsystem(toggled_on: bool)
signal bpm_changed(new_value: int)
signal instrument_changed(index: int)
signal iterations_changed(new_value: int)
signal length_changed(new_value: int)

@onready var config = Config.config

@onready var LSystemLabel = $VBoxContainer/RichTextLabel
@onready var root = get_node("/root/Game")

@onready var samplerButton = $VBoxContainer/SamplerButton
@onready var animationButton = $VBoxContainer/AnimationSwitch

@onready var bpmValueLabel = $VBoxContainer/BPMContainer/BPMValueLabel
@onready var bpmSlider = $VBoxContainer/BPMContainer/BPMSlider

@onready var iterationsValueLabel = $VBoxContainer/IterationsContainer/IterationsValue
@onready var iterationsSlider = $VBoxContainer/IterationsContainer/IterationsSlider

@onready var lengthValueLabel = $VBoxContainer/LengthContainer/LengthValue
@onready var lengthSlider = $VBoxContainer/LengthContainer/LengthSlider

@onready var piano_roll_container = $PianoRoll
@onready var piano_roll = $PianoRoll



func _ready() -> void:	
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lsystem = root.get_lsystem()
	LSystemLabel.append_text(str(lsystem.rules))
	instrument_changed.connect(AM.change_instrument)
	
	bpmValueLabel.text = str(config.bpm)
	bpmSlider.value = config.bpm
	
	iterationsValueLabel.text = str(config.number_iterations)
	iterationsSlider.value = config.number_iterations
	
	lengthValueLabel.text = str(config.length_bars)
	lengthSlider.value = config.length_bars

	piano_roll_container.size = Vector2(1920, 350)
	piano_roll_container.position = Vector2(0, 1080-350)
	

func changeInstrument(index: int):
	emit_signal("instrument_changed", index)
	print("sending signal from UI")
func toggleAnimation(toggled_on: bool) -> void:
	emit_signal("toggle_animation")
func toggleLSystem(toggled_on: bool) -> void:
	emit_signal("toggle_lsystem", toggled_on)
func on_bpm_changed(ended: bool ) -> void:
	var new_value = int(bpmSlider.value)
	config.bpm = new_value
	emit_signal("bpm_changed", new_value)
	bpmValueLabel.text = str(new_value)
	
func on_iterations_changed(new_value: int) -> void:
	emit_signal("iterations_changed", new_value)
	iterationsValueLabel.text = str(new_value)
	config.number_iterations = new_value

func _on_length_changed(value_changed: bool) -> void:
	var new_value = lengthSlider.value
	lengthValueLabel.text = str(int(new_value))
	config.length_bars = new_value
	emit_signal("length_changed", new_value)
