extends Control

##################################################
########## SIGNALS #############
##################################################
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
signal lsystem_preview_direction_changed(index: int, anchor_mode: String, delta: int)
signal walk_recording_started
signal walk_recording_cancelled
signal walk_recording_undo_requested
signal walk_recording_duration_changed(duration_beats: float)
signal walk_lsystem_generate_requested
signal walk_lsystem_regenerate_requested
signal tonnetz_clicked(world_position: Vector2)
signal global_play_pause_toggled(paused: bool)
signal stop_all_lsystems_requested
signal tonnetz_visibility_toggled(visible: bool)
signal export_midi_requested(path: String)
signal export_midi_voice_requested(index: int, path: String)

##################################################
########## ONREADY VARS #############
##################################################
@onready var config = Config.config

@onready var lsystem_container = $TabContainer/LSystems
@onready var tab_container = $TabContainer
@onready var tonnetz_viewport_container: SubViewportContainer = $TonnetzViewportContainer
@onready var tonnetz_viewport: SubViewport = $TonnetzViewportContainer/TonnetzViewport

##################################################
########## CONST #############
##################################################
const OUTER_MARGIN := 0.0
const LEFT_PANEL_MIN_WIDTH := 380.0
const LEFT_PANEL_MAX_WIDTH := 560.0
const LEFT_PANEL_WIDTH_RATIO := 0.28
const TONNETZ_MIN_WIDTH := 420.0

const PANEL_PADDING := 12.0
const PANEL_GAP := 12.0
const TAB_CONTENT_TOP_MARGIN := 14.0
const LSYSTEM_CARD_WIDTH := 300.0
const MUTED_ICON_PATH := "res://icons/muted.svg"
const UNMUTED_ICON_PATH := "res://icons/unmuted.svg"
const TONNETZ_MIN_ZOOM := 0.35
const TONNETZ_MAX_ZOOM := 3.0
const TONNETZ_WHEEL_ZOOM_STEP := 1.08
const GENERAL_PANEL_HEIGHT := 190.0
const WALK_RECORDER_PANEL_HEIGHT := 160.0
const WALK_PREVIEW_SIZE := Vector2(252.0, 82.0)
const WALK_PREVIEW_NODE_DIRECTIONS := [
	Vector2i(1, -1), Vector2i(0, -1), Vector2i(-1, 0),
	Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 0)
]
const WALK_PREVIEW_NODE_STEP := 18.0
const WALK_PREVIEW_TRIANGLE_STEP := 18.0
const WALK_PREVIEW_MAX_SYMBOLS := 220


##################################################
########## VAR DECLARATIO S #############
##################################################
var left_panel: Panel
var tonnetz_panel: Panel
var controls_panel: Panel
var controls_container: VBoxContainer
var lsystem_content_container: VBoxContainer
var voice_scroll: ScrollContainer
var voice_list: HBoxContainer
var bpm_value_label: Label
var bpm_slider: Slider
var walk_recorder_panel: PanelContainer
var walk_record_button: Button
var walk_undo_button: Button
var walk_cancel_button: Button
var walk_generate_button: Button
var walk_regenerate_button: Button
var walk_duration_button: OptionButton
var global_play_pause_button: Button
var tonnetz_fullscreen_button: Button
var tonnetz_fullscreen_exit_button: Button
var stop_all_button: Button
var export_midi_button: Button
var export_midi_dialog: FileDialog
var master_bpm_panel: PanelContainer
var export_midi_voice_index := -1
var global_paused := false
var tonnetz_fullscreen := false
var tonnetz_pan_dragging := false
var tonnetz_touch_points := {}
var tonnetz_view_offset := Vector2.ZERO
var tonnetz_view_zoom := 1.0
var tonnetz_normal_view_offset := Vector2.ZERO
var tonnetz_normal_view_zoom := 1.0
var tonnetz_bounds := Rect2()
var tonnetz_bounds_available := false
var icon_cache := {}

##################################################
########## SETUP UI #############
##################################################
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	tab_container.clip_contents = true
	lsystem_container.clip_contents = true
	tab_container.visible = false

	_setup_layout_panels()
	_setup_global_play_pause_button()
	_setup_master_bpm_control()
	_setup_walk_recorder_controls()
	_setup_export_midi_dialog()
	_apply_layout()
	tonnetz_viewport_container.mouse_filter = Control.MOUSE_FILTER_PASS
	tonnetz_viewport_container.gui_input.connect(_on_tonnetz_viewport_gui_input)
	_setup_lsystem_voice_list()
	_apply_layout()
	
	bpm_value_label.text = str(config.bpm)
	bpm_slider.value = config.bpm

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

