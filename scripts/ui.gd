extends Control

##################################################
########## SIGNALS #############
##################################################
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
signal lsystem_mute_toggled(index: int, muted: bool)
signal tonnetz_clicked(world_position: Vector2)
signal global_play_pause_toggled(paused: bool)
signal play_selected_bar_requested
signal repeat_selected_bar_toggled(enabled: bool)
signal mutate_selection_requested(index: int)
signal mutation_side_selected(side: String)
signal mutation_apply_requested
signal mutation_cancel_requested
signal export_midi_requested(path: String)
signal master_reverb_changed(amount: float)
signal master_delay_changed(amount: float)
signal master_distortion_changed(amount: float)

##################################################
########## ONREADY VARS #############
##################################################
@onready var config = Config.config

@onready var piano_roll_container = $PianoRoll
@onready var lsystem_container = $TabContainer/LSystems
@onready var other_container = $TabContainer/Misc
@onready var tab_container = $TabContainer
@onready var tonnetz_viewport_container: SubViewportContainer = $TonnetzViewportContainer
@onready var tonnetz_viewport: SubViewport = $TonnetzViewportContainer/TonnetzViewport

##################################################
########## CONST #############
##################################################
const OUTER_MARGIN := 16.0
const PANEL_GAP := 12.0
const CANVAS_SIZE := Vector2(1920.0, 1080.0)
const LEFT_PANEL_WIDTH := 384.0 # 360 + padding

const PIANO_ROLL_HEIGHT := 350.0
const PIANO_ROLL_HIDDEN_HEIGHT := 0.0
const PIANO_ROLL_TOGGLE_SIZE := Vector2(82.0, 32.0)
const PANEL_PADDING := 12.0
const TAB_CONTENT_TOP_MARGIN := 14.0
const LSYSTEM_CARD_WIDTH := 300.0
const MUTED_ICON_PATH := "res://icons/muted.svg"
const UNMUTED_ICON_PATH := "res://icons/unmuted.svg"


##################################################
########## VAR DECLARATIO S #############
##################################################
var left_panel: Panel
var tonnetz_panel: Panel
var piano_panel: Panel
var piano_hide_button: Button
var voice_scroll: ScrollContainer
var voice_list: HBoxContainer
var sampler_button: OptionButton
var length_value_label: Label
var length_slider: HSlider
var bpm_value_label: Label
var bpm_slider: Slider
var animation_switch: CheckButton
var global_play_pause_button: Button
var play_selected_bar_button: Button
var repeat_selected_bar_button: Button
var export_midi_button: Button
var export_midi_dialog: FileDialog
var master_bpm_panel: PanelContainer
var master_reverb_panel: PanelContainer
var master_reverb_value_label: Label
var master_reverb_slider: VSlider
var master_delay_panel: PanelContainer
var master_delay_value_label: Label
var master_delay_slider: VSlider
var master_distortion_panel: PanelContainer
var master_distortion_value_label: Label
var master_distortion_slider: VSlider
var mutation_prompt: PanelContainer
var mutation_voice_button_row: HBoxContainer
var mutation_debug_label: Label
var mutation_debug_scroll: ScrollContainer
var mutation_decision_row: HBoxContainer
var mutation_side_row: HBoxContainer
var mutation_original_button: Button
var mutation_candidate_button: Button
var mutation_apply_button: Button
var mutation_cancel_button: Button
var global_paused := false
var piano_roll_hidden := false

##################################################
########## SETUP UI #############
##################################################
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	tab_container.clip_contents = true
	lsystem_container.clip_contents = true
	other_container.clip_contents = true

	instrument_changed.connect(AM.change_instrument)
	_setup_layout_panels()
	_setup_piano_roll_controls()
	_setup_global_play_pause_button()
	_setup_master_bpm_control()
	_setup_master_reverb_control()
	_setup_master_delay_control()
	_setup_master_distortion_control()
	_setup_export_midi_dialog()
	_setup_mutation_prompt()
	_apply_layout()
	tonnetz_viewport_container.mouse_filter = Control.MOUSE_FILTER_PASS
	tonnetz_viewport_container.gui_input.connect(_on_tonnetz_viewport_gui_input)
	_setup_other_controls()
	_setup_lsystem_voice_list()
	_apply_layout()
	
	bpm_value_label.text = str(config.bpm)
	bpm_slider.value = config.bpm

	length_value_label.text = str(config.length_bars)
	length_slider.value = config.length_bars

	animation_switch.button_pressed = config.animations_on
	_update_animation_switch_text()

##################################################
########## TONNETZ #############
##################################################
func is_position_in_tonnetz_area(screen_position: Vector2) -> bool:
	if not tonnetz_viewport_container:
		return false

	return Rect2(tonnetz_viewport_container.global_position, tonnetz_viewport_container.size).has_point(screen_position)


func get_tonnetz_area() -> Rect2:
	if not tonnetz_panel:
		return Rect2()

	return Rect2(tonnetz_panel.position, tonnetz_panel.size)


func get_tonnetz_world_position(screen_position: Vector2) -> Vector2:
	if not tonnetz_viewport_container:
		return screen_position

	return screen_position - tonnetz_viewport_container.global_position


func _on_tonnetz_viewport_gui_input(event: InputEvent) -> void:
	if (
		event is InputEventMouseButton
		and event.pressed
		and event.button_index == MOUSE_BUTTON_LEFT
	):
		tonnetz_clicked.emit(event.position)
		accept_event()

