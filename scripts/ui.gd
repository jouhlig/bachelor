extends Control

##################################################
########## SIGNALS #############
##################################################
signal length_changed(new_value: int)
signal add_random_lsystem_requested
signal lsystem_selected(index: int)
signal lsystem_randomize_requested(index: int)
signal lsystem_duplicate_requested(index: int)
signal lsystem_remove_requested(index: int)
signal lsystem_axiom_changed(index: int, new_axiom: String)
signal lsystem_iterations_changed(index: int, iterations: int)
signal lsystem_rule_changed(index: int, symbol: String, production: String)
signal lsystem_volume_changed(index: int, volume: float)
signal lsystem_mute_toggled(index: int, muted: bool)
signal walk_recording_started
signal walk_recording_cancelled
signal walk_recording_undo_requested
signal walk_recording_duration_changed(duration_beats: float)
signal walk_lsystem_generate_requested
signal walk_lsystem_regenerate_requested
signal tonnetz_clicked(world_position: Vector2)
signal global_play_pause_toggled(paused: bool)
signal export_midi_requested(path: String)

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
const TONNETZ_MIN_ZOOM := 0.35
const TONNETZ_MAX_ZOOM := 3.0
const TONNETZ_WHEEL_ZOOM_STEP := 1.08
const WALK_RECORDER_PANEL_WIDTH := 740.0


##################################################
########## VAR DECLARATIO S #############
##################################################
var left_panel: Panel
var tonnetz_panel: Panel
var piano_panel: Panel
var piano_hide_button: Button
var voice_scroll: ScrollContainer
var voice_list: HBoxContainer
var length_value_label: Label
var length_slider: HSlider
var bpm_value_label: Label
var bpm_slider: Slider
var animation_switch: CheckButton
var walk_recorder_panel: PanelContainer
var walk_record_button: Button
var walk_undo_button: Button
var walk_cancel_button: Button
var walk_generate_button: Button
var walk_regenerate_button: Button
var walk_duration_button: OptionButton
var global_play_pause_button: Button
var export_midi_button: Button
var export_midi_dialog: FileDialog
var master_bpm_panel: PanelContainer
var global_paused := false
var piano_roll_hidden := true
var tonnetz_pan_dragging := false
var tonnetz_touch_points := {}
var tonnetz_view_offset := Vector2.ZERO
var tonnetz_view_zoom := 1.0
var icon_cache := {}

##################################################
########## SETUP UI #############
##################################################
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	tab_container.clip_contents = true
	lsystem_container.clip_contents = true
	other_container.clip_contents = true

	_setup_layout_panels()
	_setup_piano_roll_controls()
	_setup_global_play_pause_button()
	_setup_walk_recorder_controls()
	_setup_master_bpm_control()
	_setup_export_midi_dialog()
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

	var viewport_position := screen_position - tonnetz_viewport_container.global_position
	return _get_tonnetz_world_position_from_viewport(viewport_position)

func _get_tonnetz_world_position_from_viewport(viewport_position: Vector2) -> Vector2:
	if not tonnetz_viewport:
		return viewport_position

	return tonnetz_viewport.canvas_transform.affine_inverse() * viewport_position


func _on_tonnetz_viewport_gui_input(event: InputEvent) -> void:
	if event is InputEventMagnifyGesture:
		_zoom_tonnetz_at_viewport_position(event.factor, event.position)
		accept_event()
		return

	if event is InputEventPanGesture:
		_pan_tonnetz(-event.delta)
		accept_event()
		return

	if (
		event is InputEventMouseButton
		and event.pressed
		and event.button_index == MOUSE_BUTTON_LEFT
	):
		tonnetz_clicked.emit(_get_tonnetz_world_position_from_viewport(event.position))
		accept_event()
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT or event.button_index == MOUSE_BUTTON_MIDDLE:
			tonnetz_pan_dragging = event.pressed
			accept_event()
			return

		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_tonnetz_at_viewport_position(TONNETZ_WHEEL_ZOOM_STEP, event.position)
			accept_event()
			return

		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_tonnetz_at_viewport_position(1.0 / TONNETZ_WHEEL_ZOOM_STEP, event.position)
			accept_event()
			return

	if event is InputEventMouseMotion and tonnetz_pan_dragging:
		_pan_tonnetz(event.relative)
		accept_event()
		return

	if event is InputEventScreenTouch:
		if event.pressed:
			tonnetz_touch_points[event.index] = event.position
		else:
			tonnetz_touch_points.erase(event.index)
		accept_event()
		return

	if event is InputEventScreenDrag:
		_update_tonnetz_touch_drag(event)
		accept_event()
		return

func _pan_tonnetz(delta: Vector2) -> void:
	tonnetz_view_offset += delta
	_apply_tonnetz_view_transform()