func _create_walk_recorder_controls() -> Control:
	var column := VBoxContainer.new()
	column.name = "WalkRecorderControls"
	column.add_theme_constant_override("separation", 8)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var label := _create_label("Walk")
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	column.add_child(label)

	var duration_row := HBoxContainer.new()
	duration_row.add_theme_constant_override("separation", 4)
	duration_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	duration_row.add_child(_create_label("Step length"))

	walk_duration_button = OptionButton.new()
	walk_duration_button.name = "WalkDurationButton"
	walk_duration_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	column.add_child(duration_row)

	var record_row := HBoxContainer.new()
	record_row.add_theme_constant_override("separation", 6)
	record_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	walk_record_button = Button.new()
	walk_record_button.text = "Start Recording"
	walk_record_button.toggle_mode = true
	walk_record_button.pressed.connect(_on_walk_record_pressed)
	record_row.add_child(walk_record_button)

	walk_generate_button = Button.new()
	walk_generate_button.text = "Generate"
	walk_generate_button.tooltip_text = "Generate an L-system from the last recorded walk"
	walk_generate_button.pressed.connect(_on_walk_generate_pressed)
	record_row.add_child(walk_generate_button)
	column.add_child(record_row)

	var edit_row := HBoxContainer.new()
	edit_row.add_theme_constant_override("separation", 6)
	edit_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	walk_regenerate_button = Button.new()
	walk_regenerate_button.text = "Regenerate"
	walk_regenerate_button.tooltip_text = "Try evolution again with the last recorded walk"
	walk_regenerate_button.pressed.connect(_on_walk_regenerate_pressed)
	edit_row.add_child(walk_regenerate_button)

	walk_undo_button = Button.new()
	walk_undo_button.text = "Undo"
	walk_undo_button.pressed.connect(_on_walk_undo_pressed)
	edit_row.add_child(walk_undo_button)

	walk_cancel_button = Button.new()
	walk_cancel_button.text = "Cancel"
	walk_cancel_button.pressed.connect(_on_walk_cancel_pressed)
	edit_row.add_child(walk_cancel_button)
	column.add_child(edit_row)

	return column


func _create_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.modulate = Color.BLACK
	return label


# The top-level layout fills whatever game area Godot exposes after stretch.
func _setup_layout_panels() -> void:
	left_panel = _create_layout_panel("LeftControlPanel", Color.WHITE, Color(0.0, 0.0, 0.0, 1.0), 4)
	tonnetz_panel = _create_layout_panel("TonnetzPanel", Color.WHITE, Color(0.0, 0.0, 0.0, 1.0), 4)
	controls_panel = _create_layout_panel("ControlsPanel", Color.WHITE, Color(0.0, 0.0, 0.0, 1.0), 4)

	add_child(left_panel)
	add_child(tonnetz_panel)
	add_child(controls_panel)
	move_child(left_panel, 0)
	move_child(tonnetz_panel, 1)
	move_child(controls_panel, 2)

	lsystem_content_container = VBoxContainer.new()
	lsystem_content_container.name = "LSystemContentContainer"
	lsystem_content_container.add_theme_constant_override("separation", 8)
	lsystem_content_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lsystem_content_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(lsystem_content_container)

	controls_container = VBoxContainer.new()
	controls_container.name = "ControlsContainer"
	controls_container.add_theme_constant_override("separation", 12)
	controls_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(controls_container)

	tonnetz_fullscreen_exit_button = Button.new()
	tonnetz_fullscreen_exit_button.name = "TonnetzFullscreenExitButton"
	tonnetz_fullscreen_exit_button.text = "Exit fullscreen"
	tonnetz_fullscreen_exit_button.tooltip_text = "Exit Tonnetz fullscreen"
	tonnetz_fullscreen_exit_button.focus_mode = Control.FOCUS_NONE
	tonnetz_fullscreen_exit_button.mouse_filter = Control.MOUSE_FILTER_STOP
	tonnetz_fullscreen_exit_button.custom_minimum_size = Vector2(132, 36)
	tonnetz_fullscreen_exit_button.visible = false
	tonnetz_fullscreen_exit_button.z_index = 200
	tonnetz_fullscreen_exit_button.pressed.connect(_on_tonnetz_fullscreen_pressed)
	add_child(tonnetz_fullscreen_exit_button)


func _create_layout_panel(panel_name: String, bg_color: Color, border_color: Color, border_width: int) -> Panel:
	var panel := Panel.new()
	panel.name = panel_name
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(0)
	style.set_content_margin(SIDE_LEFT, PANEL_PADDING)
	style.set_content_margin(SIDE_TOP, PANEL_PADDING)
	style.set_content_margin(SIDE_RIGHT, PANEL_PADDING)
	style.set_content_margin(SIDE_BOTTOM, PANEL_PADDING)
	panel.add_theme_stylebox_override("panel", style)

	return panel


