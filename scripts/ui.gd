extends Control

signal toggle_animation
signal toggle_lsystem(toggled_on: bool)
signal bpm_changed(new_value: int)
signal instrument_changed(index: int)
signal iterations_changed(new_value: int)
signal length_changed(new_value: int)

@onready var config = Config.config
@onready var root = get_node("/root/Game")

var prod_box = preload("res://l_system_production_box.tscn")

@onready var lsystem_label = $TabContainer/LSystemContainer/RichTextLabel

@onready var sampler_button = $TabContainer/SamplerContainer/SamplerButton
@onready var animation_button = $TabContainer/AnimationContainer/AnimationSwitch

@onready var bpm_value_label = $TabContainer/BPMContainer/BPMValueLabel
@onready var bpm_slider = $TabContainer/BPMContainer/BPMSlider

@onready var iterations_value_label = $TabContainer/LSystemContainer/IterationsContainer/IterationsValue
@onready var iterations_slider = $TabContainer/LSystemContainer/IterationsContainer/IterationsSlider

@onready var length_value_label = $TabContainer/LengthContainer/LengthValue
@onready var length_slider = $TabContainer/LengthContainer/LengthSlider

@onready var piano_roll_container = $PianoRoll
@onready var piano_roll = $PianoRoll

@onready var axiom_text_edit = $TabContainer/LSystemContainer/Axiom/axiom_text_edit
@onready var generated_string_label = $TabContainer/LSystemContainer/GeneratedString/String


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	instrument_changed.connect(AM.change_instrument)
	
	bpm_value_label.text = str(config.bpm)
	bpm_slider.value = config.bpm

	length_value_label.text = str(config.length_bars)
	length_slider.value = config.length_bars

	iterations_value_label.text = str(config.number_iterations)
	iterations_slider.value = config.number_iterations

	piano_roll_container.size = Vector2(1920, 350)
	piano_roll_container.position = Vector2(0, 1080 - 350)


	


	
########### L-SYSTEM ###########

func update_lsystem_ui(lsystem: LSystem) -> void:
	clear_rules()

	axiom_text_edit.text = lsystem.axiom
	generated_string_label.text = lsystem.generated_string

	add_system_rules(lsystem)


func add_system_rules(lsystem: LSystem) -> void:
	for key in lsystem.rules:
		var new_prod = prod_box.instantiate()

		lsystem_label.add_sibling(new_prod)

		new_prod.setup(
			key,
			lsystem.rules[key]
		)
		#connect signal to UI
		new_prod.production_changed.connect(on_production_rule_changed)

		new_prod.add_to_group("rule_boxes")


func clear_rules() -> void:
	get_tree().call_group("rule_boxes","queue_free")


func _on_lsystem_changed() -> void:
	var new_system := LSystemFactory.random(config)

	root.set_lsystem(new_system)

	update_lsystem_ui(new_system)


func _on_axiom_text_edit_text_submitted(new_text: String) -> void:
	if new_text.is_empty():
		return

	var clamped_text := new_text[0]

	axiom_text_edit.text = clamped_text

	root.lsystem.axiom = clamped_text

	update_generated_string()


func update_generated_string() -> void:
	LSystemFactory.regenerate_string( root.lsystem, config.number_iterations)
	generated_string_label.text = root.lsystem.generated_string


func on_iterations_changed(new_value: int) -> void:
	config.number_iterations = new_value

	iterations_value_label.text = str(new_value)

	update_generated_string()

	emit_signal("iterations_changed", new_value)


func _on_length_changed(value_changed: bool) -> void:
	var new_value := int(length_slider.value)

	config.length_bars = new_value

	length_value_label.text = str(new_value)

	emit_signal("length_changed", new_value)

func on_production_rule_changed():
	#print("production rule changed")
	update_lsystem_ui(root.lsystem)
	

########### SAMPLER ###########

func changeInstrument(index: int) -> void:
	emit_signal("instrument_changed", index)

	#print("sending signal from UI")


########### ANIMATIONS ###########

func toggleAnimation(toggled_on: bool) -> void:
	emit_signal("toggle_animation")


func toggleLSystem(toggled_on: bool) -> void:
	emit_signal("toggle_lsystem", toggled_on)


########### TEMPO ###########

func on_bpm_changed(ended: bool) -> void:
	var new_value := int(bpm_slider.value)

	config.bpm = new_value

	bpm_value_label.text = str(new_value)

	emit_signal("bpm_changed", new_value)