func _zoom_tonnetz_at_viewport_position(factor: float, viewport_position: Vector2) -> void:
	if not tonnetz_viewport or factor <= 0.0:
		return

	var old_zoom := tonnetz_view_zoom
	var new_zoom = clamp(old_zoom * factor, TONNETZ_MIN_ZOOM, TONNETZ_MAX_ZOOM)

	if is_equal_approx(new_zoom, old_zoom):
		return

	var world_position_before_zoom := (
		tonnetz_viewport.canvas_transform.affine_inverse() * viewport_position
	)
	tonnetz_view_zoom = new_zoom
	_apply_tonnetz_view_transform()
	var viewport_position_after_zoom := tonnetz_viewport.canvas_transform * world_position_before_zoom
	tonnetz_view_offset += viewport_position - viewport_position_after_zoom
	_apply_tonnetz_view_transform()

func _apply_tonnetz_view_transform() -> void:
	if not tonnetz_viewport:
		return

	var transform := Transform2D.IDENTITY
	transform = transform.scaled(Vector2(tonnetz_view_zoom, tonnetz_view_zoom))
	transform.origin = tonnetz_view_offset
	tonnetz_viewport.canvas_transform = transform

func _update_tonnetz_touch_drag(event: InputEventScreenDrag) -> void:
	if not tonnetz_touch_points.has(event.index):
		tonnetz_touch_points[event.index] = event.position
		return

	var previous_points := tonnetz_touch_points.duplicate()
	tonnetz_touch_points[event.index] = event.position

	if tonnetz_touch_points.size() == 1:
		_pan_tonnetz(event.relative)
		return

	if tonnetz_touch_points.size() != 2 or previous_points.size() != 2:
		return

	var previous_pair := previous_points.values()
	var current_pair := tonnetz_touch_points.values()
	var previous_center :Vector2= (previous_pair[0] + previous_pair[1]) * 0.5
	var current_center :Vector2= (current_pair[0] + current_pair[1]) * 0.5
	var previous_distance: float = previous_pair[0].distance_to(previous_pair[1])
	var current_distance: float = current_pair[0].distance_to(current_pair[1])

	_pan_tonnetz(current_center - previous_center)

	if previous_distance > 0.001:
		_zoom_tonnetz_at_viewport_position(
			current_distance / previous_distance,
			current_center
		)

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

func _create_walk_recorder_controls() -> Control:
	var row := HBoxContainer.new()
	row.name = "WalkRecorderControls"
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.alignment = BoxContainer.ALIGNMENT_CENTER

	var label := _create_label("Walk")
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)

	var duration_row := HBoxContainer.new()
	duration_row.add_theme_constant_override("separation", 4)
	duration_row.add_child(_create_label("Step length"))

	walk_duration_button = OptionButton.new()
	walk_duration_button.name = "WalkDurationButton"
	walk_duration_button.custom_minimum_size = Vector2(96, 0)
	walk_duration_button.add_item("Full", 0)
	walk_duration_button.set_item_metadata(0, 4.0)
	walk_duration_button.add_item("Half", 1)
	walk_duration_button.set_item_metadata(1, 2.0)
	walk_duration_button.add_item("Quarter", 2)
	walk_duration_button.set_item_metadata(2, 1.0)
	walk_duration_button.add_item("Eighth", 3)
	walk_duration_button.set_item_metadata(3, 0.5)
	walk_duration_button.select(2)
	walk_duration_button.item_selected.connect(_on_walk_duration_selected)
	duration_row.add_child(walk_duration_button)
	row.add_child(duration_row)

	walk_record_button = Button.new()
	walk_record_button.text = "Start Recording"
	walk_record_button.toggle_mode = true
	walk_record_button.pressed.connect(_on_walk_record_pressed)
	row.add_child(walk_record_button)

	walk_generate_button = Button.new()
	walk_generate_button.text = "Generate L-system"
	walk_generate_button.tooltip_text = "Generate an L-system from the last recorded walk"
	walk_generate_button.pressed.connect(_on_walk_generate_pressed)
	row.add_child(walk_generate_button)

	walk_regenerate_button = Button.new()
	walk_regenerate_button.text = "Regenerate"
	walk_regenerate_button.tooltip_text = "Try evolution again with the last recorded walk"
	walk_regenerate_button.pressed.connect(_on_walk_regenerate_pressed)
	row.add_child(walk_regenerate_button)

	walk_undo_button = Button.new()
	walk_undo_button.text = "Undo"
	walk_undo_button.pressed.connect(_on_walk_undo_pressed)
	row.add_child(walk_undo_button)

	walk_cancel_button = Button.new()
	walk_cancel_button.text = "Cancel"
	walk_cancel_button.pressed.connect(_on_walk_cancel_pressed)
	row.add_child(walk_cancel_button)

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
	if not tonnetz_viewport_container.stretch:
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

	if export_midi_button:
		export_midi_button.position = Vector2(
			CANVAS_SIZE.x - OUTER_MARGIN - 150,
			OUTER_MARGIN
		)

	if walk_recorder_panel:
		walk_recorder_panel.position = Vector2(
			CANVAS_SIZE.x - OUTER_MARGIN - 150.0 - WALK_RECORDER_PANEL_WIDTH - 12.0,
			OUTER_MARGIN
		)
		walk_recorder_panel.size = Vector2(WALK_RECORDER_PANEL_WIDTH, 40.0)

	if master_bpm_panel:
		master_bpm_panel.position = Vector2(
			CANVAS_SIZE.x - OUTER_MARGIN - 72.0,
			OUTER_MARGIN + 72.0
		)
		master_bpm_panel.size = Vector2(56.0, 300.0)

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
	add_button.text = "Add random L-system"
	add_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	add_button.pressed.connect(_on_add_random_lsystem_pressed)
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
	lsystem,
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

	if info.has("fitness"):
		var fitness_value := float(info.get("fitness", INF))
		var fitness_label := Label.new()
		fitness_label.text = "Fitness: %s" % _format_voice_fitness(fitness_value)
		fitness_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		status_row.add_child(fitness_label)

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

	_add_voice_volume_controls(card, index, volume)

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
	button.icon = _get_icon(icon_path)