func _apply_layout() -> void:
	var canvas_size := get_viewport_rect().size
	size = canvas_size
	var top_height = canvas_size.y - OUTER_MARGIN * 2.0
	var left_width: float = clampf(
		canvas_size.x * LEFT_PANEL_WIDTH_RATIO,
		LEFT_PANEL_MIN_WIDTH,
		LEFT_PANEL_MAX_WIDTH
	)

	if canvas_size.x - left_width < TONNETZ_MIN_WIDTH:
		left_width = max(LEFT_PANEL_MIN_WIDTH, canvas_size.x - TONNETZ_MIN_WIDTH)

	var tonnetz_x = OUTER_MARGIN + left_width
	var tonnetz_width = canvas_size.x - tonnetz_x - OUTER_MARGIN
	var controls_height: float = min(GENERAL_PANEL_HEIGHT, top_height * 0.34)
	var walk_height: float = min(WALK_RECORDER_PANEL_HEIGHT, top_height * 0.22)
	var lsystems_height: float = max(
		240.0,
		top_height - controls_height - walk_height - PANEL_GAP * 2.0
	)
	var controls_y: float = OUTER_MARGIN + lsystems_height + PANEL_GAP
	var walk_y: float = controls_y + controls_height + PANEL_GAP

	left_panel.visible = not tonnetz_fullscreen
	controls_panel.visible = not tonnetz_fullscreen
	controls_container.visible = not tonnetz_fullscreen
	lsystem_content_container.visible = not tonnetz_fullscreen
	tonnetz_fullscreen_button.visible = not tonnetz_fullscreen
	if walk_recorder_panel:
		walk_recorder_panel.visible = not tonnetz_fullscreen
	tab_container.visible = false

	if tonnetz_fullscreen:
		tonnetz_panel.position = Vector2.ZERO
		tonnetz_panel.size = canvas_size
	else:
		left_panel.position = Vector2(OUTER_MARGIN, OUTER_MARGIN)
		left_panel.size = Vector2(left_width, lsystems_height)

		tonnetz_panel.position = Vector2(tonnetz_x, OUTER_MARGIN)
		tonnetz_panel.size = Vector2(tonnetz_width, top_height)

		controls_panel.position = Vector2(OUTER_MARGIN, controls_y)
		controls_panel.size = Vector2(left_width, controls_height)

		controls_container.position = controls_panel.position + Vector2(PANEL_PADDING, PANEL_PADDING)
		controls_container.size = controls_panel.size - Vector2(PANEL_PADDING * 2.0, PANEL_PADDING * 2.0)
		controls_container.custom_minimum_size = controls_container.size

		walk_recorder_panel.position = Vector2(OUTER_MARGIN, walk_y)
		walk_recorder_panel.size = Vector2(left_width, walk_height)

	tonnetz_fullscreen_exit_button.visible = tonnetz_fullscreen
	tonnetz_fullscreen_exit_button.size = tonnetz_fullscreen_exit_button.get_combined_minimum_size()
	tonnetz_fullscreen_exit_button.position = Vector2(
		canvas_size.x - tonnetz_fullscreen_exit_button.size.x - PANEL_PADDING,
		PANEL_PADDING
	)

	if voice_scroll:
		voice_scroll.custom_minimum_size = Vector2.ZERO
		voice_scroll.update_minimum_size()

	if not tonnetz_fullscreen:
		lsystem_content_container.position = left_panel.position + Vector2(PANEL_PADDING, PANEL_PADDING)
		lsystem_content_container.size = left_panel.size - Vector2(PANEL_PADDING * 2.0, PANEL_PADDING * 2.0)
		lsystem_content_container.custom_minimum_size = lsystem_content_container.size

		tonnetz_fullscreen_button.size = tonnetz_fullscreen_button.get_combined_minimum_size()
		tonnetz_fullscreen_button.position = Vector2(
			tonnetz_panel.position.x + tonnetz_panel.size.x - tonnetz_fullscreen_button.size.x - PANEL_PADDING,
			tonnetz_panel.position.y + PANEL_PADDING
		)

	if voice_scroll and not tonnetz_fullscreen:
		voice_scroll.custom_minimum_size = Vector2(
			0.0,
			max(0.0, lsystem_content_container.size.y - 48.0)
		)

	tonnetz_viewport_container.position = tonnetz_panel.position
	tonnetz_viewport_container.size = tonnetz_panel.size
	tonnetz_viewport_container.custom_minimum_size = tonnetz_viewport_container.size
	if not tonnetz_viewport_container.stretch:
		tonnetz_viewport.size = Vector2i(tonnetz_viewport_container.size)

	config.start_pos = Vector2(0, 20)

	if walk_recorder_panel:
		walk_recorder_panel.custom_minimum_size = walk_recorder_panel.size

	if master_bpm_panel:
		master_bpm_panel.custom_minimum_size = Vector2(controls_container.size.x, 54.0)

	if tonnetz_fullscreen:
		_fit_tonnetz_to_fullscreen()

func _on_viewport_size_changed() -> void:
	_apply_layout()

func center_tonnetz_view(builder: TonnetzBuilder) -> void:
	if not builder or builder.nodes.is_empty() or not tonnetz_viewport:
		return

	var bounds := _get_tonnetz_bounds(builder)

	if bounds.size == Vector2.ZERO:
		return

	tonnetz_bounds = bounds
	tonnetz_bounds_available = true
	var viewport_center := tonnetz_viewport_container.size * 0.5
	var content_center := bounds.get_center()
	tonnetz_view_zoom = 1.0
	tonnetz_view_offset = viewport_center - content_center * tonnetz_view_zoom
	_apply_tonnetz_view_transform()

func _fit_tonnetz_to_fullscreen() -> void:
	if not tonnetz_bounds_available or tonnetz_bounds.size == Vector2.ZERO:
		return

	if tonnetz_viewport_container.size == Vector2.ZERO:
		return

	var scale_x: float = tonnetz_viewport_container.size.x / max(1.0, tonnetz_bounds.size.x)
	var scale_y: float = tonnetz_viewport_container.size.y / max(1.0, tonnetz_bounds.size.y)
	tonnetz_view_zoom = max(scale_x, scale_y)
	tonnetz_view_offset = (
		tonnetz_viewport_container.size * 0.5
		- tonnetz_bounds.get_center() * tonnetz_view_zoom
	)
	_apply_tonnetz_view_transform()