##################################################
########## SET CONTROLS FOR MISC #############
##################################################
func _setup_other_controls() -> void:
	other_container.modulate = Color.WHITE
	other_container.add_theme_constant_override("separation", 14)
	other_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var margin := MarginContainer.new()
	margin.name = "OtherContentMargin"
	margin.add_theme_constant_override("margin_top", TAB_CONTENT_TOP_MARGIN)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	other_container.add_child(margin)

	var panel := PanelContainer.new()
	panel.name = "OtherControlsCard"
	panel.custom_minimum_size = Vector2(LSYSTEM_CARD_WIDTH, 0)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 1.0)
	style.border_color = Color(0.0, 0.0, 0.0, 1.0)
	style.set_corner_radius_all(28)
	style.set_border_width_all(4)
	style.set_content_margin(SIDE_LEFT, 16)
	style.set_content_margin(SIDE_TOP, 24)
	style.set_content_margin(SIDE_RIGHT, 16)
	style.set_content_margin(SIDE_BOTTOM, 16)
	panel.add_theme_stylebox_override("panel", style)
	margin.add_child(panel)

	var card := VBoxContainer.new()
	#card.modulate = Color.WHITE
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(card)

	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_child(header)

	var title := Label.new()
	title.text = "Controls"
	var fv := FontVariation.new()
	fv.base_font = load("res://fonts/Rubik-VariableFont_wght.ttf")
	fv.variation_opentype = {"weight": 700}
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_font_override("font", fv)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	card.add_child(_create_label("Selected instrument:"))
	sampler_button = OptionButton.new()
	sampler_button.name = "SamplerButton"
	sampler_button.add_item("Xylophone", 0)
	sampler_button.add_item("Ocarina", 1)
	sampler_button.add_item("Piano", 2)
	sampler_button.add_item("Harp", 3)
	sampler_button.selected = 0
	sampler_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sampler_button.item_selected.connect(changeInstrument)
	card.add_child(sampler_button)

	card.add_child(_create_length_controls())

	animation_switch = CheckButton.new()
	animation_switch.name = "AnimationSwitch"
	#animation_switch.modulate = Color.BLACK
	animation_switch.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	animation_switch.toggled.connect(toggleAnimation)
	card.add_child(animation_switch)


func _create_length_controls() -> Control:
	var row := HBoxContainer.new()
	row.name = "LengthControls"
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	row.add_child(_create_label("Length in bars:"))

	length_value_label = _create_label("")
	row.add_child(length_value_label)

	length_slider = HSlider.new()
	length_slider.name = "LengthSlider"
	length_slider.value = 30.0
	length_slider.rounded = true
	length_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	length_slider.drag_ended.connect(_on_length_changed)
	row.add_child(length_slider)

	return row


func _create_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.modulate = Color.BLACK
	return label


# The three top-level layout regions are fixed because the project locks aspect ratio.
func _setup_layout_panels() -> void:
	left_panel = _create_layout_panel("LeftControlPanel", Color(0.97, 0.97, 0.95, 0.96), Color(0.08, 0.08, 0.08, 0.85), 2)
	tonnetz_panel = _create_layout_panel("TonnetzPanel", Color(1, 1, 1, 0.04), Color(0.08, 0.08, 0.08, 0.9), 3)
	piano_panel = _create_layout_panel("PianoRollPanel", Color(0.96, 0.96, 0.94, 0.98), Color(0.08, 0.08, 0.08, 0.9), 3)

	add_child(left_panel)
	add_child(tonnetz_panel)
	add_child(piano_panel)
	move_child(left_panel, 0)
	move_child(tonnetz_panel, 1)
	move_child(piano_panel, 2)


func _create_layout_panel(panel_name: String, bg_color: Color, border_color: Color, border_width: int) -> Panel:
	var panel := Panel.new()
	panel.name = panel_name
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
#
	#var style := StyleBoxFlat.new()
	#style.bg_color = bg_color
	#style.border_color = Color.BLACK
	#style.set_border_width_all(border_width)
	#style.set_corner_radius_all(4)
	#style.set_content_margin(SIDE_LEFT, PANEL_PADDING)
	#style.set_content_margin(SIDE_TOP, PANEL_PADDING)
	#style.set_content_margin(SIDE_RIGHT, PANEL_PADDING)
	#style.set_content_margin(SIDE_BOTTOM, PANEL_PADDING)
	#panel.add_theme_stylebox_override("panel", style)

	return panel


func _setup_piano_roll_controls() -> void:
	piano_hide_button = _create_piano_roll_toggle_button("PianoRollHideButton", "Hide")
	piano_hide_button.tooltip_text = "Hide piano roll"
	piano_hide_button.pressed.connect(_on_piano_roll_hide_pressed)
	add_child(piano_hide_button)


func _create_piano_roll_toggle_button(button_name: String, button_text: String) -> Button:
	var button := Button.new()
	button.name = button_name
	button.text = button_text
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.custom_minimum_size = PIANO_ROLL_TOGGLE_SIZE
	button.size = PIANO_ROLL_TOGGLE_SIZE
	button.z_index = 120

	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.94)
	style.border_color = Color(0.08, 0.08, 0.08, 0.92)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin(SIDE_LEFT, 10)
	style.set_content_margin(SIDE_TOP, 5)
	style.set_content_margin(SIDE_RIGHT, 10)
	style.set_content_margin(SIDE_BOTTOM, 5)
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style)
	button.add_theme_stylebox_override("pressed", style)

	return button


func _get_piano_roll_height() -> float:
	if piano_roll_hidden:
		return PIANO_ROLL_HIDDEN_HEIGHT

	return PIANO_ROLL_HEIGHT