func _update_voice_mute_button(button: Button, muted: bool) -> void:
	button.icon = _get_icon(MUTED_ICON_PATH if muted else UNMUTED_ICON_PATH)
	button.modulate = Color(0.45, 0.45, 0.45, 1.0) if muted else Color.WHITE
	#button.tooltip_text = "Unmute voice" if muted else "Mute voice"

func _get_icon(icon_path: String):
	if not icon_cache.has(icon_path):
		icon_cache[icon_path] = load(icon_path)

	return icon_cache[icon_path]

func _format_voice_fitness(fitness: float) -> String:
	if is_nan(fitness):
		return "n/a"

	if is_inf(fitness):
		return "INF"

	if abs(fitness) >= 1000.0:
		return "%.2f" % fitness

	return "%.3f" % fitness

func _add_voice_volume_controls(card: VBoxContainer, index: int, volume: float) -> void:
	var volume_row := HBoxContainer.new()
	card.add_child(volume_row)

	var volume_label := Label.new()
	volume_label.text = "Volume"
	volume_row.add_child(volume_label)

	var volume_value := Label.new()
	volume_value.text = "%d%%" % int(round(volume * 100.0))
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

func _on_add_random_lsystem_pressed() -> void:
	add_random_lsystem_requested.emit()

func _on_walk_record_pressed() -> void:
	walk_record_button.button_pressed = true
	walk_recording_started.emit()

func _on_walk_undo_pressed() -> void:
	walk_recording_undo_requested.emit()

func _on_walk_generate_pressed() -> void:
	walk_record_button.button_pressed = false
	walk_lsystem_generate_requested.emit()

func _on_walk_regenerate_pressed() -> void:
	walk_lsystem_regenerate_requested.emit()

func _on_walk_cancel_pressed() -> void:
	walk_record_button.button_pressed = false
	walk_recording_cancelled.emit()

func _on_walk_duration_selected(index: int) -> void:
	var duration = walk_duration_button.get_item_metadata(index)
	walk_recording_duration_changed.emit(float(duration))


func _on_voice_volume_changed(new_value: float, index: int, volume_value: Label) -> void:
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
	regex.compile(LSystem.rule_symbol_pattern())

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


func _setup_walk_recorder_controls() -> void:
	walk_recorder_panel = PanelContainer.new()
	walk_recorder_panel.name = "WalkRecorderPanel"
	walk_recorder_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	walk_recorder_panel.z_index = 100
	walk_recorder_panel.custom_minimum_size = Vector2(WALK_RECORDER_PANEL_WIDTH, 40.0)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.92)
	style.border_color = Color(0.08, 0.08, 0.08, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin(SIDE_LEFT, 10)
	style.set_content_margin(SIDE_TOP, 4)
	style.set_content_margin(SIDE_RIGHT, 10)
	style.set_content_margin(SIDE_BOTTOM, 4)
	walk_recorder_panel.add_theme_stylebox_override("panel", style)
	add_child(walk_recorder_panel)

	walk_recorder_panel.add_child(_create_walk_recorder_controls())


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


func _create_top_icon_button(button_name: String, icon_path: String, tooltip: String) -> Button:
	var button := Button.new()
	button.name = button_name
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(40, 40)
	button.size = Vector2(50,50)
	button.icon = _get_icon(icon_path)
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


func set_global_paused_visual(paused: bool) -> void:
	global_paused = paused
	global_play_pause_button.icon = _get_icon("res://icons/play.svg" if global_paused else "res://icons/pause.svg")
	global_play_pause_button.tooltip_text = "Play" if global_paused else "Pause"


func _on_length_changed(value_changed: bool) -> void:
	var new_value := int(length_slider.value)

	config.length_bars = new_value

	length_value_label.text = str(new_value)

	emit_signal("length_changed", new_value)

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