func _get_tonnetz_bounds(builder: TonnetzBuilder) -> Rect2:
	var bounds := Rect2()
	var first := true

	for node in builder.nodes.values():
		if not is_instance_valid(node):
			continue

		var point: Vector2 = node.get_center()

		if first:
			bounds = Rect2(point, Vector2.ZERO)
			first = false
		else:
			bounds = bounds.expand(point)

	return bounds

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
	style.bg_color = Color.WHITE
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
	var header := HBoxContainer.new()
	header.name = "LSystemHeader"
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lsystem_content_container.add_child(header)

	var title := _create_label("L-Systems")
	var fv := FontVariation.new()
	fv.base_font = load("res://fonts/Rubik-VariableFont_wght.ttf")
	fv.variation_opentype = {"weight": 700}
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_font_override("font", fv)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var add_button := Button.new()
	add_button.text = "Add random"
	add_button.tooltip_text = "Add a random L-system"
	add_button.focus_mode = Control.FOCUS_NONE
	add_button.pressed.connect(_on_add_random_lsystem_pressed)
	header.add_child(add_button)

	var margin := MarginContainer.new()
	margin.name = "LSystemContentMargin"
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lsystem_content_container.add_child(margin)

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
	style.bg_color = Color.WHITE
	style.border_color = color
	style.set_corner_radius_all(28)
	style.set_border_width_all(4)
	style.set_content_margin(SIDE_LEFT, 0)
	style.set_content_margin(SIDE_TOP, 0)
	style.set_content_margin(SIDE_RIGHT, 0)
	style.set_content_margin(SIDE_BOTTOM, 16)
	panel.add_theme_stylebox_override("panel", style)

	var card := VBoxContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_child(card)
	
########## HEADER #############
	var header_panel := PanelContainer.new()
	header_panel.name = "VoiceHeader"
	header_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	header_panel.gui_input.connect(_on_lsystem_card_gui_input.bind(index))
	card.add_child(header_panel)

	var header_color := color if is_active else _get_inactive_voice_header_color(color)
	var header_text_color := _get_voice_header_text_color(header_color)
	var header_style := StyleBoxFlat.new()
	header_style.bg_color = header_color
	header_style.set_corner_radius_all(22)
	header_style.set_content_margin(SIDE_LEFT, 12)
	header_style.set_content_margin(SIDE_TOP, 8)
	header_style.set_content_margin(SIDE_RIGHT, 12)
	header_style.set_content_margin(SIDE_BOTTOM, 8)
	header_panel.add_theme_stylebox_override("panel", header_style)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 4)
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.mouse_filter = Control.MOUSE_FILTER_PASS
	header_panel.add_child(header)
	
########## TITLE #############
	var title := Label.new()
	title.text = "Voice %d" % (index + 1)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fv := FontVariation.new()
	fv.base_font = load("res://fonts/Rubik-VariableFont_wght.ttf")
	fv.variation_opentype = {"weight": 700}
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_font_override("font", fv)
	title.modulate = header_text_color
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

########## ICONS #############

	var mute_button := Button.new()
	_setup_lsystem_icon_button(mute_button, UNMUTED_ICON_PATH)
	mute_button.toggle_mode = true
	mute_button.button_pressed = bool(info.get("muted", false))
	_update_voice_mute_button(mute_button, mute_button.button_pressed)
	mute_button.toggled.connect(_on_voice_mute_toggled.bind(index, mute_button))
	header.add_child(mute_button)

	var random_button := Button.new()
	#random_button.text = "Randomize"
	_setup_lsystem_icon_button(random_button, "res://icons/shuffle.svg")

	random_button.pressed.connect(_on_voice_randomize_pressed.bind(index))
	random_button.modulate = header_text_color
	header.add_child(random_button)

	var duplicate_button := Button.new()
	#duplicate_button.text = "Copy"
	_setup_lsystem_icon_button(duplicate_button, "res://icons/duplicate.svg")

	duplicate_button.pressed.connect(_on_voice_duplicate_pressed.bind(index))
	duplicate_button.modulate = header_text_color
	header.add_child(duplicate_button)

	var export_voice_button := Button.new()
	export_voice_button.flat = true
	export_voice_button.text = "Export"
	export_voice_button.tooltip_text = "Export this voice as MIDI"
	export_voice_button.pressed.connect(_on_voice_export_midi_pressed.bind(index))
	export_voice_button.add_theme_color_override("font_color", header_text_color)
	export_voice_button.add_theme_color_override("font_hover_color", header_text_color)
	export_voice_button.add_theme_color_override("font_pressed_color", header_text_color)
	header.add_child(export_voice_button)

	var remove_button := Button.new()
	#remove_button.text = "Remove"
	_setup_lsystem_icon_button(remove_button, "res://icons/cancel.svg")
	remove_button.pressed.connect(_on_voice_remove_pressed.bind(index))
	remove_button.modulate = header_text_color
	header.add_child(remove_button)

	var body_margin := MarginContainer.new()
	body_margin.add_theme_constant_override("margin_left", 16)
	body_margin.add_theme_constant_override("margin_top", 12)
	body_margin.add_theme_constant_override("margin_right", 16)
	body_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_child(body_margin)

	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.mouse_filter = Control.MOUSE_FILTER_PASS
	body_margin.add_child(body)

	if info.has("fitness"):
		var fitness_value := float(info.get("fitness", INF))
		var fitness_label := Label.new()
		fitness_label.text = "Fitness: %s" % _format_voice_fitness(fitness_value)
		fitness_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_child(fitness_label)

	var length_label := Label.new()
	length_label.text = "Length: %d" % lsystem.generated_string.length()
	length_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(length_label)

	body.add_child(_create_lsystem_walk_previews(index, lsystem, color, info))

