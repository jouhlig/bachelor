extends Control

signal toggle_animation
signal toggle_lsystem(toggled_on: bool)
signal bpm_changed(new_value: int)
signal instrument_changed(index: int)
signal length_changed(new_value: int)
signal add_lsystem_requested
signal lsystem_selected(index: int)
signal lsystem_randomize_requested(index: int)
signal lsystem_duplicate_requested(index: int)
signal lsystem_remove_requested(index: int)
signal lsystem_play_requested(index: int)
signal lsystem_stop_requested(index: int)
signal lsystem_axiom_changed(index: int, new_axiom: String)
signal lsystem_iterations_changed(index: int, iterations: int)
signal lsystem_rule_changed(index: int, symbol: String, production: String)
signal lsystem_volume_changed(index: int, volume: float)

@onready var config = Config.config
@onready var root = get_node("/root/Game")

@onready var bpm_value_label = $TabContainer/BPMContainer/BPMValueLabel
@onready var bpm_slider = $TabContainer/BPMContainer/BPMSlider

@onready var length_value_label = $TabContainer/LengthContainer/LengthValue
@onready var length_slider = $TabContainer/LengthContainer/LengthSlider

@onready var piano_roll_container = $PianoRoll
@onready var piano_roll = $PianoRoll

@onready var add_lsystem_button = $TabContainer/LSystemContainer/AddLSystem
@onready var lsystem_container = $TabContainer/LSystemContainer
@onready var tab_container = $TabContainer

var voice_scroll: ScrollContainer
var voice_list: VBoxContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	instrument_changed.connect(AM.change_instrument)
	add_lsystem_button.pressed.connect(_on_add_lsystem_pressed)
	tab_container.size = Vector2(420, 720)
	_setup_lsystem_voice_list()
	
	bpm_value_label.text = str(config.bpm)
	bpm_slider.value = config.bpm

	length_value_label.text = str(config.length_bars)
	length_slider.value = config.length_bars

	piano_roll_container.size = Vector2(1920, 350)
	piano_roll_container.position = Vector2(0, 1080 - 350)


	


	
########### L-SYSTEM ###########

func update_lsystems_ui(
	lsystems: Array,
	active_index: int,
	colors: Array,
	volumes: Array = [],
	voice_info: Array = []
) -> void:
	if not voice_list:
		return

	for child in voice_list.get_children():
		child.queue_free()

	for i in range(lsystems.size()):
		var color := Color.WHITE

		if i < colors.size():
			color = colors[i]

		var volume := 0.8

		if i < volumes.size():
			volume = volumes[i]

		var info := {}

		if i < voice_info.size():
			info = voice_info[i]

		voice_list.add_child(
			_create_lsystem_card(
				i,
				lsystems[i],
				i == active_index,
				color,
				volume,
				info
			)
		)


func _setup_lsystem_voice_list() -> void:
	voice_scroll = ScrollContainer.new()
	voice_scroll.name = "LSystemVoiceScroll"
	voice_scroll.custom_minimum_size = Vector2(0, 560)
	voice_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	voice_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lsystem_container.add_child(voice_scroll)

	voice_list = VBoxContainer.new()
	voice_list.name = "LSystemVoiceList"
	voice_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	voice_scroll.add_child(voice_list)