func _apply_layout() -> void:
	var piano_height := _get_piano_roll_height()
	var piano_bottom := CANVAS_SIZE.y - OUTER_MARGIN
	var bottom_y = piano_bottom - piano_height
	var top_height = bottom_y - OUTER_MARGIN - PANEL_GAP
	var left_width = LEFT_PANEL_WIDTH
	var tonnetz_x = OUTER_MARGIN + left_width + PANEL_GAP
	var tonnetz_width = CANVAS_SIZE.x - tonnetz_x - OUTER_MARGIN

	left_panel.position = Vector2(OUTER_MARGIN, OUTER_MARGIN)
	left_panel.size = Vector2(left_width, top_height)

	tonnetz_panel.position = Vector2(tonnetz_x, OUTER_MARGIN)
	tonnetz_panel.size = Vector2(tonnetz_width, top_height)

	piano_panel.position = Vector2(OUTER_MARGIN, bottom_y)
	piano_panel.size = Vector2(
		CANVAS_SIZE.x - OUTER_MARGIN * 2.0,
		piano_height
	)
	piano_panel.visible = not piano_roll_hidden

	if voice_scroll:
		voice_scroll.custom_minimum_size = Vector2.ZERO
		voice_scroll.update_minimum_size()

	var tab_size := left_panel.size - Vector2(PANEL_PADDING * 2.0, PANEL_PADDING * 2.0)
	tab_container.custom_minimum_size = Vector2.ZERO
	tab_container.update_minimum_size()
	tab_container.position = left_panel.position + Vector2(PANEL_PADDING, PANEL_PADDING)
	tab_container.size = tab_size
	tab_container.custom_minimum_size = tab_size
	tab_container.update_minimum_size()
	#tab_container.add_theme_font_size_override("font_size", 18)

	if voice_scroll:
		voice_scroll.custom_minimum_size = Vector2(
			0.0,
			max(0.0, tab_container.size.y - TAB_CONTENT_TOP_MARGIN)
		)

	piano_roll_container.position = piano_panel.position + Vector2(PANEL_PADDING, PANEL_PADDING)
	piano_roll_container.size = (
		Vector2.ZERO
		if piano_roll_hidden
		else piano_panel.size - Vector2(PANEL_PADDING * 2.0, PANEL_PADDING * 2.0)
	)
	piano_roll_container.custom_minimum_size = piano_roll_container.size
	piano_roll_container.visible = not piano_roll_hidden

	tonnetz_viewport_container.position = tonnetz_panel.position + Vector2(PANEL_PADDING, PANEL_PADDING)
	tonnetz_viewport_container.size = tonnetz_panel.size - Vector2(PANEL_PADDING * 2.0, PANEL_PADDING * 2.0)
	tonnetz_viewport_container.custom_minimum_size = tonnetz_viewport_container.size
	tonnetz_viewport.size = Vector2i(tonnetz_viewport_container.size)

	config.pianoroll_size = piano_roll_container.size
	config.pianoroll_start_pos = piano_roll_container.position
	config.start_pos = Vector2(0, 20)

	if piano_hide_button:
		piano_hide_button.text = "Show" if piano_roll_hidden else "Hide"
		piano_hide_button.tooltip_text = "Show piano roll" if piano_roll_hidden else "Hide piano roll"
		var hide_button_y := piano_bottom - PIANO_ROLL_TOGGLE_SIZE.y
		if not piano_roll_hidden:
			hide_button_y = bottom_y - PIANO_ROLL_TOGGLE_SIZE.y - 4.0
		piano_hide_button.position = Vector2(
			OUTER_MARGIN + PANEL_PADDING,
			hide_button_y
		)

	if global_play_pause_button:
		global_play_pause_button.position = Vector2(
			CANVAS_SIZE.x - OUTER_MARGIN - 100,
			OUTER_MARGIN
		)

	if play_selected_bar_button:
		play_selected_bar_button.position = Vector2(
			CANVAS_SIZE.x - OUTER_MARGIN - 150,
			OUTER_MARGIN
		)

	if repeat_selected_bar_button:
		repeat_selected_bar_button.position = Vector2(
			CANVAS_SIZE.x - OUTER_MARGIN - 200,
			OUTER_MARGIN
		)

	if export_midi_button:
		export_midi_button.position = Vector2(
			CANVAS_SIZE.x - OUTER_MARGIN - 260,
			OUTER_MARGIN
		)

	if master_bpm_panel:
		master_bpm_panel.position = Vector2(
			CANVAS_SIZE.x - OUTER_MARGIN - 72.0,
			OUTER_MARGIN + 72.0
		)
		master_bpm_panel.size = Vector2(56.0, 300.0)

	if master_reverb_panel:
		master_reverb_panel.position = Vector2(
			CANVAS_SIZE.x - OUTER_MARGIN - 140.0,
			OUTER_MARGIN + 72.0
		)
		master_reverb_panel.size = Vector2(56.0, 300.0)

	if master_distortion_panel:
		master_distortion_panel.position = Vector2(
			CANVAS_SIZE.x - OUTER_MARGIN - 208.0,
			OUTER_MARGIN + 72.0
		)
		master_distortion_panel.size = Vector2(56.0, 300.0)

	if master_delay_panel:
		master_delay_panel.position = Vector2(
			CANVAS_SIZE.x - OUTER_MARGIN - 276.0,
			OUTER_MARGIN + 72.0
		)
		master_delay_panel.size = Vector2(56.0, 300.0)

	if mutation_prompt:
		mutation_prompt.position = Vector2(
			piano_panel.position.x + PANEL_PADDING + 12.0,
			piano_panel.position.y + PANEL_PADDING + 12.0
		)
		mutation_prompt.size = Vector2(760.0, max(160.0, piano_height - PANEL_PADDING * 4.0))
		mutation_prompt.visible = mutation_prompt.visible and not piano_roll_hidden

	if mutation_debug_scroll:
		mutation_debug_scroll.custom_minimum_size = Vector2(720.0, max(120.0, piano_height - PANEL_PADDING * 8.0))