########## ITERATIONS #############
	var iterations_row := HBoxContainer.new()
	body.add_child(iterations_row)

	var iterations_label := Label.new()
	iterations_label.text = "Iterations"
	#iterations_label.modulate = Color.BLACK
	iterations_row.add_child(iterations_label)

	var iterations_value := Label.new()
	iterations_value.text = str(lsystem.iterations)
	#iterations_value.modulate = Color.BLACK
	iterations_row.add_child(iterations_value)

	var iterations_down_button := Button.new()
	_setup_lsystem_icon_button(iterations_down_button, "res://icons/left.svg")
	iterations_down_button.tooltip_text = "Decrease iterations"
	iterations_row.add_child(iterations_down_button)

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

	var iterations_up_button := Button.new()
	_setup_lsystem_icon_button(iterations_up_button, "res://icons/right.svg")
	iterations_up_button.tooltip_text = "Increase iterations"
	iterations_row.add_child(iterations_up_button)
	iterations_down_button.pressed.connect(
		_on_voice_iterations_step_pressed.bind(index, iterations_slider, iterations_value, -1)
	)
	iterations_up_button.pressed.connect(
		_on_voice_iterations_step_pressed.bind(index, iterations_slider, iterations_value, 1)
	)

	_add_voice_volume_controls(body, index, volume)

	########## GENERATED STRING #############
	var generated_edit := Label.new()
	generated_edit.text = "Generated String: " + lsystem.generated_string
	generated_edit.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	generated_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(generated_edit)
	
########## AXIOM #############
	var axiom_row := HBoxContainer.new()
	body.add_child(axiom_row)

	var axiom_label := Label.new()
	axiom_label.text = "Axiom"
	#axiom_label.modulate = Color.BLACK
	axiom_row.add_child(axiom_label)

	var axiom_edit := LineEdit.new()
	axiom_edit.text = lsystem.axiom
	axiom_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_lsystem_line_edit_style(axiom_edit)
	axiom_edit.text_submitted.connect(_on_voice_axiom_submitted.bind(index))
	axiom_row.add_child(axiom_edit)
	
########## PROD RULES #############
	for key in lsystem.rules:
		body.add_child(_create_rule_row(index, key, lsystem.rules[key]))

	return panel

##################################################
########## FUNCTIONS #############
##################################################
func _create_lsystem_walk_previews(
	index: int,
	lsystem,
	color: Color,
	info: Dictionary
) -> Control:
	var previews := VBoxContainer.new()
	previews.name = "WalkPreviews"
	previews.add_theme_constant_override("separation", 6)
	previews.mouse_filter = Control.MOUSE_FILTER_PASS

	previews.add_child(
		_create_lsystem_walk_preview_row(
			index,
			"nodes",
			"Nodes",
			lsystem.generated_string,
			color,
			int(info.get("node_direction_index", 5))
		)
	)
	previews.add_child(
		_create_lsystem_walk_preview_row(
			index,
			"triangles",
			"Triangles",
			lsystem.generated_string,
			color,
			int(info.get("triangle_edge", 0))
		)
	)

	return previews

func _create_lsystem_walk_preview_row(
	index: int,
	anchor_mode: String,
	label_text: String,
	instructions: String,
	color: Color,
	direction_index: int
) -> Control:
	var row := HBoxContainer.new()
	row.name = "%sPreviewRow" % label_text
	row.add_theme_constant_override("separation", 4)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_PASS

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(58, 0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)

	var left_button := Button.new()
	_setup_lsystem_icon_button(left_button, "res://icons/left.svg")
	left_button.tooltip_text = "Rotate preview left"
	left_button.pressed.connect(_on_lsystem_preview_direction_pressed.bind(index, anchor_mode, -1))
	row.add_child(left_button)

	var preview := Control.new()
	preview.name = "%sPreview" % label_text
	preview.custom_minimum_size = WALK_PREVIEW_SIZE
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.draw.connect(
		_draw_lsystem_walk_preview.bind(
			preview,
			anchor_mode,
			instructions,
			color,
			direction_index
		)
	)
	row.add_child(preview)

	var right_button := Button.new()
	_setup_lsystem_icon_button(right_button, "res://icons/right.svg")
	right_button.tooltip_text = "Rotate preview right"
	right_button.pressed.connect(_on_lsystem_preview_direction_pressed.bind(index, anchor_mode, 1))
	row.add_child(right_button)

	return row

func _draw_lsystem_walk_preview(
	preview: Control,
	anchor_mode: String,
	instructions: String,
	color: Color,
	direction_index: int
) -> void:
	var points := _build_lsystem_walk_preview_points(
		anchor_mode,
		instructions,
		direction_index
	)
	var rect := Rect2(Vector2.ZERO, preview.size)
	preview.draw_rect(rect, Color.WHITE, true)
	preview.draw_rect(rect, Color(0.0, 0.0, 0.0, 0.18), false, 1.0)

	if points.size() < 2:
		preview.draw_circle(rect.get_center(), 4.0, color)
		return

	var scaled_points := _fit_walk_preview_points(points, rect.grow(-8.0))
	var line_color := color
	line_color.a = 0.85
	preview.draw_polyline(PackedVector2Array(scaled_points), line_color, 3.0, true)
	preview.draw_circle(scaled_points[0], 4.0, Color(0.08, 0.08, 0.08, 1.0))
	preview.draw_circle(scaled_points[-1], 4.0, color)