func _create_lsystem_card(
	index: int,
	lsystem: LSystem,
	is_active: bool,
	color: Color,
	volume: float,
	info: Dictionary
) -> Control:
	var panel := PanelContainer.new()
	panel.name = "LSystemVoice%d" % index
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.88) if is_active else Color(0.9, 0.9, 0.9, 0.7)
	style.border_color = color
	style.set_border_width(SIDE_LEFT, 4)
	style.set_border_width(SIDE_TOP, 2 if is_active else 1)
	style.set_border_width(SIDE_RIGHT, 2 if is_active else 1)
	style.set_border_width(SIDE_BOTTOM, 2 if is_active else 1)
	style.set_content_margin(SIDE_LEFT, 8)
	style.set_content_margin(SIDE_TOP, 8)
	style.set_content_margin(SIDE_RIGHT, 8)
	style.set_content_margin(SIDE_BOTTOM, 8)
	panel.add_theme_stylebox_override("panel", style)

	var card := VBoxContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(card)

	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_child(header)

	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(22, 22)
	swatch.color = color
	header.add_child(swatch)

	var title := Label.new()
	title.text = "Voice %d" % (index + 1)
	title.modulate = Color.BLACK
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var active_button := Button.new()
	active_button.text = "Active" if is_active else "Select"
	active_button.toggle_mode = true
	active_button.button_pressed = is_active
	active_button.pressed.connect(_on_voice_selected.bind(index))
	header.add_child(active_button)

	var random_button := Button.new()
	random_button.text = "Random"
	random_button.pressed.connect(_on_voice_randomize_pressed.bind(index))
	header.add_child(random_button)

	var duplicate_button := Button.new()
	duplicate_button.text = "Copy"
	duplicate_button.pressed.connect(_on_voice_duplicate_pressed.bind(index))
	header.add_child(duplicate_button)

	var remove_button := Button.new()
	remove_button.text = "Remove"
	remove_button.pressed.connect(_on_voice_remove_pressed.bind(index))
	header.add_child(remove_button)

	var play_button := Button.new()
	play_button.text = "Play"
	play_button.pressed.connect(_on_voice_play_pressed.bind(index))
	header.add_child(play_button)

	var stop_button := Button.new()
	stop_button.text = "Stop"
	stop_button.pressed.connect(_on_voice_stop_pressed.bind(index))
	header.add_child(stop_button)

	var status_row := VBoxContainer.new()
	card.add_child(status_row)

	var origin_label := Label.new()
	origin_label.modulate = Color.BLACK
	origin_label.text = "Origin: %s" % info.get("origin_label", "Not set")
	status_row.add_child(origin_label)

	var start_label := Label.new()
	start_label.modulate = Color.BLACK
	start_label.text = "Start: %s" % info.get("start_label", "Not scheduled")
	status_row.add_child(start_label)

	var axiom_row := HBoxContainer.new()
	card.add_child(axiom_row)

	var axiom_label := Label.new()
	axiom_label.text = "Axiom"
	axiom_label.modulate = Color.BLACK
	axiom_row.add_child(axiom_label)

	var axiom_edit := LineEdit.new()
	axiom_edit.text = lsystem.axiom
	axiom_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	axiom_edit.text_submitted.connect(_on_voice_axiom_submitted.bind(index))
	axiom_row.add_child(axiom_edit)

	var iterations_row := HBoxContainer.new()
	card.add_child(iterations_row)

	var iterations_label := Label.new()
	iterations_label.text = "Iterations"
	iterations_label.modulate = Color.BLACK
	iterations_row.add_child(iterations_label)

	var iterations_value := Label.new()
	iterations_value.text = str(lsystem.iterations)
	iterations_value.modulate = Color.BLACK
	iterations_row.add_child(iterations_value)

	var iterations_slider := HSlider.new()
	iterations_slider.min_value = 0
	iterations_slider.max_value = 10
	iterations_slider.step = 1
	iterations_slider.rounded = true
	iterations_slider.value = lsystem.iterations
	iterations_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	iterations_slider.value_changed.connect(
		_on_voice_iterations_value_changed.bind(iterations_value)
	)
	iterations_slider.drag_ended.connect(
		_on_voice_iterations_drag_ended.bind(index, iterations_slider)
	)
	iterations_row.add_child(iterations_slider)

	var volume_row := HBoxContainer.new()
	card.add_child(volume_row)

	var volume_label := Label.new()
	volume_label.text = "Volume"
	volume_label.modulate = Color.BLACK
	volume_row.add_child(volume_label)

	var volume_value := Label.new()
	volume_value.text = "%d%%" % int(round(volume * 100.0))
	volume_value.modulate = Color.BLACK
	volume_value.custom_minimum_size = Vector2(42, 0)
	volume_row.add_child(volume_value)

	var volume_slider := HSlider.new()
	volume_slider.min_value = 0.0
	volume_slider.max_value = 1.0
	volume_slider.step = 0.01
	volume_slider.value = volume
	volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	volume_slider.value_changed.connect(
		_on_voice_volume_changed.bind(index, volume_value)
	)
	volume_row.add_child(volume_slider)

	var generated_edit := LineEdit.new()
	generated_edit.text = lsystem.generated_string
	generated_edit.editable = false
	generated_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_child(generated_edit)

	for key in lsystem.rules:
		card.add_child(_create_rule_row(index, key, lsystem.rules[key]))

	return panel