##################################################
########## SET CONTROLS FOR LSYSTEMS #############
##################################################
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

	if lsystems.is_empty():
		voice_list.add_child(_create_empty_lsystem_card())
		return

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


func _create_empty_lsystem_card() -> Control:
	var panel := PanelContainer.new()
	panel.name = "NoLSystemsCard"
	panel.custom_minimum_size = Vector2(LSYSTEM_CARD_WIDTH, 0)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.72)
	style.border_color = Color(0.55, 0.55, 0.55, 1.0)
	style.set_corner_radius_all(28)
	style.set_border_width_all(3)
	style.set_content_margin(SIDE_LEFT, 16)
	style.set_content_margin(SIDE_TOP, 24)
	style.set_content_margin(SIDE_RIGHT, 16)
	style.set_content_margin(SIDE_BOTTOM, 16)
	panel.add_theme_stylebox_override("panel", style)

	var card := VBoxContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(card)

	var title := Label.new()
	title.text = "No voices"
	title.add_theme_font_size_override("font_size", 24)
	card.add_child(title)

	var description := Label.new()
	description.text = "Add an L-system to start again."
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(description)

	var add_button := Button.new()
	add_button.text = "Add L-system"
	add_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	add_button.pressed.connect(_on_add_lsystem_pressed)
	card.add_child(add_button)

	return panel


func _setup_lsystem_voice_list() -> void:
	var margin := MarginContainer.new()
	margin.name = "LSystemContentMargin"
	margin.add_theme_constant_override("margin_top", TAB_CONTENT_TOP_MARGIN)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lsystem_container.add_child(margin)

	voice_scroll = ScrollContainer.new()
	voice_scroll.name = "LSystemVoiceScroll"
	voice_scroll.custom_minimum_size = Vector2(0, 560)
	voice_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	voice_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(voice_scroll)

	voice_list = HBoxContainer.new()
	voice_list.name = "LSystemVoiceList"
	voice_list.add_theme_constant_override("separation", 10)
	voice_list.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	voice_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
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
	panel.custom_minimum_size = Vector2(LSYSTEM_CARD_WIDTH, 0)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.gui_input.connect(_on_lsystem_card_gui_input.bind(index))

	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 1.0) if is_active else Color(0.9, 0.9, 0.9, 0.7)
	style.border_color = color
	style.set_corner_radius_all(28)
	style.set_border_width_all(4)
	style.set_content_margin(SIDE_LEFT, 16)
	style.set_content_margin(SIDE_TOP, 24)
	style.set_content_margin(SIDE_RIGHT, 16)
	style.set_content_margin(SIDE_BOTTOM, 16)
	panel.add_theme_stylebox_override("panel", style)

	var card := VBoxContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_child(card)
	
########## HEADER #############
	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.mouse_filter = Control.MOUSE_FILTER_PASS
	card.add_child(header)
	
########## ID COLOR SWATCH #############
	var swatch := Panel.new()
	swatch.custom_minimum_size = Vector2(30, 30)
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var swatch_style := StyleBoxFlat.new()
	swatch_style.bg_color = color
	swatch_style.set_corner_radius_all(30)
	swatch.add_theme_stylebox_override("panel", swatch_style)
	header.add_child(swatch)
	
########## TITLE #############
	var title := Label.new()
	title.text = "Voice %d" % (index + 1)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fv := FontVariation.new()
	fv.base_font = load("res://fonts/Rubik-VariableFont_wght.ttf")
	fv.variation_opentype = {"weight": 700}
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_font_override("font", fv)
	#title.modulate = Color.BLACK
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

########## ICONS #############

	var active_button := Button.new()
	active_button.flat = true
	active_button.text = "Active" if is_active else "Inactive"
	active_button.toggle_mode = true
	active_button.button_pressed = is_active
	active_button.toggled.connect(_on_voice_active_toggled.bind(index))
	header.add_child(active_button)

	var icon_row := HBoxContainer.new()
	icon_row.add_theme_constant_override("separation", 4)
	icon_row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	card.add_child(icon_row)

	var mute_button := Button.new()
	_setup_lsystem_icon_button(mute_button, UNMUTED_ICON_PATH)
	mute_button.toggle_mode = true
	mute_button.button_pressed = bool(info.get("muted", false))
	_update_voice_mute_button(mute_button, mute_button.button_pressed)
	mute_button.toggled.connect(_on_voice_mute_toggled.bind(index, mute_button))
	icon_row.add_child(mute_button)

	var random_button := Button.new()
	#random_button.text = "Randomize"
	_setup_lsystem_icon_button(random_button, "res://icons/shuffle.svg")

	random_button.pressed.connect(_on_voice_randomize_pressed.bind(index))
	icon_row.add_child(random_button)

	var duplicate_button := Button.new()
	#duplicate_button.text = "Copy"
	_setup_lsystem_icon_button(duplicate_button, "res://icons/duplicate.svg")

	duplicate_button.pressed.connect(_on_voice_duplicate_pressed.bind(index))
	icon_row.add_child(duplicate_button)

	var remove_button := Button.new()
	#remove_button.text = "Remove"
	_setup_lsystem_icon_button(remove_button, "res://icons/cancel.svg")
	remove_button.pressed.connect(_on_voice_remove_pressed.bind(index))
	icon_row.add_child(remove_button)

	var play_button := Button.new()
	#play_button.text = "Play"
	_setup_lsystem_icon_button(play_button, "res://icons/play.svg")
	play_button.pressed.connect(_on_voice_play_pressed.bind(index))
	icon_row.add_child(play_button)

	var stop_button := Button.new()
	#stop_button.text = "Stop"
	_setup_lsystem_icon_button(stop_button, "res://icons/pause.svg")
	stop_button.pressed.connect(_on_voice_stop_pressed.bind(index))
	icon_row.add_child(stop_button)
	