func _build_lsystem_walk_preview_points(
	anchor_mode: String,
	instructions: String,
	direction_index: int
) -> Array[Vector2]:
	if anchor_mode == "triangles":
		return _build_triangle_walk_preview_points(instructions, direction_index)

	return _build_node_walk_preview_points(instructions, direction_index)

func _build_node_walk_preview_points(instructions: String, direction_index: int) -> Array[Vector2]:
	var direction: Vector2i = WALK_PREVIEW_NODE_DIRECTIONS[posmod(direction_index, WALK_PREVIEW_NODE_DIRECTIONS.size())]
	var position: Vector2 = Vector2.ZERO
	var points: Array[Vector2] = [position]
	var symbol_count: int = min(instructions.length(), WALK_PREVIEW_MAX_SYMBOLS)

	for i in range(symbol_count):
		match instructions[i]:
			"l":
				direction = _turn_preview_node_direction_left(direction)
			"r":
				direction = _turn_preview_node_direction_right(direction)
			"s":
				position += _axial_to_preview_position(direction) * WALK_PREVIEW_NODE_STEP
				points.append(position)

	return points

func _build_triangle_walk_preview_points(instructions: String, edge: int) -> Array[Vector2]:
	var current_edge := posmod(edge, 3)
	var orientation := 0
	var position: Vector2 = Vector2.ZERO
	var points: Array[Vector2] = [position]
	var symbol_count: int = min(instructions.length(), WALK_PREVIEW_MAX_SYMBOLS)

	for i in range(symbol_count):
		match instructions[i]:
			"l":
				current_edge = (current_edge + 1) % 3
			"r":
				current_edge = (current_edge + 2) % 3
			"s":
				position += _get_triangle_preview_step(orientation, current_edge)
				orientation = 1 - orientation
				points.append(position)

	return points

func _fit_walk_preview_points(points: Array[Vector2], rect: Rect2) -> Array[Vector2]:
	var min_point := points[0]
	var max_point := points[0]

	for point in points:
		min_point.x = min(min_point.x, point.x)
		min_point.y = min(min_point.y, point.y)
		max_point.x = max(max_point.x, point.x)
		max_point.y = max(max_point.y, point.y)

	var bounds_size := max_point - min_point
	var scale := 1.0

	if bounds_size.x > 0.0 or bounds_size.y > 0.0:
		scale = min(
			rect.size.x / max(1.0, bounds_size.x),
			rect.size.y / max(1.0, bounds_size.y)
		)

	var offset := rect.position + (rect.size - bounds_size * scale) * 0.5
	var result: Array[Vector2] = []

	for point in points:
		result.append(offset + (point - min_point) * scale)

	return result

func _turn_preview_node_direction_left(direction: Vector2i) -> Vector2i:
	var q := direction.x
	var r := direction.y
	var s := -q - r
	return Vector2i(-s, -q)

func _turn_preview_node_direction_right(direction: Vector2i) -> Vector2i:
	var q := direction.x
	var r := direction.y
	var s := -q - r
	return Vector2i(-r, -s)

func _axial_to_preview_position(direction: Vector2i) -> Vector2:
	return Vector2(
		0.5 * float(direction.x - direction.y),
		0.866 * float(direction.x + direction.y)
	)

func _get_triangle_preview_step(orientation: int, edge: int) -> Vector2:
	var angle_offset := -PI / 2.0 if orientation == 0 else PI / 2.0
	var angle := angle_offset + float(edge) * TAU / 3.0
	return Vector2(cos(angle), sin(angle)) * WALK_PREVIEW_TRIANGLE_STEP


func _setup_lsystem_icon_button(button: Button, icon_path: String) -> void:
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.icon = _get_icon(icon_path)

func _apply_lsystem_line_edit_style(line_edit: LineEdit) -> void:
	var normal_style := _create_lsystem_line_edit_style(
		Color(1.0, 0.985, 0.94, 1.0),
		Color(0.0, 0.0, 0.0, 0.22),
		1
	)
	var focus_style := _create_lsystem_line_edit_style(
		Color(1.0, 0.995, 0.965, 1.0),
		Color(0.0, 0.0, 0.0, 0.45),
		2
	)

	line_edit.add_theme_stylebox_override("normal", normal_style)
	line_edit.add_theme_stylebox_override("focus", focus_style)
	line_edit.add_theme_color_override("font_color", Color.BLACK)
	line_edit.add_theme_color_override("caret_color", Color.BLACK)
	line_edit.add_theme_color_override("selection_color", Color(0.95, 0.82, 0.46, 0.45))