func _create_rule_row(index: int, symbol: String, production: String) -> Control:
	var row := VBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var input_row := HBoxContainer.new()
	input_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(input_row)

	var symbol_label := LineEdit.new()
	symbol_label.text = symbol
	symbol_label.editable = false
	symbol_label.custom_minimum_size = Vector2(28, 30)
	input_row.add_child(symbol_label)

	var arrow := Label.new()
	arrow.text = "->"
	arrow.modulate = Color.BLACK
	input_row.add_child(arrow)

	var production_edit := LineEdit.new()
	production_edit.text = production
	production_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input_row.add_child(production_edit)

	var warning := Label.new()
	warning.visible = false
	warning.modulate = Color.BLACK
	row.add_child(warning)

	production_edit.text_submitted.connect(
		_on_voice_rule_submitted.bind(index, symbol, production_edit, warning)
	)

	return row


func _on_add_lsystem_pressed() -> void:
	add_lsystem_requested.emit()


func _on_voice_selected(index: int) -> void:
	lsystem_selected.emit(index)


func _on_voice_randomize_pressed(index: int) -> void:
	lsystem_randomize_requested.emit(index)

func _on_voice_duplicate_pressed(index: int) -> void:
	lsystem_duplicate_requested.emit(index)

func _on_voice_remove_pressed(index: int) -> void:
	lsystem_remove_requested.emit(index)


func _on_voice_play_pressed(index: int) -> void:
	lsystem_play_requested.emit(index)


func _on_voice_stop_pressed(index: int) -> void:
	lsystem_stop_requested.emit(index)


func _on_voice_axiom_submitted(new_text: String, index: int) -> void:
	if new_text.is_empty():
		return

	lsystem_axiom_changed.emit(index, new_text[0])


func _on_voice_iterations_value_changed(
	new_value: float,
	iterations_value: Label
) -> void:
	iterations_value.text = str(int(new_value))


func _on_voice_iterations_drag_ended(
	value_changed: bool,
	index: int,
	iterations_slider: HSlider
) -> void:
	if not value_changed:
		return

	var iterations := int(iterations_slider.value)
	lsystem_iterations_changed.emit(index, iterations)

func _on_voice_volume_changed(
	new_value: float,
	index: int,
	volume_value: Label
) -> void:
	volume_value.text = "%d%%" % int(round(new_value * 100.0))
	lsystem_volume_changed.emit(index, new_value)


func _on_voice_rule_submitted(
	new_text: String,
	index: int,
	symbol: String,
	production_edit: LineEdit,
	warning: Label
) -> void:
	warning.visible = false

	var regex := RegEx.new()
	regex.compile("[^lruds1248]")

	var filtered = regex.sub(new_text, "", true)

	if filtered != new_text:
		production_edit.text = filtered
		warning.visible = true
		warning.text = "A production can only include the symbols from the alphabet."

	if filtered.is_empty():
		filtered = symbol
		production_edit.text = filtered
		warning.visible = true
		warning.text = "A production cannot be empty."

	lsystem_rule_changed.emit(index, symbol, filtered)


func _on_length_changed(value_changed: bool) -> void:
	var new_value := int(length_slider.value)

	config.length_bars = new_value

	length_value_label.text = str(new_value)

	emit_signal("length_changed", new_value)

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