########## STATUS (ORIGIN; BEAT) #############
	var status_row := VBoxContainer.new()
	status_row.mouse_filter = Control.MOUSE_FILTER_PASS
	card.add_child(status_row)

	var origin_label := Label.new()
	#origin_label.modulate = Color.BLACK
	origin_label.text = "Origin: %s" % info.get("origin_label", "Not set")
	origin_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_row.add_child(origin_label)

	var start_label := Label.new()
	#start_label.modulate = Color.BLACK
	start_label.text = "Start: %s" % info.get("start_label", "Not scheduled")
	start_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_row.add_child(start_label)

########## ITERATIONS #############
	var iterations_row := HBoxContainer.new()
	card.add_child(iterations_row)

	var iterations_label := Label.new()
	iterations_label.text = "Iterations"
	#iterations_label.modulate = Color.BLACK
	iterations_row.add_child(iterations_label)

	var iterations_value := Label.new()
	iterations_value.text = str(lsystem.iterations)
	#iterations_value.modulate = Color.BLACK
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

########## VOLUME #############
	var volume_row := HBoxContainer.new()
	card.add_child(volume_row)

	var volume_label := Label.new()
	volume_label.text = "Volume"
	#volume_label.modulate = Color.BLACK
	volume_row.add_child(volume_label)

	var volume_value := Label.new()
	volume_value.text = "%d%%" % int(round(volume * 100.0))
	#volume_value.modulate = Color.BLACK
	volume_value.custom_minimum_size = Vector2(42, 0)
	volume_row.add_child(volume_value)

	var volume_slider := HSlider.new()
	volume_slider.min_value = 0.0
	volume_slider.max_value = 1.0
	volume_slider.step = 0.01
	volume_slider.value = volume
	volume_slider.custom_minimum_size = Vector2(140, 0)
	volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	volume_slider.value_changed.connect(
		_on_voice_volume_changed.bind(index, volume_value)
	)
	volume_row.add_child(volume_slider)

########## GENERATED STRING #############
	var generated_edit := Label.new()
	generated_edit.text = "Generated String: " + lsystem.generated_string
	generated_edit.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	generated_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_child(generated_edit)
	
########## AXIOM #############
	var axiom_row := HBoxContainer.new()
	card.add_child(axiom_row)

	var axiom_label := Label.new()
	axiom_label.text = "Axiom"
	#axiom_label.modulate = Color.BLACK
	axiom_row.add_child(axiom_label)

	var axiom_edit := LineEdit.new()
	axiom_edit.text = lsystem.axiom
	axiom_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	axiom_edit.text_submitted.connect(_on_voice_axiom_submitted.bind(index))
	axiom_row.add_child(axiom_edit)
	
########## PROD RULES #############
	for key in lsystem.rules:
		card.add_child(_create_rule_row(index, key, lsystem.rules[key]))

	return panel

##################################################
########## FUNCTIONS #############
##################################################

func _setup_lsystem_icon_button(button: Button, icon_path: String) -> void:
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.icon = load(icon_path)


func _update_voice_mute_button(button: Button, muted: bool) -> void:
	button.icon = load(MUTED_ICON_PATH if muted else UNMUTED_ICON_PATH)
	button.modulate = Color(0.45, 0.45, 0.45, 1.0) if muted else Color.WHITE
	#button.tooltip_text = "Unmute voice" if muted else "Mute voice"


func _create_rule_row(index: int, symbol: String, production: String) -> Control:
	var row := VBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var input_row := HBoxContainer.new()
	input_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(input_row)

	var symbol_label := Label.new()
	symbol_label.text = symbol + " ->"
	symbol_label.custom_minimum_size = Vector2(28, 30)
	input_row.add_child(symbol_label)

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

##################################################
########## EVENTS #############
##################################################
func _on_lsystem_card_gui_input(event: InputEvent, index: int) -> void:
	if (
		event is InputEventMouseButton
		and event.pressed
		and event.button_index == MOUSE_BUTTON_LEFT
	):
		lsystem_selected.emit(index)
		accept_event()


func _on_voice_active_toggled(_enabled: bool, index: int) -> void:
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

func _on_voice_mute_toggled(muted: bool, index: int, button: Button) -> void:
	_update_voice_mute_button(button, muted)
	lsystem_mute_toggled.emit(index, muted)

func _on_voice_axiom_submitted(new_text: String, index: int) -> void:
	if new_text.is_empty():
		return
	lsystem_axiom_changed.emit(index, new_text[0])

func _on_voice_iterations_value_changed(
	new_value: float,
	iterations_value: Label
) -> void:
	iterations_value.text = str(int(new_value))

func _on_voice_iterations_drag_ended(value_changed: bool, index: int, iterations_slider: HSlider) -> void:
	if not value_changed:
		return
	var iterations := int(iterations_slider.value)
	lsystem_iterations_changed.emit(index, iterations)

func _on_add_lsystem_pressed() -> void:
	add_lsystem_requested.emit()


func _on_voice_volume_changed(new_value: float, index: int, volume_value: Label) -> void:
	volume_value.text = "%d%%" % int(round(new_value * 100.0))
	lsystem_volume_changed.emit(index, new_value)


func _on_master_reverb_changed(new_value: float) -> void:
	var amount: float = clamp(new_value, 0.0, 1.0)
	master_reverb_value_label.text = "%d%%" % int(round(amount * 100.0))
	master_reverb_changed.emit(amount)