func _create_lsystem_line_edit_style(bg_color: Color, border_color: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(6)
	style.set_content_margin(SIDE_LEFT, 8)
	style.set_content_margin(SIDE_TOP, 4)
	style.set_content_margin(SIDE_RIGHT, 8)
	style.set_content_margin(SIDE_BOTTOM, 4)
	return style

func _get_inactive_voice_header_color(color: Color) -> Color:
	return color.lerp(Color(0.55, 0.55, 0.55, 1.0), 0.62)

func _get_voice_header_text_color(color: Color) -> Color:
	var luminance := color.r * 0.299 + color.g * 0.587 + color.b * 0.114
	return Color.BLACK if luminance > 0.62 else Color.WHITE


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

	var volume_down_button := Button.new()
	_setup_lsystem_icon_button(volume_down_button, "res://icons/left.svg")
	volume_down_button.tooltip_text = "Decrease volume"
	volume_row.add_child(volume_down_button)

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

	var volume_up_button := Button.new()
	_setup_lsystem_icon_button(volume_up_button, "res://icons/right.svg")
	volume_up_button.tooltip_text = "Increase volume"
	volume_row.add_child(volume_up_button)
	volume_down_button.pressed.connect(
		_on_voice_volume_step_pressed.bind(index, volume_slider, volume_value, -0.01)
	)
	volume_up_button.pressed.connect(
		_on_voice_volume_step_pressed.bind(index, volume_slider, volume_value, 0.01)
	)

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
	_apply_lsystem_line_edit_style(production_edit)
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

func _on_voice_export_midi_pressed(index: int) -> void:
	if not export_midi_dialog:
		return

	export_midi_voice_index = index
	export_midi_dialog.current_file = _build_default_voice_midi_filename(index)
	export_midi_dialog.popup_centered(Vector2i(760, 520))

func _on_voice_remove_pressed(index: int) -> void:
	lsystem_remove_requested.emit(index)

func _on_lsystem_preview_direction_pressed(index: int, anchor_mode: String, delta: int) -> void:
	lsystem_preview_direction_changed.emit(index, anchor_mode, delta)

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

func _on_voice_iterations_step_pressed(
	index: int,
	iterations_slider: HSlider,
	iterations_value: Label,
	delta: int
) -> void:
	var iterations := int(clamp(
		iterations_slider.value + delta,
		iterations_slider.min_value,
		iterations_slider.max_value
	))
	iterations_slider.value = iterations
	iterations_value.text = str(iterations)
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

func _on_voice_volume_step_pressed(
	index: int,
	volume_slider: HSlider,
	volume_value: Label,
	delta: float
) -> void:
	var volume: float = clamp(
		volume_slider.value + delta,
		volume_slider.min_value,
		volume_slider.max_value
	)
	volume_slider.value = volume
	volume_value.text = "%d%%" % int(round(volume * 100.0))
	lsystem_volume_changed.emit(index, volume)

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
	var title := _create_label("General")
	var fv := FontVariation.new()
	fv.base_font = load("res://fonts/Rubik-VariableFont_wght.ttf")
	fv.variation_opentype = {"weight": 700}
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_font_override("font", fv)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls_container.add_child(title)

	tonnetz_fullscreen_button = Button.new()
	tonnetz_fullscreen_button.name = "TonnetzFullscreenButton"
	tonnetz_fullscreen_button.text = "Tonnetz fullscreen"
	tonnetz_fullscreen_button.tooltip_text = "Make the Tonnetz area fullscreen"
	tonnetz_fullscreen_button.focus_mode = Control.FOCUS_NONE
	tonnetz_fullscreen_button.custom_minimum_size = Vector2(132, 36)
	tonnetz_fullscreen_button.mouse_filter = Control.MOUSE_FILTER_STOP
	tonnetz_fullscreen_button.z_index = 200
	tonnetz_fullscreen_button.pressed.connect(_on_tonnetz_fullscreen_pressed)
	add_child(tonnetz_fullscreen_button)

	stop_all_button = Button.new()
	stop_all_button.name = "StopAllButton"
	stop_all_button.text = "Stop all"
	stop_all_button.tooltip_text = "Stop all voices"
	stop_all_button.focus_mode = Control.FOCUS_NONE
	stop_all_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stop_all_button.pressed.connect(_on_stop_all_pressed)
	controls_container.add_child(stop_all_button)

	export_midi_button = Button.new()
	export_midi_button.name = "ExportMidiButton"
	export_midi_button.text = "Export all"
	export_midi_button.tooltip_text = "Export all voices as MIDI"
	export_midi_button.focus_mode = Control.FOCUS_NONE
	export_midi_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	export_midi_button.mouse_filter = Control.MOUSE_FILTER_STOP
	export_midi_button.pressed.connect(_on_export_midi_pressed)
	controls_container.add_child(export_midi_button)


func _setup_walk_recorder_controls() -> void:
	walk_recorder_panel = PanelContainer.new()
	walk_recorder_panel.name = "WalkRecorderPanel"
	walk_recorder_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	walk_recorder_panel.z_index = 100
	walk_recorder_panel.custom_minimum_size = Vector2(LEFT_PANEL_MIN_WIDTH, WALK_RECORDER_PANEL_HEIGHT)

	var style := StyleBoxFlat.new()
	style.bg_color = Color.WHITE
	style.border_color = Color.BLACK
	style.set_border_width_all(4)
	style.set_corner_radius_all(0)
	style.set_content_margin(SIDE_LEFT, PANEL_PADDING)
	style.set_content_margin(SIDE_TOP, PANEL_PADDING)
	style.set_content_margin(SIDE_RIGHT, PANEL_PADDING)
	style.set_content_margin(SIDE_BOTTOM, PANEL_PADDING)
	walk_recorder_panel.add_theme_stylebox_override("panel", style)
	add_child(walk_recorder_panel)

	walk_recorder_panel.add_child(_create_walk_recorder_controls())


func _setup_master_bpm_control() -> void:
	master_bpm_panel = PanelContainer.new()
	master_bpm_panel.name = "MasterBPMPanel"
	master_bpm_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	master_bpm_panel.z_index = 100

	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.0)
	style.border_color = Color(1, 1, 1, 0.0)
	style.set_border_width_all(0)
	style.set_corner_radius_all(0)
	style.set_content_margin(SIDE_LEFT, 8)
	style.set_content_margin(SIDE_TOP, 10)
	style.set_content_margin(SIDE_RIGHT, 8)
	style.set_content_margin(SIDE_BOTTOM, 10)
	master_bpm_panel.add_theme_stylebox_override("panel", style)
	controls_container.add_child(master_bpm_panel)

	var bpm_row := HBoxContainer.new()
	bpm_row.name = "BPMRow"
	bpm_row.add_theme_constant_override("separation", 4)
	bpm_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	master_bpm_panel.add_child(bpm_row)

	var title := _create_label("BPM")
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bpm_row.add_child(title)

	bpm_value_label = _create_label("120")
	bpm_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bpm_value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bpm_value_label.custom_minimum_size = Vector2(42, 0)
	bpm_row.add_child(bpm_value_label)

	var bpm_down_button := Button.new()
	_setup_lsystem_icon_button(bpm_down_button, "res://icons/left.svg")
	bpm_down_button.tooltip_text = "Decrease BPM"
	bpm_row.add_child(bpm_down_button)

	bpm_slider = HSlider.new()
	bpm_slider.name = "BPMSlider"
	bpm_slider.min_value = 20.0
	bpm_slider.max_value = 200.0
	bpm_slider.step = 10.0
	bpm_slider.value = 120.0
	bpm_slider.exp_edit = true
	bpm_slider.custom_minimum_size = Vector2(120, 0)
	bpm_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bpm_slider.tooltip_text = "BPM"
	bpm_slider.value_changed.connect(_on_bpm_value_changed)
	bpm_slider.drag_ended.connect(on_bpm_changed)
	bpm_row.add_child(bpm_slider)

	var bpm_up_button := Button.new()
	_setup_lsystem_icon_button(bpm_up_button, "res://icons/right.svg")
	bpm_up_button.tooltip_text = "Increase BPM"
	bpm_row.add_child(bpm_up_button)
	bpm_down_button.pressed.connect(_on_bpm_step_pressed.bind(-10))
	bpm_up_button.pressed.connect(_on_bpm_step_pressed.bind(10))


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

func _on_tonnetz_fullscreen_pressed() -> void:
	if tonnetz_fullscreen:
		tonnetz_fullscreen = false
		_update_tonnetz_fullscreen_button()
		tonnetz_visibility_toggled.emit(true)
		_apply_layout()
		tonnetz_view_zoom = tonnetz_normal_view_zoom
		tonnetz_view_offset = tonnetz_normal_view_offset
		_apply_tonnetz_view_transform()
		return

	tonnetz_normal_view_zoom = tonnetz_view_zoom
	tonnetz_normal_view_offset = tonnetz_view_offset
	tonnetz_fullscreen = true
	_update_tonnetz_fullscreen_button()
	tonnetz_visibility_toggled.emit(false)
	_apply_layout()
	_fit_tonnetz_to_fullscreen()

func _on_stop_all_pressed() -> void:
	stop_all_lsystems_requested.emit()

func _on_export_midi_pressed() -> void:
	if not export_midi_dialog:
		return

	export_midi_voice_index = -1
	export_midi_dialog.current_file = _build_default_midi_filename()
	export_midi_dialog.popup_centered(Vector2i(760, 520))


func _on_export_midi_file_selected(path: String) -> void:
	if path.get_extension().to_lower() != "mid":
		path += ".mid"

	if export_midi_voice_index >= 0:
		export_midi_voice_requested.emit(export_midi_voice_index, path)
	else:
		export_midi_requested.emit(path)

	export_midi_voice_index = -1


func _build_default_midi_filename() -> String:
	var date := Time.get_datetime_dict_from_system()
	return "tonnetz_%04d%02d%02d_%02d%02d.mid" % [
		int(date["year"]),
		int(date["month"]),
		int(date["day"]),
		int(date["hour"]),
		int(date["minute"])
	]

func _build_default_voice_midi_filename(index: int) -> String:
	var date := Time.get_datetime_dict_from_system()
	return "tonnetz_voice_%d_%04d%02d%02d_%02d%02d.mid" % [
		index + 1,
		int(date["year"]),
		int(date["month"]),
		int(date["day"]),
		int(date["hour"]),
		int(date["minute"])
	]


func set_global_paused_visual(paused: bool) -> void:
	global_paused = paused
	if not global_play_pause_button:
		return

	global_play_pause_button.icon = _get_icon("res://icons/play.svg" if global_paused else "res://icons/pause.svg")
	global_play_pause_button.tooltip_text = "Play" if global_paused else "Pause"

func _update_tonnetz_fullscreen_button() -> void:
	if not tonnetz_fullscreen_button:
		return

	tonnetz_fullscreen_button.text = "Exit fullscreen" if tonnetz_fullscreen else "Tonnetz fullscreen"
	tonnetz_fullscreen_button.tooltip_text = "Exit Tonnetz fullscreen" if tonnetz_fullscreen else "Make the Tonnetz area fullscreen"


func _on_bpm_value_changed(new_value: float) -> void:
	bpm_value_label.text = str(int(new_value))

func _on_bpm_step_pressed(delta: int) -> void:
	var new_value := int(clamp(
		bpm_slider.value + delta,
		bpm_slider.min_value,
		bpm_slider.max_value
	))
	bpm_slider.value = new_value
	config.bpm = new_value
	bpm_value_label.text = str(new_value)

func on_bpm_changed(ended: bool) -> void:
	if not ended:
		return
	var new_value := int(bpm_slider.value)
	config.bpm = new_value
	bpm_value_label.text = str(new_value)