func _on_master_delay_changed(new_value: float) -> void:
	var amount: float = clamp(new_value, 0.0, 1.0)
	master_delay_value_label.text = "Off" if amount <= 0.0 else "%d%%" % int(round(amount * 100.0))
	master_delay_changed.emit(amount)


func _on_master_distortion_changed(new_value: float) -> void:
	var amount: float = clamp(new_value, 0.0, 1.0)
	master_distortion_value_label.text = "Off" if amount <= 0.0 else "%d%%" % int(round(amount * 100.0))
	master_distortion_changed.emit(amount)


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


func _setup_global_play_pause_button() -> void:
	repeat_selected_bar_button = _create_top_icon_button(
		"RepeatSelectedBarButton",
		"res://icons/repeat.svg",
		"Repeat selected bars"
	)
	repeat_selected_bar_button.toggle_mode = true
	repeat_selected_bar_button.toggled.connect(_on_repeat_selected_bar_toggled)
	add_child(repeat_selected_bar_button)
	repeat_selected_bar_button.z_index = 100

	play_selected_bar_button = _create_top_icon_button(
		"PlaySelectedBarButton",
		"res://icons/right.svg",
		"Play selected bar"
	)
	play_selected_bar_button.pressed.connect(_on_play_selected_bar_pressed)
	add_child(play_selected_bar_button)
	play_selected_bar_button.z_index = 100

	global_play_pause_button = _create_top_icon_button(
		"GlobalPlayPauseButton",
		"res://icons/pause.svg",
		"Pause"
	)
	global_play_pause_button.pressed.connect(_on_global_play_pause_pressed)
	add_child(global_play_pause_button)
	global_play_pause_button.z_index = 100

	export_midi_button = Button.new()
	export_midi_button.name = "ExportMidiButton"
	export_midi_button.text = "MIDI"
	export_midi_button.tooltip_text = "Export MIDI"
	export_midi_button.focus_mode = Control.FOCUS_NONE
	export_midi_button.custom_minimum_size = Vector2(56, 40)
	export_midi_button.size = Vector2(56, 40)
	export_midi_button.mouse_filter = Control.MOUSE_FILTER_STOP
	export_midi_button.pressed.connect(_on_export_midi_pressed)
	add_child(export_midi_button)
	export_midi_button.z_index = 100


func _setup_master_bpm_control() -> void:
	master_bpm_panel = PanelContainer.new()
	master_bpm_panel.name = "MasterBPMPanel"
	master_bpm_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	master_bpm_panel.z_index = 100

	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.92)
	style.border_color = Color(0.08, 0.08, 0.08, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin(SIDE_LEFT, 8)
	style.set_content_margin(SIDE_TOP, 10)
	style.set_content_margin(SIDE_RIGHT, 8)
	style.set_content_margin(SIDE_BOTTOM, 10)
	master_bpm_panel.add_theme_stylebox_override("panel", style)
	add_child(master_bpm_panel)

	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	master_bpm_panel.add_child(column)

	var title := _create_label("BPM")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(title)

	bpm_value_label = _create_label("120")
	bpm_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bpm_value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(bpm_value_label)

	bpm_slider = VSlider.new()
	bpm_slider.name = "BPMSlider"
	bpm_slider.min_value = 20.0
	bpm_slider.max_value = 200.0
	bpm_slider.step = 10.0
	bpm_slider.value = 120.0
	bpm_slider.exp_edit = true
	bpm_slider.custom_minimum_size = Vector2(32, 210)
	bpm_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bpm_slider.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bpm_slider.tooltip_text = "BPM"
	bpm_slider.value_changed.connect(_on_bpm_value_changed)
	bpm_slider.drag_ended.connect(on_bpm_changed)
	column.add_child(bpm_slider)


func _setup_master_reverb_control() -> void:
	master_reverb_panel = PanelContainer.new()
	master_reverb_panel.name = "MasterReverbPanel"
	master_reverb_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	master_reverb_panel.z_index = 100

	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.92)
	style.border_color = Color(0.08, 0.08, 0.08, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin(SIDE_LEFT, 8)
	style.set_content_margin(SIDE_TOP, 10)
	style.set_content_margin(SIDE_RIGHT, 8)
	style.set_content_margin(SIDE_BOTTOM, 10)
	master_reverb_panel.add_theme_stylebox_override("panel", style)
	add_child(master_reverb_panel)

	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	master_reverb_panel.add_child(column)

	var title := _create_label("Reverb")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(title)

	master_reverb_value_label = _create_label("0%")
	master_reverb_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	master_reverb_value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(master_reverb_value_label)

	master_reverb_slider = VSlider.new()
	master_reverb_slider.name = "MasterReverbSlider"
	master_reverb_slider.min_value = 0.0
	master_reverb_slider.max_value = 1.0
	master_reverb_slider.step = 0.01
	master_reverb_slider.value = 0.0
	master_reverb_slider.custom_minimum_size = Vector2(32, 210)
	master_reverb_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	master_reverb_slider.size_flags_vertical = Control.SIZE_EXPAND_FILL
	master_reverb_slider.tooltip_text = "Master reverb"
	master_reverb_slider.value_changed.connect(_on_master_reverb_changed)
	column.add_child(master_reverb_slider)


func _setup_master_delay_control() -> void:
	var controls := _create_master_slider_control(
		"MasterDelayPanel",
		"MasterDelaySlider",
		"Delay",
		"Off",
		0.0,
		1.0,
		0.01,
		0.0,
		"Master delay"
	)
	master_delay_panel = controls["panel"]
	master_delay_value_label = controls["value_label"]
	master_delay_slider = controls["slider"]
	master_delay_slider.value_changed.connect(_on_master_delay_changed)


func _setup_master_distortion_control() -> void:
	var controls := _create_master_slider_control(
		"MasterDistortionPanel",
		"MasterDistortionSlider",
		"Drive",
		"Off",
		0.0,
		1.0,
		0.01,
		0.0,
		"Master distortion"
	)
	master_distortion_panel = controls["panel"]
	master_distortion_value_label = controls["value_label"]
	master_distortion_slider = controls["slider"]
	master_distortion_slider.value_changed.connect(_on_master_distortion_changed)


func _create_master_slider_control(
	panel_name: String,
	slider_name: String,
	title_text: String,
	value_text: String,
	min_value: float,
	max_value: float,
	step: float,
	initial_value: float,
	tooltip: String
) -> Dictionary:
	var panel := PanelContainer.new()
	panel.name = panel_name
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.z_index = 100

	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.92)
	style.border_color = Color(0.08, 0.08, 0.08, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin(SIDE_LEFT, 8)
	style.set_content_margin(SIDE_TOP, 10)
	style.set_content_margin(SIDE_RIGHT, 8)
	style.set_content_margin(SIDE_BOTTOM, 10)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(column)

	var title := _create_label(title_text)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(title)

	var value_label := _create_label(value_text)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(value_label)

	var slider := VSlider.new()
	slider.name = slider_name
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.value = initial_value
	slider.custom_minimum_size = Vector2(32, 210)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_EXPAND_FILL
	slider.tooltip_text = tooltip
	column.add_child(slider)

	return {
		"panel": panel,
		"value_label": value_label,
		"slider": slider
	}


func _setup_export_midi_dialog() -> void:
	export_midi_dialog = FileDialog.new()
	export_midi_dialog.name = "ExportMidiDialog"
	export_midi_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	export_midi_dialog.access = FileDialog.ACCESS_FILESYSTEM
	export_midi_dialog.title = "Export MIDI"
	export_midi_dialog.filters = PackedStringArray(["*.mid ; MIDI files"])
	export_midi_dialog.current_file = _build_default_midi_filename()
	export_midi_dialog.file_selected.connect(_on_export_midi_file_selected)
	add_child(export_midi_dialog)


func _setup_mutation_prompt() -> void:
	mutation_prompt = PanelContainer.new()
	mutation_prompt.name = "MutationPrompt"
	mutation_prompt.visible = false
	mutation_prompt.mouse_filter = Control.MOUSE_FILTER_STOP
	mutation_prompt.z_index = 110

	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.96)
	style.border_color = Color(0.08, 0.08, 0.08, 0.95)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin(SIDE_LEFT, 12)
	style.set_content_margin(SIDE_TOP, 10)
	style.set_content_margin(SIDE_RIGHT, 12)
	style.set_content_margin(SIDE_BOTTOM, 10)
	mutation_prompt.add_theme_stylebox_override("panel", style)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	mutation_prompt.add_child(content)

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 10)
	content.add_child(action_row)

	var label := Label.new()
	label.text = "Mutate selection from Voice"
	label.modulate = Color.BLACK
	action_row.add_child(label)

	mutation_voice_button_row = HBoxContainer.new()
	mutation_voice_button_row.add_theme_constant_override("separation", 6)
	action_row.add_child(mutation_voice_button_row)

	mutation_debug_scroll = ScrollContainer.new()
	mutation_debug_scroll.name = "MutationDebugScroll"
	mutation_debug_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mutation_debug_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mutation_debug_scroll.custom_minimum_size = Vector2(520.0, 180.0)
	content.add_child(mutation_debug_scroll)

	mutation_debug_label = Label.new()
	mutation_debug_label.modulate = Color.BLACK
	mutation_debug_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mutation_debug_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mutation_debug_scroll.add_child(mutation_debug_label)

	mutation_decision_row = HBoxContainer.new()
	mutation_decision_row.add_theme_constant_override("separation", 8)
	mutation_decision_row.visible = false
	content.add_child(mutation_decision_row)

	mutation_side_row = HBoxContainer.new()
	mutation_side_row.add_theme_constant_override("separation", 8)
	mutation_decision_row.add_child(mutation_side_row)

	mutation_original_button = Button.new()
	mutation_original_button.text = "Original"
	mutation_original_button.tooltip_text = "Listen to the current L-system"
	mutation_original_button.toggle_mode = true
	mutation_original_button.pressed.connect(_on_mutation_original_pressed)
	mutation_side_row.add_child(mutation_original_button)

	mutation_candidate_button = Button.new()
	mutation_candidate_button.text = "Candidate"
	mutation_candidate_button.tooltip_text = "Listen to the proposed mutation"
	mutation_candidate_button.toggle_mode = true
	mutation_candidate_button.pressed.connect(_on_mutation_candidate_pressed)
	mutation_side_row.add_child(mutation_candidate_button)

	mutation_apply_button = Button.new()
	mutation_apply_button.text = "Apply"
	mutation_apply_button.tooltip_text = "Apply this proposed mutation"
	mutation_apply_button.pressed.connect(_on_mutation_apply_pressed)
	mutation_decision_row.add_child(mutation_apply_button)

	mutation_cancel_button = Button.new()
	mutation_cancel_button.text = "Cancel"
	mutation_cancel_button.tooltip_text = "Discard this proposed mutation"
	mutation_cancel_button.pressed.connect(_on_mutation_cancel_pressed)
	mutation_decision_row.add_child(mutation_cancel_button)

	add_child(mutation_prompt)


func show_mutation_prompt(colors: Array, debug_text: String = "", target_index: int = -1) -> void:
	if not mutation_prompt or not mutation_voice_button_row:
		return

	for child in mutation_voice_button_row.get_children():
		child.queue_free()

	for index in range(colors.size()):
		mutation_voice_button_row.add_child(
			_create_mutation_voice_button(index, colors[index], index == target_index)
		)

	if mutation_debug_label:
		mutation_debug_label.text = debug_text

	if mutation_decision_row:
		mutation_decision_row.visible = false

	mutation_prompt.visible = not colors.is_empty()


func show_mutation_proposition(proposition_text: String, show_decision_buttons: bool = true) -> void:
	if mutation_debug_label:
		mutation_debug_label.text = proposition_text

	if mutation_decision_row:
		mutation_decision_row.visible = show_decision_buttons

	if show_decision_buttons:
		set_mutation_side_visual("candidate")


func hide_mutation_prompt() -> void:
	if mutation_prompt:
		mutation_prompt.visible = false


func _create_mutation_voice_button(index: int, color: Color, is_target: bool = false) -> Button:
	var button := Button.new()
	button.text = str(index + 1)
	button.tooltip_text = "Mutate from Voice %d" % (index + 1)
	button.custom_minimum_size = Vector2(34, 30)
	button.focus_mode = Control.FOCUS_NONE

	var style := StyleBoxFlat.new()
	style.bg_color = color if is_target else color.lerp(Color(0.72, 0.72, 0.72, 1.0), 0.68)
	style.border_color = Color(0.06, 0.06, 0.06, 1.0) if is_target else Color(0.55, 0.55, 0.55, 1.0)
	style.set_border_width_all(4 if is_target else 1)
	style.set_corner_radius_all(6)
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style)
	button.add_theme_stylebox_override("pressed", style)
	button.modulate = Color.WHITE if is_target else Color(1.0, 1.0, 1.0, 0.62)
	button.pressed.connect(_on_mutation_voice_pressed.bind(index))

	return button


func _create_top_icon_button(button_name: String, icon_path: String, tooltip: String) -> Button:
	var button := Button.new()
	button.name = button_name
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(40, 40)
	button.size = Vector2(50,50)
	button.icon = load(icon_path)
	button.tooltip_text = tooltip
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	return button


func _on_global_play_pause_pressed() -> void:
	global_paused = not global_paused
	set_global_paused_visual(global_paused)
	global_play_pause_toggled.emit(global_paused)


func _on_piano_roll_hide_pressed() -> void:
	piano_roll_hidden = not piano_roll_hidden
	_apply_layout()


func _on_play_selected_bar_pressed() -> void:
	play_selected_bar_requested.emit()


func _on_repeat_selected_bar_toggled(enabled: bool) -> void:
	set_repeat_selected_bar_visual(enabled)
	repeat_selected_bar_toggled.emit(enabled)


func _on_export_midi_pressed() -> void:
	if not export_midi_dialog:
		return

	export_midi_dialog.current_file = _build_default_midi_filename()
	export_midi_dialog.popup_centered(Vector2i(760, 520))


func _on_export_midi_file_selected(path: String) -> void:
	if path.get_extension().to_lower() != "mid":
		path += ".mid"

	export_midi_requested.emit(path)


func _build_default_midi_filename() -> String:
	var date := Time.get_datetime_dict_from_system()
	return "tonnetz_%04d%02d%02d_%02d%02d.mid" % [
		int(date["year"]),
		int(date["month"]),
		int(date["day"]),
		int(date["hour"]),
		int(date["minute"])
	]


func _on_mutation_voice_pressed(index: int) -> void:
	mutate_selection_requested.emit(index)

func _on_mutation_original_pressed() -> void:
	set_mutation_side_visual("original")
	mutation_side_selected.emit("original")


func _on_mutation_candidate_pressed() -> void:
	set_mutation_side_visual("candidate")
	mutation_side_selected.emit("candidate")


func _on_mutation_apply_pressed() -> void:
	mutation_apply_requested.emit()


func _on_mutation_cancel_pressed() -> void:
	if mutation_decision_row:
		mutation_decision_row.visible = false

	mutation_cancel_requested.emit()


func set_mutation_side_visual(side: String) -> void:
	if mutation_original_button:
		mutation_original_button.set_pressed_no_signal(side == "original")

	if mutation_candidate_button:
		mutation_candidate_button.set_pressed_no_signal(side == "candidate")


func set_repeat_selected_bar_visual(enabled: bool) -> void:
	if repeat_selected_bar_button:
		repeat_selected_bar_button.set_pressed_no_signal(enabled)
		repeat_selected_bar_button.modulate = Color(0.25, 0.95, 0.62, 1.0) if enabled else Color.WHITE


func set_global_paused_visual(paused: bool) -> void:
	global_paused = paused
	global_play_pause_button.icon = load("res://icons/play.svg") if global_paused else load("res://icons/pause.svg")
	global_play_pause_button.tooltip_text = "Play" if global_paused else "Pause"


func _on_length_changed(value_changed: bool) -> void:
	var new_value := int(length_slider.value)

	config.length_bars = new_value

	length_value_label.text = str(new_value)

	emit_signal("length_changed", new_value)

func changeInstrument(index: int) -> void:
	emit_signal("instrument_changed", index)

func toggleAnimation(toggled_on: bool) -> void:
	config.animations_on = toggled_on
	_update_animation_switch_text()

func _on_bpm_value_changed(new_value: float) -> void:
	bpm_value_label.text = str(int(new_value))

func on_bpm_changed(ended: bool) -> void:
	if not ended:
		return
	var new_value := int(bpm_slider.value)
	config.bpm = new_value
	bpm_value_label.text = str(new_value)

func _update_animation_switch_text() -> void:
	animation_switch.text = "Animation On" if config.animations_on else "Animation Off"
