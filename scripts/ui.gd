extends Control

# builds the full user interface 
# handles input

##################################################
########## SIGNALS #############
##################################################
signal add_random_lsystem_requested
signal lsystem_selected(index: int)
signal lsystem_randomize_requested(index: int)
signal lsystem_duplicate_requested(index: int)
signal lsystem_remove_requested(index: int)
signal lsystem_solo_toggled(index: int, solo: bool)
signal lsystem_axiom_changed(index: int, new_axiom: String)
signal lsystem_iterations_changed(index: int, iterations: int)
signal lsystem_rule_changed(index: int, symbol: String, production: String)
signal lsystem_volume_changed(index: int, volume: float)
signal trail_length_changed(length_steps: int)
signal lsystem_mute_toggled(index: int, muted: bool)
signal lsystem_preview_direction_changed(index: int, delta: int)
signal walk_recording_started
signal walk_recording_cancelled
signal walk_recording_undo_requested
signal walk_recording_duration_changed(duration_beats: float)
signal walk_lsystem_generate_requested
signal tonnetz_clicked(world_position: Vector2)
signal export_midi_requested(path: String)
signal export_midi_voice_requested(index: int, path: String)
signal export_lsystems_requested(path: String)
signal export_lsystem_requested(index: int, path: String)
signal import_lsystems_requested(path: String)
signal all_lsystems_mute_toggled(muted: bool)
signal master_volume_changed(volume: float)

##################################################
########## ONREADY VARS #############
##################################################
@onready var config = Config.config

@onready var tonnetz_viewport_container: SubViewportContainer = $TonnetzViewportContainer
@onready var tonnetz_viewport: SubViewport = $TonnetzViewportContainer/TonnetzViewport

##################################################
########## CONST #############
##################################################
const WALK_PREVIEW_NODE_DIRECTIONS := [
	Vector2i(1, -1), Vector2i(0, -1), Vector2i(-1, 0),
	Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 0)
]
const TutorialOverlayScript := preload("res://scripts/tutorial_overlay.gd")


##################################################
########## VAR DECLARATIO S #############
##################################################
var left_panel: Panel
var tonnetz_panel: Panel
var tonnetz_title_label: Label
var tonnetz_hint_label: Label
var controls_panel: Panel
var controls_container: HBoxContainer
var lsystem_content_container: VBoxContainer
var lsystem_box_panel: PanelContainer
var lsystem_box_container: VBoxContainer
var voice_scroll: ScrollContainer
var voice_list: VBoxContainer
var bpm_value_label: Label
var bpm_slider: Slider
var master_volume_value_label: Label
var walk_record_button: Button
var walk_duration_buttons: Array[Button] = []
var all_mute_button: Button
var export_midi_dialog: FileDialog
var playback_panel: PanelContainer
var master_bpm_panel: PanelContainer
var export_panel: PanelContainer
var start_screen: Control
var start_pattern: Control
var tutorial_overlay: Control
var tutorial_voice_card: Control
var export_midi_voice_index := -1
var export_dialog_mode := ""
var all_muted := false
var start_screen_visible := true
var tonnetz_view_offset := Vector2.ZERO
var tonnetz_view_zoom := 1.0
var walk_card_visible := false

##################################################
########## SETUP UI #############
##################################################
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_viewport().size_changed.connect(_on_viewport_size_changed)

	_setup_layout_panels()
	_setup_right_control_boxes()
	_setup_export_midi_dialog()
	_setup_start_screen()
	_setup_tutorial_screen()
	_apply_layout()
	tonnetz_viewport_container.mouse_filter = Control.MOUSE_FILTER_PASS
	tonnetz_viewport_container.gui_input.connect(_on_tonnetz_viewport_gui_input)
	_setup_lsystem_voice_list()
	move_child(tutorial_overlay, get_child_count() - 1)
	_apply_layout()
	
	bpm_value_label.text = "%d" % int(CL.bpm)
	bpm_slider.value = CL.bpm
	set_all_muted_visual(false)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color.WHITE, true)

##################################################
########## TONNETZ #############
##################################################
func is_position_in_tonnetz_area(screen_position: Vector2) -> bool:
	if not tonnetz_viewport_container:
		return false

	return Rect2(tonnetz_viewport_container.global_position, tonnetz_viewport_container.size).has_point(screen_position)


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
	if (
		event is InputEventMouseButton
		and event.pressed
		and event.button_index == MOUSE_BUTTON_LEFT
	):
		tonnetz_clicked.emit(_get_tonnetz_world_position_from_viewport(event.position))
		accept_event()
		return

	if event is InputEventScreenTouch:
		if event.pressed:
			tonnetz_clicked.emit(_get_tonnetz_world_position_from_viewport(event.position))
		accept_event()
		return

func _apply_tonnetz_view_transform() -> void:
	if not tonnetz_viewport:
		return

	var transform := Transform2D.IDENTITY
	transform = transform.scaled(Vector2(tonnetz_view_zoom, tonnetz_view_zoom))
	transform.origin = tonnetz_view_offset
	tonnetz_viewport.canvas_transform = transform
	tonnetz_viewport_container.queue_redraw()

func _create_walk_recorder_controls(show_record_button: bool = true) -> Control:
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

	walk_duration_buttons.clear()
	_add_walk_duration_button(duration_row, "1", 4.0, false)
	_add_walk_duration_button(duration_row, "1/2", 2.0, false)
	_add_walk_duration_button(duration_row, "1/4", 1.0, true)
	_add_walk_duration_button(duration_row, "1/8", 0.5, false)
	column.add_child(duration_row)

	var record_row := HBoxContainer.new()
	record_row.add_theme_constant_override("separation", 6)
	record_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	if show_record_button:
		walk_record_button = Button.new()
		walk_record_button.text = "Start Recording"
		_apply_button_style(walk_record_button)
		walk_record_button.toggle_mode = true
		_apply_toggle_button_state(walk_record_button, false)
		walk_record_button.pressed.connect(_on_walk_record_pressed)
		record_row.add_child(walk_record_button)

	var walk_generate_button := Button.new()
	walk_generate_button.text = "Generate"
	_apply_button_style(walk_generate_button)
	walk_generate_button.tooltip_text = "Generate an L-system from the last recorded walk"
	walk_generate_button.pressed.connect(_on_walk_generate_pressed)
	record_row.add_child(walk_generate_button)

	var walk_undo_button := Button.new()
	walk_undo_button.text = "Undo"
	_apply_button_style(walk_undo_button)
	walk_undo_button.pressed.connect(_on_walk_undo_pressed)
	record_row.add_child(walk_undo_button)

	column.add_child(record_row)

	return column


func _create_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	_apply_label_style(label)
	return label

func _apply_label_style(label: Label) -> void:
	label.modulate = config.ui_text_color
	label.add_theme_font_override("font", config.font)

func _apply_button_style(button: Control) -> void:
	button.add_theme_font_override("font", config.font)
	button.add_theme_stylebox_override("normal", _create_control_style(
		config.ui_panel_color,
		config.ui_panel_border_color,
		1,
		10,
		5
	))
	button.add_theme_stylebox_override("hover", _create_control_style(
		Color(0.94, 0.94, 0.94, 1.0),
		config.ui_panel_border_color,
		1,
		10,
		5
	))
	button.add_theme_stylebox_override("pressed", _create_control_style(
		Color(0.88, 0.88, 0.88, 1.0),
		config.ui_panel_border_color,
		1,
		10,
		5
	))
	button.add_theme_stylebox_override("disabled", _create_control_style(
		Color(0.88, 0.88, 0.88, 1.0),
		config.ui_muted_color,
		1,
		10,
		5
	))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", config.ui_text_color)
	button.add_theme_color_override("font_hover_color", config.ui_text_color)
	button.add_theme_color_override("font_pressed_color", config.ui_text_color)
	button.add_theme_color_override("font_disabled_color", config.ui_muted_color)
	button.add_theme_color_override("icon_normal_color", config.ui_text_color)
	button.add_theme_color_override("icon_hover_color", config.ui_text_color)
	button.add_theme_color_override("icon_pressed_color", config.ui_text_color)
	button.add_theme_color_override("icon_disabled_color", config.ui_muted_color)

func _apply_panel_button_style(button: Control) -> void:
	button.add_theme_font_override("font", config.font)
	button.add_theme_stylebox_override("normal", _create_control_style(
		config.ui_panel_color,
		config.ui_panel_border_color,
		2,
		10,
		5
	))
	button.add_theme_stylebox_override("hover", _create_control_style(
		Color(0.94, 0.94, 0.94, 1.0),
		config.ui_panel_border_color,
		2,
		10,
		5
	))
	button.add_theme_stylebox_override("pressed", _create_control_style(
		Color(0.88, 0.88, 0.88, 1.0),
		config.ui_panel_border_color,
		2,
		10,
		5
	))
	button.add_theme_stylebox_override("disabled", _create_control_style(
		Color(0.88, 0.88, 0.88, 1.0),
		config.ui_muted_color,
		2,
		10,
		5
	))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", config.ui_text_color)
	button.add_theme_color_override("font_hover_color", config.ui_text_color)
	button.add_theme_color_override("font_pressed_color", config.ui_text_color)
	button.add_theme_color_override("font_disabled_color", config.ui_muted_color)

func _apply_toggle_button_state(button: Button, active: bool) -> void:
	var bg_color: Color = config.ui_text_color if active else config.ui_panel_color
	var text_color: Color = config.ui_panel_color if active else config.ui_text_color
	button.add_theme_stylebox_override("normal", _create_control_style(
		bg_color,
		config.ui_panel_border_color,
		1,
		10,
		5
	))
	button.add_theme_stylebox_override("hover", _create_control_style(
		bg_color,
		config.ui_panel_border_color,
		1,
		10,
		5
	))
	button.add_theme_stylebox_override("pressed", _create_control_style(
		bg_color,
		config.ui_panel_border_color,
		1,
		10,
		5
	))
	button.add_theme_color_override("font_color", text_color)
	button.add_theme_color_override("font_hover_color", text_color)
	button.add_theme_color_override("font_pressed_color", text_color)

func _apply_slider_style(slider: Slider) -> void:
	slider.custom_minimum_size.y = 28
	var track := _create_control_style(
		config.ui_panel_color,
		config.ui_panel_border_color,
		1,
		0,
		0
	)
	track.set_content_margin(SIDE_TOP, 10)
	track.set_content_margin(SIDE_BOTTOM, 10)
	slider.add_theme_stylebox_override("slider", track)
	slider.add_theme_stylebox_override("grabber_area", _create_control_style(
		config.ui_text_color,
		config.ui_text_color,
		0,
		0,
		0
	))
	slider.add_theme_stylebox_override("grabber_area_highlight", _create_control_style(
		config.ui_text_color,
		config.ui_text_color,
		0,
		0,
		0
	))

	var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var grabber := ImageTexture.create_from_image(image)
	slider.add_theme_icon_override("grabber", grabber)
	slider.add_theme_icon_override("grabber_highlight", grabber)
	slider.add_theme_icon_override("grabber_disabled", grabber)

func _apply_scrollbar_style(scroll_container: ScrollContainer) -> void:
	var vertical_bar := scroll_container.get_v_scroll_bar()
	vertical_bar.custom_minimum_size = Vector2(18, 0)
	vertical_bar.add_theme_stylebox_override("scroll", _create_control_style(
		config.ui_panel_color,
		config.ui_panel_border_color,
		1,
		0,
		0
	))
	vertical_bar.add_theme_stylebox_override("grabber", _create_control_style(
		config.ui_text_color,
		config.ui_text_color,
		1,
		0,
		0
	))
	vertical_bar.add_theme_stylebox_override("grabber_highlight", _create_control_style(
		config.ui_text_color,
		config.ui_text_color,
		1,
		0,
		0
	))
	vertical_bar.add_theme_stylebox_override("grabber_pressed", _create_control_style(
		config.ui_text_color,
		config.ui_text_color,
		1,
		0,
		0
	))

func _create_control_style(
	bg_color: Color,
	border_color: Color,
	border_width: int,
	x_margin: int,
	y_margin: int
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(0)
	style.set_content_margin(SIDE_LEFT, x_margin)
	style.set_content_margin(SIDE_TOP, y_margin)
	style.set_content_margin(SIDE_RIGHT, x_margin)
	style.set_content_margin(SIDE_BOTTOM, y_margin)
	return style

func _add_walk_duration_button(row: HBoxContainer, text: String, duration_beats: float, active: bool) -> void:
	var button := Button.new()
	button.text = text
	button.toggle_mode = true
	button.button_pressed = active
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(46, 30)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.set_meta("duration_beats", duration_beats)
	_apply_button_style(button)
	_apply_toggle_button_state(button, active)
	button.pressed.connect(_on_walk_duration_pressed.bind(button))
	walk_duration_buttons.append(button)
	row.add_child(button)


# The top-level layout fills whatever game area Godot exposes after stretch.
func _setup_layout_panels() -> void:
	left_panel = _create_layout_panel("LeftControlPanel", config.ui_panel_color, config.ui_panel_border_color, 0)
	tonnetz_panel = _create_layout_panel(
		"TonnetzPanel",
		config.tonnetz_background_color,
		config.tonnetz_border_color,
		config.ui_panel_border_width
	)
	controls_panel = _create_layout_panel("ControlsPanel", Color.TRANSPARENT, Color.TRANSPARENT, 0)
	tonnetz_title_label = _create_label("TONNETZ (3 OCTAVES)")
	tonnetz_title_label.add_theme_font_size_override("font_size", 18)
	tonnetz_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tonnetz_hint_label = _create_label("Dur ▲   Moll ▼")
	tonnetz_hint_label.add_theme_font_size_override("font_size", 14)
	tonnetz_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tonnetz_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tonnetz_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	add_child(left_panel)
	add_child(tonnetz_panel)
	add_child(tonnetz_title_label)
	add_child(tonnetz_hint_label)
	add_child(controls_panel)
	move_child(left_panel, 0)
	move_child(tonnetz_panel, 1)
	move_child(tonnetz_title_label, 2)
	move_child(tonnetz_hint_label, 3)
	move_child(tonnetz_viewport_container, 4)
	move_child(controls_panel, 5)

	lsystem_content_container = VBoxContainer.new()
	lsystem_content_container.name = "LSystemContentContainer"
	lsystem_content_container.add_theme_constant_override("separation", 14)
	lsystem_content_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lsystem_content_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(lsystem_content_container)

	controls_container = HBoxContainer.new()
	controls_container.name = "ControlsContainer"
	controls_container.add_theme_constant_override("separation", 12)
	controls_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(controls_container)


func _create_layout_panel(panel_name: String, bg_color: Color, border_color: Color, border_width: int) -> Panel:
	var panel := Panel.new()
	panel.name = panel_name
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(0)
	style.set_content_margin(SIDE_LEFT, config.panel_padding)
	style.set_content_margin(SIDE_TOP, config.panel_padding)
	style.set_content_margin(SIDE_RIGHT, config.panel_padding)
	style.set_content_margin(SIDE_BOTTOM, config.panel_padding)
	panel.add_theme_stylebox_override("panel", style)

	return panel

func _create_box_panel(panel_name: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = panel_name
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	var style := StyleBoxFlat.new()
	style.bg_color = config.ui_panel_color
	style.border_color = config.ui_panel_border_color
	style.set_border_width_all(config.ui_panel_border_width)
	style.set_corner_radius_all(0)
	style.set_content_margin(SIDE_LEFT, 12)
	style.set_content_margin(SIDE_TOP, 10)
	style.set_content_margin(SIDE_RIGHT, 12)
	style.set_content_margin(SIDE_BOTTOM, 12)
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _apply_layout() -> void:
	var canvas_size := get_viewport_rect().size
	size = canvas_size
	var top_height = canvas_size.y - config.outer_margin * 2.0
	var left_width: float = config.left_panel_width
	var bottom_height: float = config.right_controls_height

	var tonnetz_x = config.outer_margin + left_width + config.panel_gap
	var tonnetz_width = canvas_size.x - tonnetz_x - config.outer_margin
	var tonnetz_height = top_height - bottom_height - config.panel_gap
	var lsystems_height: float = top_height

	left_panel.visible = true
	controls_panel.visible = true
	controls_container.visible = true
	lsystem_content_container.visible = true

	left_panel.position = Vector2(config.outer_margin, config.outer_margin)
	left_panel.size = Vector2(left_width, lsystems_height)

	tonnetz_panel.position = Vector2(tonnetz_x, config.outer_margin)
	tonnetz_panel.size = Vector2(tonnetz_width, tonnetz_height)

	controls_panel.position = Vector2(
		tonnetz_x,
		config.outer_margin + tonnetz_height + config.panel_gap
	)
	controls_panel.size = Vector2(tonnetz_width, bottom_height)

	controls_container.position = controls_panel.position
	controls_container.size = controls_panel.size
	controls_container.custom_minimum_size = controls_panel.size

	lsystem_content_container.position = left_panel.position
	lsystem_content_container.size = left_panel.size
	lsystem_content_container.custom_minimum_size = lsystem_content_container.size

	tonnetz_title_label.position = tonnetz_panel.position + Vector2(config.panel_padding, 8.0)
	tonnetz_title_label.size = Vector2(
		tonnetz_panel.size.x - config.panel_padding * 2.0,
		config.tonnetz_title_height - 8.0
	)
	tonnetz_hint_label.position = tonnetz_panel.position + Vector2(
		tonnetz_panel.size.x - config.panel_padding - 220.0,
		8.0
	)
	tonnetz_hint_label.size = Vector2(220.0, config.tonnetz_title_height - 8.0)

	tonnetz_viewport_container.position = tonnetz_panel.position + Vector2(0.0, config.tonnetz_title_height)
	tonnetz_viewport_container.size = tonnetz_panel.size - Vector2(0.0, config.tonnetz_title_height)
	tonnetz_viewport_container.custom_minimum_size = tonnetz_viewport_container.size
	tonnetz_viewport.size = Vector2i(tonnetz_viewport_container.size.round())

	if master_bpm_panel:
		master_bpm_panel.custom_minimum_size = Vector2(0.0, controls_panel.size.y)

	if lsystem_box_panel:
		lsystem_box_panel.custom_minimum_size = Vector2(lsystem_content_container.size.x, 0.0)
		lsystem_box_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	if start_screen:
		start_screen.visible = start_screen_visible
		start_screen.size = canvas_size
		start_screen.position = Vector2.ZERO
		start_pattern.size = canvas_size
		start_pattern.queue_redraw()
	if tutorial_overlay:
		move_child(tutorial_overlay, get_child_count() - 1)
		tutorial_overlay.position = Vector2.ZERO
		tutorial_overlay.size = canvas_size
		tutorial_overlay.custom_minimum_size = canvas_size
		_refresh_tutorial_targets()
		tutorial_overlay.refresh()
	queue_redraw()

func _on_viewport_size_changed() -> void:
	_apply_layout()

func center_tonnetz_view(builder: TonnetzBuilder) -> void:
	if not builder or builder.nodes.is_empty() or not tonnetz_viewport:
		return

	var bounds := _get_tonnetz_bounds(builder)

	if bounds.size == Vector2.ZERO:
		return

	var viewport_center := tonnetz_viewport_container.size * 0.5
	var content_center := bounds.get_center()
	tonnetz_view_zoom = config.tonnetz_view_zoom
	tonnetz_view_offset = viewport_center - content_center * tonnetz_view_zoom
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

	tutorial_voice_card = null

	if walk_card_visible:
		voice_list.add_child(_create_walk_lsystem_card())

	if lsystems.is_empty():
		voice_list.add_child(_create_empty_lsystem_card())
		_refresh_tutorial_targets()
		return

	for i in range(lsystems.size()):
		var color: Color = config.ui_panel_color

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

	_refresh_tutorial_targets()

func _create_walk_lsystem_card() -> Control:
	var panel := PanelContainer.new()
	panel.name = "GenerateWalkCard"
	panel.custom_minimum_size = Vector2(0, 0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	var style := StyleBoxFlat.new()
	style.bg_color = config.ui_panel_color
	style.border_color = config.ui_panel_border_color
	style.set_corner_radius_all(0)
	style.set_border_width_all(1)
	style.set_content_margin(SIDE_LEFT, 14)
	style.set_content_margin(SIDE_TOP, 14)
	style.set_content_margin(SIDE_RIGHT, 14)
	style.set_content_margin(SIDE_BOTTOM, 14)
	panel.add_theme_stylebox_override("panel", style)

	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 8)
	panel.add_child(card)

	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_child(header)

	var title := Label.new()
	_apply_label_style(title)
	title.text = "Record Own Walk"
	title.modulate = config.ui_text_color
	title.add_theme_font_size_override("font_size", 18)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var close_button := Button.new()
	close_button.text = "Close"
	_apply_button_style(close_button)
	close_button.tooltip_text = "Close walk generator"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.mouse_filter = Control.MOUSE_FILTER_STOP
	close_button.custom_minimum_size = Vector2(78, 28)
	close_button.pressed.connect(_on_generate_walk_close_pressed)
	header.add_child(close_button)

	card.add_child(_create_walk_recorder_controls(false))
	return panel


func _create_empty_lsystem_card() -> Control:
	var panel := PanelContainer.new()
	panel.name = "NoLSystemsCard"
	panel.custom_minimum_size = Vector2(0, 0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	var style := StyleBoxFlat.new()
	style.bg_color = config.ui_panel_color
	style.border_color = config.ui_panel_border_color
	style.set_corner_radius_all(0)
	style.set_border_width_all(1)
	style.set_content_margin(SIDE_LEFT, 14)
	style.set_content_margin(SIDE_TOP, 16)
	style.set_content_margin(SIDE_RIGHT, 14)
	style.set_content_margin(SIDE_BOTTOM, 14)
	panel.add_theme_stylebox_override("panel", style)

	var card := VBoxContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(card)

	var title := Label.new()
	_apply_label_style(title)
	title.text = "No grammar yet."
	title.add_theme_font_size_override("font_size", 20)
	card.add_child(title)

	var description := Label.new()
	_apply_label_style(description)
	description.text = "Start with a random grammar or draw a walk."
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(description)

	return panel


func _setup_lsystem_voice_list() -> void:
	lsystem_box_panel = _create_box_panel("LSystemBox")
	lsystem_box_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var lsystem_box_style := lsystem_box_panel.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	lsystem_box_style.set_content_margin(SIDE_TOP, 18)
	lsystem_box_panel.add_theme_stylebox_override("panel", lsystem_box_style)
	lsystem_content_container.add_child(lsystem_box_panel)

	lsystem_box_container = VBoxContainer.new()
	lsystem_box_container.name = "LSystemBoxContent"
	lsystem_box_container.add_theme_constant_override("separation", 20)
	lsystem_box_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lsystem_box_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lsystem_box_panel.add_child(lsystem_box_container)

	var header := VBoxContainer.new()
	header.name = "LSystemHeader"
	header.add_theme_constant_override("separation", 18)
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lsystem_box_container.add_child(header)

	var title := _create_label("L-Systems")
	var fv := FontVariation.new()
	fv.base_font = config.font
	fv.variation_opentype = {"weight": 700}
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_font_override("font", fv)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var walk_row := HBoxContainer.new()
	walk_row.name = "RecordWalkRow"
	walk_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(walk_row)

	var record_own_walk_button := _create_generation_card_button(
		"Record Own Walk",
		"Show walk generation controls"
	)
	record_own_walk_button.name = "RecordOwnWalkButton"
	record_own_walk_button.pressed.connect(_on_generate_walk_tile_pressed)
	walk_row.add_child(record_own_walk_button)

	var add_row := HBoxContainer.new()
	add_row.name = "AddRandomGrammarRow"
	add_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(add_row)

	var add_random_lsystem_button := _create_generation_card_button(
		"Add Random Grammar",
		"Create a random L-system"
	)
	add_random_lsystem_button.name = "AddRandomGrammarButton"
	add_random_lsystem_button.pressed.connect(_on_add_random_lsystem_pressed)
	add_row.add_child(add_random_lsystem_button)

	var margin := MarginContainer.new()
	margin.name = "LSystemContentMargin"
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lsystem_box_container.add_child(margin)

	voice_scroll = ScrollContainer.new()
	voice_scroll.name = "LSystemVoiceScroll"
	voice_scroll.custom_minimum_size = Vector2.ZERO
	voice_scroll.follow_focus = true
	voice_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	voice_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	voice_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	voice_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_apply_scrollbar_style(voice_scroll)
	margin.add_child(voice_scroll)

	var voice_list_margin := MarginContainer.new()
	voice_list_margin.name = "LSystemVoiceListMargin"
	voice_list_margin.add_theme_constant_override("margin_right", 22)
	voice_list_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	voice_list_margin.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	voice_scroll.add_child(voice_list_margin)

	voice_list = VBoxContainer.new()
	voice_list.name = "LSystemVoiceList"
	voice_list.add_theme_constant_override("separation", 18)
	voice_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	voice_list.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	voice_list_margin.add_child(voice_list)

func _create_generation_card_button(text: String, tooltip: String) -> Button:
	var button := Button.new()
	button.text = text
	_apply_panel_button_style(button)
	button.tooltip_text = tooltip
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, 44)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.add_theme_font_size_override("font_size", 16)
	return button

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
	panel.custom_minimum_size = Vector2(0, 0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.gui_input.connect(_on_lsystem_card_gui_input.bind(index))

	if is_active:
		tutorial_voice_card = panel

	var style := StyleBoxFlat.new()
	style.bg_color = config.ui_panel_color
	style.border_color = config.ui_panel_border_color
	style.set_corner_radius_all(0)
	style.set_border_width_all(config.ui_panel_border_width)
	style.set_content_margin(SIDE_LEFT, 2)
	style.set_content_margin(SIDE_TOP, 2)
	style.set_content_margin(SIDE_RIGHT, 2)
	style.set_content_margin(SIDE_BOTTOM, 10 if is_active else 2)
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

	var header_color: Color = color
	var header_text_color: Color = config.ui_text_color
	var header_style := StyleBoxFlat.new()
	header_style.bg_color = header_color
	header_style.border_color = config.ui_panel_border_color
	header_style.set_border_width(SIDE_BOTTOM, config.ui_panel_border_width)
	header_style.set_corner_radius_all(0)
	header_style.set_content_margin(SIDE_LEFT, 12)
	header_style.set_content_margin(SIDE_TOP, 10)
	header_style.set_content_margin(SIDE_RIGHT, 12)
	header_style.set_content_margin(SIDE_BOTTOM, 10)
	header_panel.add_theme_stylebox_override("panel", header_style)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.mouse_filter = Control.MOUSE_FILTER_PASS
	header_panel.add_child(header)

	var accordion_icon := Label.new()
	_apply_label_style(accordion_icon)
	accordion_icon.text = "▼" if is_active else "▲"
	accordion_icon.modulate = header_text_color
	accordion_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(accordion_icon)

########## TITLE #############
	var display_number := int(info.get("display_number", index + 1))
	var title := Label.new()
	_apply_label_style(title)
	title.text = "Voice %d" % display_number
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fv := FontVariation.new()
	fv.base_font = config.font
	fv.variation_opentype = {"weight": 700}
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_font_override("font", fv)
	title.modulate = header_text_color
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var mute_button := Button.new()
	mute_button.text = "Mute"
	_apply_button_style(mute_button)
	mute_button.toggle_mode = true
	mute_button.button_pressed = bool(info.get("muted", false))
	mute_button.focus_mode = Control.FOCUS_NONE
	mute_button.custom_minimum_size = Vector2(70, 28)
	_update_voice_mute_button(mute_button, mute_button.button_pressed)
	mute_button.toggled.connect(_on_voice_mute_toggled.bind(index, mute_button))
	header.add_child(mute_button)

	var solo_button := Button.new()
	solo_button.text = "Solo"
	_apply_button_style(solo_button)
	solo_button.toggle_mode = true
	solo_button.button_pressed = bool(info.get("solo", false))
	solo_button.tooltip_text = "Solo voice"
	solo_button.focus_mode = Control.FOCUS_NONE
	solo_button.custom_minimum_size = Vector2(58, 28)
	_apply_toggle_button_state(solo_button, solo_button.button_pressed)
	solo_button.toggled.connect(_on_voice_solo_toggled.bind(index, solo_button))
	header.add_child(solo_button)

	if not is_active:
		return panel

	var action_margin := MarginContainer.new()
	action_margin.name = "VoiceActionMargin"
	action_margin.add_theme_constant_override("margin_left", 10)
	action_margin.add_theme_constant_override("margin_top", 12)
	action_margin.add_theme_constant_override("margin_right", 10)
	action_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_child(action_margin)

	var action_column := VBoxContainer.new()
	action_column.name = "VoiceActionColumn"
	action_column.add_theme_constant_override("separation", 14)
	action_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_margin.add_child(action_column)

	var action_row := HBoxContainer.new()
	action_row.name = "VoiceActionRow"
	action_row.add_theme_constant_override("separation", 10)
	action_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_column.add_child(action_row)

	var duplicate_button := Button.new()
	duplicate_button.name = "DuplicateVoiceButton%d" % index
	duplicate_button.text = "Duplicate"
	_apply_button_style(duplicate_button)
	duplicate_button.tooltip_text = "Duplicate voice"
	duplicate_button.focus_mode = Control.FOCUS_NONE
	duplicate_button.custom_minimum_size = Vector2(0, 28)
	duplicate_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	duplicate_button.pressed.connect(_on_voice_duplicate_pressed.bind(index))
	action_row.add_child(duplicate_button)

	var randomize_button := Button.new()
	randomize_button.name = "RandomizeVoiceButton%d" % index
	randomize_button.text = "Randomize"
	_apply_button_style(randomize_button)
	randomize_button.tooltip_text = "Randomize voice"
	randomize_button.focus_mode = Control.FOCUS_NONE
	randomize_button.custom_minimum_size = Vector2(0, 28)
	randomize_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	randomize_button.pressed.connect(_on_voice_randomize_pressed.bind(index))
	action_row.add_child(randomize_button)

	var delete_button := Button.new()
	delete_button.name = "DeleteVoiceButton%d" % index
	delete_button.text = "Delete"
	_apply_button_style(delete_button)
	delete_button.tooltip_text = "Delete voice"
	delete_button.focus_mode = Control.FOCUS_NONE
	delete_button.custom_minimum_size = Vector2(0, 28)
	delete_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	delete_button.pressed.connect(_on_voice_remove_pressed.bind(index))
	action_row.add_child(delete_button)

	var export_row := HBoxContainer.new()
	export_row.name = "VoiceExportRow"
	export_row.add_theme_constant_override("separation", 10)
	export_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_column.add_child(export_row)

	var export_midi_voice_button := Button.new()
	export_midi_voice_button.name = "ExportMidiVoiceButton%d" % index
	export_midi_voice_button.text = "Export MIDI"
	_apply_button_style(export_midi_voice_button)
	export_midi_voice_button.tooltip_text = "Export this voice as MIDI"
	export_midi_voice_button.focus_mode = Control.FOCUS_NONE
	export_midi_voice_button.custom_minimum_size = Vector2(0, 28)
	export_midi_voice_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	export_midi_voice_button.pressed.connect(_on_voice_export_midi_pressed.bind(index))
	export_row.add_child(export_midi_voice_button)

	var export_lsystem_voice_button := Button.new()
	export_lsystem_voice_button.name = "ExportLSystemVoiceButton%d" % index
	export_lsystem_voice_button.text = "Export L-system"
	_apply_button_style(export_lsystem_voice_button)
	export_lsystem_voice_button.tooltip_text = "Export this L-system as JSON"
	export_lsystem_voice_button.focus_mode = Control.FOCUS_NONE
	export_lsystem_voice_button.custom_minimum_size = Vector2(0, 28)
	export_lsystem_voice_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	export_lsystem_voice_button.pressed.connect(_on_voice_export_lsystem_pressed.bind(index))
	export_row.add_child(export_lsystem_voice_button)

	var body_margin := MarginContainer.new()
	body_margin.add_theme_constant_override("margin_left", 12)
	body_margin.add_theme_constant_override("margin_top", 24)
	body_margin.add_theme_constant_override("margin_right", 12)
	body_margin.add_theme_constant_override("margin_bottom", 14)
	body_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_child(body_margin)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", int(config.lsystem_section_gap))
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.mouse_filter = Control.MOUSE_FILTER_PASS
	body_margin.add_child(body)

	_add_voice_volume_controls(body, index, volume)

	body.add_child(_create_lsystem_walk_previews(index, color, info))

	var grammar_section := VBoxContainer.new()
	grammar_section.name = "GrammarSection"
	grammar_section.add_theme_constant_override("separation", 18)
	grammar_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(grammar_section)
	
########## AXIOM #############
	var axiom_row := HBoxContainer.new()
	axiom_row.add_theme_constant_override("separation", 10)
	axiom_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grammar_section.add_child(axiom_row)

	var axiom_label := Label.new()
	_apply_label_style(axiom_label)
	axiom_label.text = "Axiom"
	axiom_label.custom_minimum_size = Vector2(58, 0)
	axiom_label.add_theme_font_size_override("font_size", 16)
	#axiom_label.modulate = Color.BLACK
	axiom_row.add_child(axiom_label)

	var axiom_edit := LineEdit.new()
	axiom_edit.text = lsystem.axiom
	axiom_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	axiom_edit.custom_minimum_size = Vector2(0, 34)
	_apply_lsystem_line_edit_style(axiom_edit, color)
	axiom_edit.add_theme_font_size_override("font_size", 16)
	axiom_edit.text_submitted.connect(_on_voice_axiom_submitted.bind(index))
	axiom_row.add_child(axiom_edit)

	var rules_header := HBoxContainer.new()
	rules_header.add_theme_constant_override("separation", 10)
	rules_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grammar_section.add_child(rules_header)

	var symbol_header := _create_mono_label("Symbol", 16)
	symbol_header.custom_minimum_size = Vector2(64, 0)
	rules_header.add_child(symbol_header)

	var replacement_header := _create_mono_label("Replacement", 16)
	replacement_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rules_header.add_child(replacement_header)
	
########## PROD RULES #############
	for key in lsystem.rules:
		grammar_section.add_child(_create_rule_row(index, key, lsystem.rules[key], color))

	grammar_section.add_child(_create_iterations_stepper(index, lsystem.iterations))
	grammar_section.add_child(_create_generated_string_section(lsystem.generated_string))

	return panel

func _create_iterations_stepper(index: int, iterations: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var label := _create_label("Iterations:")
	label.add_theme_font_size_override("font_size", 16)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	var stepper := HBoxContainer.new()
	stepper.add_theme_constant_override("separation", 0)
	stepper.custom_minimum_size = Vector2(76, 38)
	row.add_child(stepper)

	var value_panel := PanelContainer.new()
	value_panel.custom_minimum_size = Vector2(46, 38)
	value_panel.add_theme_stylebox_override("panel", _create_control_style(
		config.ui_panel_color,
		config.ui_panel_border_color,
		1,
		0,
		0
	))
	stepper.add_child(value_panel)

	var value := Label.new()
	_apply_label_style(value)
	value.text = str(iterations)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value.add_theme_font_size_override("font_size", 16)
	value_panel.add_child(value)

	var button_column := VBoxContainer.new()
	button_column.add_theme_constant_override("separation", 0)
	button_column.custom_minimum_size = Vector2(30, 38)
	stepper.add_child(button_column)

	var up_button := Button.new()
	up_button.text = "▲"
	_apply_button_style(up_button)
	up_button.tooltip_text = "Increase iterations"
	up_button.custom_minimum_size = Vector2(30, 19)
	up_button.add_theme_font_size_override("font_size", 10)
	button_column.add_child(up_button)

	var down_button := Button.new()
	down_button.text = "▼"
	_apply_button_style(down_button)
	down_button.tooltip_text = "Decrease iterations"
	down_button.custom_minimum_size = Vector2(30, 19)
	down_button.add_theme_font_size_override("font_size", 10)
	button_column.add_child(down_button)

	up_button.pressed.connect(_on_voice_iterations_stepper_pressed.bind(index, value, 1))
	down_button.pressed.connect(_on_voice_iterations_stepper_pressed.bind(index, value, -1))
	return row

func _create_generated_string_section(generated_string: String) -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var title := _create_label("Generated String")
	title.add_theme_font_size_override("font_size", 16)
	column.add_child(title)

	var generated_label := _create_mono_label(generated_string, 16)
	generated_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	generated_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 78)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(generated_label)
	_apply_scrollbar_style(scroll)
	column.add_child(scroll)
	return column

func _create_mono_label(text: String, font_size: int = 12) -> Label:
	var label := _create_label(text)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_font_override("font", config.font)
	return label

##################################################
########## FUNCTIONS #############
##################################################
func _create_lsystem_walk_previews(
	index: int,
	color: Color,
	info: Dictionary
) -> Control:
	return _create_lsystem_walk_preview_row(
		index,
		color,
		int(info.get("node_direction_index", 5)),
		int(info.get("triangle_edge", 0))
	)

func _create_lsystem_walk_preview_row(
	index: int,
	color: Color,
	node_direction_index: int,
	triangle_edge: int
) -> Control:
	var column := VBoxContainer.new()
	column.name = "DirectionPreviewRow"
	column.add_theme_constant_override("separation", 10)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.mouse_filter = Control.MOUSE_FILTER_PASS

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(row)

	var left_button := Button.new()
	left_button.text = "▼"
	_apply_button_style(left_button)
	left_button.focus_mode = Control.FOCUS_NONE
	left_button.tooltip_text = "Rotate counterclockwise"
	left_button.pressed.connect(_on_lsystem_preview_direction_pressed.bind(index, -1))
	row.add_child(left_button)

	var preview := Control.new()
	preview.name = "DirectionPreview"
	preview.custom_minimum_size = config.walk_preview_size
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.draw.connect(
		_draw_lsystem_direction_preview.bind(
			preview,
			color,
			node_direction_index,
			triangle_edge
		)
	)
	row.add_child(preview)

	var right_button := Button.new()
	right_button.text = "▲"
	_apply_button_style(right_button)
	right_button.focus_mode = Control.FOCUS_NONE
	right_button.tooltip_text = "Rotate clockwise"
	right_button.pressed.connect(_on_lsystem_preview_direction_pressed.bind(index, 1))
	row.add_child(right_button)

	return column

func _draw_lsystem_direction_preview(
	preview: Control,
	color: Color,
	node_direction_index: int,
	triangle_edge: int
) -> void:
	var rect := Rect2(Vector2.ZERO, preview.size)
	preview.draw_rect(rect, config.ui_input_color, true)
	preview.draw_rect(rect, config.ui_panel_border_color, false, 1.0)
	var nodes_center := Vector2(rect.size.x * 0.32, rect.size.y * 0.5)
	var triangles_center := Vector2(rect.size.x * 0.74, rect.size.y * 0.5)
	var base_line_color: Color = config.line_color

	_draw_node_direction_marker(
		preview,
		nodes_center,
		color,
		base_line_color,
		node_direction_index
	)
	_draw_triangle_direction_marker(
		preview,
		triangles_center,
		color,
		base_line_color,
		triangle_edge
	)

func _draw_node_direction_marker(
	preview: Control,
	center: Vector2,
	color: Color,
	base_line_color: Color,
	node_direction_index: int
) -> void:
	var active_index := posmod(node_direction_index, WALK_PREVIEW_NODE_DIRECTIONS.size())
	var scale: float = 0.55
	var node_radius: float = config.note_radius * scale
	var marker_distance: float = float(config.offset) * scale * 0.5
	var line_width: float = config.line_width
	var outline_width: float = config.outline_width

	for direction_index in range(WALK_PREVIEW_NODE_DIRECTIONS.size()):
		var direction := Vector2(
			0.5 * float(WALK_PREVIEW_NODE_DIRECTIONS[direction_index].x - WALK_PREVIEW_NODE_DIRECTIONS[direction_index].y),
			0.866 * float(WALK_PREVIEW_NODE_DIRECTIONS[direction_index].x + WALK_PREVIEW_NODE_DIRECTIONS[direction_index].y)
		).normalized()
		var marker_color := color if direction_index == active_index else base_line_color
		var start: Vector2 = center + direction * (node_radius + 2.0)
		var end: Vector2 = center + direction * marker_distance
		preview.draw_line(start, end, marker_color, line_width, true)

	preview.draw_circle(center, node_radius + outline_width, config.note_border_color, true, -1.0, true)
	preview.draw_circle(center, node_radius, config.note_color, true, -1.0, true)

func _draw_triangle_direction_marker(
	preview: Control,
	center: Vector2,
	color: Color,
	base_line_color: Color,
	triangle_edge: int
) -> void:
	var active_edge := posmod(triangle_edge, 3)
	var radius: float = config.note_radius * 1.2
	var points := PackedVector2Array()

	for point_index in range(3):
		var angle := -PI / 2.0 + float(point_index) * TAU / 3.0
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)

	preview.draw_colored_polygon(points, config.note_color)

	for edge_index in range(3):
		var from_point := points[edge_index]
		var to_point := points[(edge_index + 1) % 3]
		var edge_color := color if edge_index == active_edge else base_line_color
		preview.draw_line(from_point, to_point, edge_color, config.line_width, true)


func _apply_lsystem_line_edit_style(
	line_edit: LineEdit,
	focus_color: Color = Color("#7E7E7E")
) -> void:
	var normal_style := _create_lsystem_line_edit_style(
		config.ui_text_color,
		config.ui_text_color,
		1
	)
	var focus_style := _create_lsystem_line_edit_style(
		config.ui_text_color,
		focus_color,
		2
	)

	line_edit.add_theme_stylebox_override("normal", normal_style)
	line_edit.add_theme_stylebox_override("focus", focus_style)
	line_edit.add_theme_color_override("font_color", config.ui_panel_color)
	line_edit.add_theme_color_override("font_focus_color", config.ui_panel_color)
	line_edit.add_theme_color_override("caret_color", config.ui_panel_color)
	line_edit.add_theme_color_override("selection_color", config.ui_selection_color)

func _create_lsystem_line_edit_style(bg_color: Color, border_color: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(0)
	style.set_content_margin(SIDE_LEFT, 7)
	style.set_content_margin(SIDE_TOP, 4)
	style.set_content_margin(SIDE_RIGHT, 7)
	style.set_content_margin(SIDE_BOTTOM, 4)
	return style

func _update_voice_mute_button(button: Button, muted: bool) -> void:
	button.text = "Unmute" if muted else "Mute"
	button.tooltip_text = "Unmute voice" if muted else "Mute voice"
	_apply_toggle_button_state(button, muted)

func _add_voice_volume_controls(card: VBoxContainer, index: int, volume: float) -> void:
	var control_group := VBoxContainer.new()
	control_group.name = "VoicePlaybackControls"
	control_group.add_theme_constant_override("separation", 6)
	control_group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_child(control_group)

	var trail_row := HBoxContainer.new()
	trail_row.add_theme_constant_override("separation", 4)
	control_group.add_child(trail_row)

	var trail_label := Label.new()
	_apply_label_style(trail_label)
	trail_label.text = "Trail Length"
	trail_label.add_theme_font_size_override("font_size", 13)
	trail_row.add_child(trail_label)

	var trail_value := Label.new()
	_apply_label_style(trail_value)
	trail_value.text = str(config.turtle_trail_max_steps)
	trail_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	trail_value.custom_minimum_size = Vector2(42, 0)
	trail_row.add_child(trail_value)

	var trail_slider := HSlider.new()
	_apply_slider_style(trail_slider)
	trail_slider.min_value = 1.0
	trail_slider.max_value = 30.0
	trail_slider.step = 1.0
	trail_slider.value = config.turtle_trail_max_steps
	trail_slider.custom_minimum_size = Vector2(140, 28)
	trail_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trail_slider.value_changed.connect(_on_trail_length_changed.bind(trail_value))
	trail_row.add_child(trail_slider)

	var volume_row := HBoxContainer.new()
	volume_row.add_theme_constant_override("separation", 4)
	control_group.add_child(volume_row)

	var volume_label := Label.new()
	_apply_label_style(volume_label)
	volume_label.text = "Volume"
	volume_label.add_theme_font_size_override("font_size", 13)
	volume_row.add_child(volume_label)

	var volume_value := Label.new()
	_apply_label_style(volume_value)
	volume_value.text = "%d%%" % int(round(volume * 100.0))
	volume_value.custom_minimum_size = Vector2(42, 0)
	volume_row.add_child(volume_value)

	var volume_slider := HSlider.new()
	_apply_slider_style(volume_slider)
	volume_slider.min_value = 0.0
	volume_slider.max_value = 1.0
	volume_slider.step = 0.01
	volume_slider.value = volume
	volume_slider.custom_minimum_size = Vector2(140, 28)
	volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	volume_slider.value_changed.connect(
		_on_voice_volume_changed.bind(index, volume_value)
	)
	volume_row.add_child(volume_slider)

func _create_rule_row(index: int, symbol: String, production: String, color: Color) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var input_row := HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 10)
	input_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(input_row)

	var symbol_label := _create_mono_label(symbol, 16)
	symbol_label.custom_minimum_size = Vector2(24, 34)
	symbol_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	input_row.add_child(symbol_label)

	var arrow_label := _create_mono_label("->", 16)
	arrow_label.custom_minimum_size = Vector2(34, 34)
	arrow_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	input_row.add_child(arrow_label)

	var production_edit := LineEdit.new()
	production_edit.text = production
	production_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	production_edit.custom_minimum_size = Vector2(0, 34)
	_apply_lsystem_line_edit_style(production_edit, color)
	production_edit.add_theme_font_override("font", config.font)
	production_edit.add_theme_font_size_override("font_size", 16)
	input_row.add_child(production_edit)

	var warning := Label.new()
	_apply_label_style(warning)
	warning.visible = false
	warning.modulate = config.ui_text_color
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


func _on_voice_randomize_pressed(index: int) -> void:
	lsystem_randomize_requested.emit(index)

func _on_voice_duplicate_pressed(index: int) -> void:
	lsystem_duplicate_requested.emit(index)

func _on_voice_solo_toggled(solo: bool, index: int, button: Button) -> void:
	_apply_toggle_button_state(button, solo)
	lsystem_solo_toggled.emit(index, solo)

func _on_voice_export_midi_pressed(index: int) -> void:
	if not export_midi_dialog:
		return

	export_dialog_mode = "midi"
	export_midi_voice_index = index
	export_midi_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	export_midi_dialog.title = "Export Voice MIDI"
	export_midi_dialog.filters = PackedStringArray(["*.mid ; MIDI files"])
	export_midi_dialog.current_file = _build_default_voice_midi_filename(index)
	export_midi_dialog.popup_centered(Vector2i(760, 520))

func _on_voice_export_lsystem_pressed(index: int) -> void:
	if not export_midi_dialog:
		return

	export_dialog_mode = "lsystem_voice"
	export_midi_voice_index = index
	export_midi_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	export_midi_dialog.title = "Export Voice L-system"
	export_midi_dialog.filters = PackedStringArray(["*.json ; JSON files"])
	export_midi_dialog.current_file = _build_default_voice_lsystem_filename(index)
	export_midi_dialog.popup_centered(Vector2i(760, 520))

func _on_voice_remove_pressed(index: int) -> void:
	lsystem_remove_requested.emit(index)

func _on_lsystem_preview_direction_pressed(index: int, delta: int) -> void:
	lsystem_preview_direction_changed.emit(index, delta)

func _on_voice_mute_toggled(muted: bool, index: int, button: Button) -> void:
	_update_voice_mute_button(button, muted)
	lsystem_mute_toggled.emit(index, muted)

func _on_voice_axiom_submitted(new_text: String, index: int) -> void:
	if new_text.is_empty():
		return
	lsystem_axiom_changed.emit(index, new_text[0])

func _on_voice_iterations_stepper_pressed(index: int, iterations_value: Label, delta: int) -> void:
	var iterations := int(clamp(
		int(iterations_value.text) + delta,
		0,
		10
	))
	iterations_value.text = str(iterations)
	lsystem_iterations_changed.emit(index, iterations)

func _on_add_random_lsystem_pressed() -> void:
	add_random_lsystem_requested.emit()

func _on_generate_walk_tile_pressed() -> void:
	if walk_card_visible:
		return

	walk_card_visible = true
	_insert_walk_lsystem_card()
	walk_recording_started.emit()

func _insert_walk_lsystem_card() -> void:
	if not voice_list:
		return

	voice_list.add_child(_create_walk_lsystem_card())
	voice_list.move_child(voice_list.get_child(voice_list.get_child_count() - 1), 0)

func _on_generate_walk_close_pressed() -> void:
	walk_card_visible = false
	_remove_walk_lsystem_card()
	walk_recording_cancelled.emit()

func _remove_walk_lsystem_card() -> void:
	if not voice_list:
		return

	for child in voice_list.get_children():
		if child.name == "GenerateWalkCard":
			child.queue_free()
			return

func _on_walk_record_pressed() -> void:
	if walk_record_button:
		walk_record_button.button_pressed = true
		_apply_toggle_button_state(walk_record_button, true)
	walk_recording_started.emit()

func _on_walk_undo_pressed() -> void:
	walk_recording_undo_requested.emit()

func _on_walk_generate_pressed() -> void:
	if walk_record_button:
		walk_record_button.button_pressed = false
		_apply_toggle_button_state(walk_record_button, false)
	walk_lsystem_generate_requested.emit()

func _on_walk_duration_pressed(selected_button: Button) -> void:
	for button in walk_duration_buttons:
		var active := button == selected_button
		button.set_pressed_no_signal(active)
		_apply_toggle_button_state(button, active)

	walk_recording_duration_changed.emit(float(selected_button.get_meta("duration_beats", 1.0)))


func _on_voice_volume_changed(new_value: float, index: int, volume_value: Label) -> void:
	volume_value.text = "%d%%" % int(round(new_value * 100.0))
	lsystem_volume_changed.emit(index, new_value)

func _on_trail_length_changed(new_value: float, trail_value: Label) -> void:
	var length_steps := int(round(new_value))
	trail_value.text = str(length_steps)
	trail_length_changed.emit(length_steps)

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


func _setup_right_control_boxes() -> void:
	playback_panel = _create_box_panel("PlaybackBox")
	playback_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	playback_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	controls_container.add_child(playback_panel)
	_setup_playback_box(playback_panel)

	master_bpm_panel = _create_box_panel("TempoBox")
	master_bpm_panel.name = "MasterBPMPanel"
	master_bpm_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	master_bpm_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	controls_container.add_child(master_bpm_panel)
	_setup_tempo_box(master_bpm_panel)

	export_panel = _create_box_panel("ExportBox")
	export_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	export_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	controls_container.add_child(export_panel)
	_setup_export_box(export_panel)

func _setup_playback_box(panel: PanelContainer) -> void:
	var content := _create_box_content("Playback")
	panel.add_child(content)

	var volume_row := HBoxContainer.new()
	volume_row.name = "MasterVolumeRow"
	volume_row.add_theme_constant_override("separation", 4)
	volume_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(volume_row)

	var volume_label := _create_label("Volume")
	volume_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	volume_row.add_child(volume_label)

	master_volume_value_label = _create_label("100%")
	master_volume_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	master_volume_value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	master_volume_value_label.custom_minimum_size = Vector2(48, 0)
	volume_row.add_child(master_volume_value_label)

	var master_volume_slider := HSlider.new()
	master_volume_slider.name = "MasterVolumeSlider"
	_apply_slider_style(master_volume_slider)
	master_volume_slider.min_value = 0.0
	master_volume_slider.max_value = 1.0
	master_volume_slider.step = 0.01
	master_volume_slider.value = 1.0
	master_volume_slider.custom_minimum_size = Vector2(120, 28)
	master_volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	master_volume_slider.value_changed.connect(_on_master_volume_changed)
	volume_row.add_child(master_volume_slider)

	all_mute_button = Button.new()
	all_mute_button.name = "AllMuteButton"
	all_mute_button.text = "Mute"
	_apply_button_style(all_mute_button)
	all_mute_button.tooltip_text = "Mute all voices"
	all_mute_button.toggle_mode = true
	all_mute_button.focus_mode = Control.FOCUS_NONE
	all_mute_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	all_mute_button.toggled.connect(_on_all_mute_toggled)
	content.add_child(all_mute_button)
	set_all_muted_visual(false)

func _setup_export_box(panel: PanelContainer) -> void:
	var content := _create_box_content("Export")
	panel.add_child(content)

	var lsystem_row := HBoxContainer.new()
	lsystem_row.name = "LSystemExportImportRow"
	lsystem_row.add_theme_constant_override("separation", 6)
	lsystem_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(lsystem_row)

	var export_lsystems_button := Button.new()
	export_lsystems_button.name = "ExportLSystemsButton"
	export_lsystems_button.text = "Export L-systems"
	_apply_button_style(export_lsystems_button)
	export_lsystems_button.tooltip_text = "Export L-system definitions"
	export_lsystems_button.focus_mode = Control.FOCUS_NONE
	export_lsystems_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	export_lsystems_button.mouse_filter = Control.MOUSE_FILTER_STOP
	export_lsystems_button.pressed.connect(_on_export_lsystems_pressed)
	lsystem_row.add_child(export_lsystems_button)

	var import_lsystems_button := Button.new()
	import_lsystems_button.name = "ImportLSystemsButton"
	import_lsystems_button.text = "Import L-systems"
	_apply_button_style(import_lsystems_button)
	import_lsystems_button.tooltip_text = "Import L-system definitions"
	import_lsystems_button.focus_mode = Control.FOCUS_NONE
	import_lsystems_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	import_lsystems_button.mouse_filter = Control.MOUSE_FILTER_STOP
	import_lsystems_button.pressed.connect(_on_import_lsystems_pressed)
	lsystem_row.add_child(import_lsystems_button)

	var export_midi_button := Button.new()
	export_midi_button.name = "ExportMidiButton"
	export_midi_button.text = "Export MIDI"
	_apply_button_style(export_midi_button)
	export_midi_button.tooltip_text = "Export all voices as MIDI"
	export_midi_button.focus_mode = Control.FOCUS_NONE
	export_midi_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	export_midi_button.mouse_filter = Control.MOUSE_FILTER_STOP
	export_midi_button.pressed.connect(_on_export_midi_pressed)
	content.add_child(export_midi_button)

func _setup_tempo_box(panel: PanelContainer) -> void:
	var content := _create_box_content("Tempo")
	panel.add_child(content)

	var bpm_row := HBoxContainer.new()
	bpm_row.name = "BPMRow"
	bpm_row.add_theme_constant_override("separation", 4)
	bpm_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(bpm_row)

	var title := _create_label("BPM")
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bpm_row.add_child(title)

	bpm_value_label = _create_label("120")
	bpm_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bpm_value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bpm_value_label.custom_minimum_size = Vector2(70, 0)
	bpm_row.add_child(bpm_value_label)

	bpm_slider = HSlider.new()
	bpm_slider.name = "BPMSlider"
	_apply_slider_style(bpm_slider)
	bpm_slider.min_value = 20.0
	bpm_slider.max_value = 200.0
	bpm_slider.step = 10.0
	bpm_slider.value = 120.0
	bpm_slider.exp_edit = true
	bpm_slider.custom_minimum_size = Vector2(120, 28)
	bpm_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bpm_slider.tooltip_text = "BPM"
	bpm_slider.value_changed.connect(_on_bpm_value_changed)
	bpm_slider.drag_ended.connect(on_bpm_changed)
	bpm_row.add_child(bpm_slider)

func _create_box_content(title_text: String) -> VBoxContainer:
	var content := VBoxContainer.new()
	content.name = title_text + "Content"
	content.add_theme_constant_override("separation", 8)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var title := _create_label(title_text)
	title.add_theme_font_size_override("font_size", 18)
	content.add_child(title)
	return content


func _setup_export_midi_dialog() -> void:
	export_midi_dialog = FileDialog.new()
	export_midi_dialog.name = "ExportDialog"
	export_midi_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	export_midi_dialog.access = FileDialog.ACCESS_FILESYSTEM
	export_midi_dialog.title = "Export MIDI"
	export_midi_dialog.filters = PackedStringArray(["*.mid ; MIDI files"])
	export_midi_dialog.current_file = _build_default_midi_filename()
	export_midi_dialog.file_selected.connect(_on_export_midi_file_selected)
	add_child(export_midi_dialog)


func _setup_start_screen() -> void:
	start_screen = Control.new()
	start_screen.name = "StartScreen"
	start_screen.mouse_filter = Control.MOUSE_FILTER_STOP
	start_screen.z_index = 500
	add_child(start_screen)

	start_pattern = Control.new()
	start_pattern.name = "StartPattern"
	start_pattern.mouse_filter = Control.MOUSE_FILTER_IGNORE
	start_pattern.draw.connect(_draw_start_pattern)
	start_screen.add_child(start_pattern)

	var center := CenterContainer.new()
	center.name = "StartCenter"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	start_screen.add_child(center)

	var content_panel := PanelContainer.new()
	content_panel.name = "StartContentPanel"
	content_panel.custom_minimum_size = Vector2(460, 220)
	content_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = config.ui_panel_color
	panel_style.border_color = config.ui_panel_border_color
	panel_style.set_border_width_all(config.ui_panel_border_width)
	panel_style.set_corner_radius_all(0)
	panel_style.set_content_margin(SIDE_LEFT, 28)
	panel_style.set_content_margin(SIDE_TOP, 24)
	panel_style.set_content_margin(SIDE_RIGHT, 28)
	panel_style.set_content_margin(SIDE_BOTTOM, 24)
	content_panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(content_panel)

	var content := VBoxContainer.new()
	content.name = "StartContent"
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 20)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_panel.add_child(content)

	var title := Label.new()
	_apply_label_style(title)
	title.text = "Interactive\nMusic Generation\nwith Tonnetz-Based\nLindenmayer Systems"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 24)
	title.modulate = config.ui_text_color
	var title_font := FontVariation.new()
	title_font.base_font = config.font
	title_font.variation_opentype = {"weight": 760}
	title.add_theme_font_override("font", title_font)
	content.add_child(title)

	var button_row := HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 10)
	button_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	content.add_child(button_row)

	var tutorial_button := Button.new()
	tutorial_button.name = "TutorialButton"
	tutorial_button.text = "Tutorial"
	_apply_button_style(tutorial_button)
	tutorial_button.custom_minimum_size = Vector2(180, 52)
	tutorial_button.focus_mode = Control.FOCUS_NONE
	tutorial_button.pressed.connect(_on_tutorial_button_pressed)
	button_row.add_child(tutorial_button)

	var start_button := Button.new()
	start_button.name = "StartButton"
	start_button.text = "Start"
	_apply_button_style(start_button)
	start_button.custom_minimum_size = Vector2(180, 52)
	start_button.focus_mode = Control.FOCUS_NONE
	start_button.pressed.connect(_on_start_button_pressed)
	button_row.add_child(start_button)


func _setup_tutorial_screen() -> void:
	tutorial_overlay = TutorialOverlayScript.new()
	tutorial_overlay.name = "TutorialOverlay"
	_refresh_tutorial_targets()
	add_child(tutorial_overlay)

func _refresh_tutorial_targets() -> void:
	if not tutorial_overlay:
		return

	tutorial_overlay.set_targets(
		left_panel,
		tonnetz_panel,
		controls_panel,
		{
			"voice_card": tutorial_voice_card,
			"playback_panel": playback_panel,
			"tempo_panel": master_bpm_panel,
			"export_panel": export_panel
		}
	)

func _draw_start_pattern() -> void:
	_draw_tonnetz_pattern(start_pattern, Rect2(Vector2.ZERO, start_pattern.size))

func _draw_tonnetz_pattern(canvas: Control, rect: Rect2) -> void:
	canvas.draw_rect(rect, config.tonnetz_background_color, true)
	var line_color: Color = config.line_color
	var node_border_color: Color = config.note_border_color
	var node_fill_color: Color = config.note_color
	var label_color: Color = config.note_label_color
	var center_row := int(config.row_count / 2)
	var center_column := int(config.column_count / 2)
	var center_coord := _coord_from_start_row_column(center_row, center_column)
	var origin := rect.get_center() - _get_start_coord_center(center_coord, Vector2.ZERO)
	var start_nodes := {}

	for row in range(config.row_count):
		for column in range(config.column_count):
			start_nodes[_coord_from_start_row_column(row, column)] = true

	for row in range(config.row_count):
		for column in range(config.column_count):
			var coord := _coord_from_start_row_column(row, column)
			var center := _get_start_coord_center(coord, origin)
			var right_coord := _coord_from_start_row_column(row, column + 1)

			if start_nodes.has(right_coord):
				_draw_start_tonnetz_line(canvas, center, right_coord, origin, line_color)
			if start_nodes.has(coord + Vector2i(-1, 0)):
				_draw_start_tonnetz_line(canvas, center, coord + Vector2i(-1, 0), origin, line_color)
			if start_nodes.has(coord + Vector2i(0, -1)):
				_draw_start_tonnetz_line(canvas, center, coord + Vector2i(0, -1), origin, line_color)

	for row in range(config.row_count):
		for column in range(config.column_count):
			var center := _get_start_coord_center(_coord_from_start_row_column(row, column), origin)
			canvas.draw_circle(center, config.note_radius + config.outline_width, node_border_color, true, -1.0, true)
			canvas.draw_circle(center, config.note_radius, node_fill_color, true, -1.0, true)
			_draw_start_note_label(canvas, row, column, center, label_color)

func _draw_start_note_label(canvas: Control, row: int, column: int, center: Vector2, label_color: Color) -> void:
	var coord := _coord_from_start_row_column(row, column)
	var pitch: int = config.base_midi_note + coord.x * 3 - coord.y * 4
	var note_name: String = config.NOTE_NAMES[posmod(pitch, 12)]
	var octave_text := str(floori(float(pitch) / 12.0))
	var note_font_size: int = config.node_note_font_size
	var octave_font_size: int = config.node_octave_font_size
	var note_size: Vector2 = config.font.get_string_size(note_name, HORIZONTAL_ALIGNMENT_LEFT, -1.0, note_font_size)
	var octave_size: Vector2 = config.font.get_string_size(octave_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, octave_font_size)
	var total_width: float = note_size.x + octave_size.x
	var baseline := center + Vector2(-total_width * 0.5 + 1.0, 3.0)

	canvas.draw_string(
		config.font,
		baseline,
		note_name,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		note_font_size,
		label_color
	)
	canvas.draw_string(
		config.font,
		baseline + Vector2(note_size.x, 3.0),
		octave_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		octave_font_size,
		label_color
	)

func _draw_start_tonnetz_line(
	canvas: Control,
	center: Vector2,
	to_coord: Vector2i,
	tile_origin: Vector2,
	color: Color
) -> void:
	var to_center := _get_start_coord_center(to_coord, tile_origin)
	var unit := (to_center - center).normalized()
	var radius_offset: Vector2 = unit * config.note_radius
	canvas.draw_line(center + radius_offset, to_center - radius_offset, color, config.line_width, true)

func _get_start_coord_center(coord: Vector2i, origin: Vector2) -> Vector2:
	var x: float = config.offset * 0.5 * float(coord.x - coord.y)
	var y: float = config.offset * 0.866 * float(coord.x + coord.y)
	return origin + Vector2(x, y)

func _coord_from_start_row_column(row: int, column: int) -> Vector2i:
	var row_start_offset := -ceili(float(row) / 2.0)
	return Vector2i(column + row + row_start_offset, -column - row_start_offset)


func _on_start_button_pressed() -> void:
	start_screen_visible = false
	start_screen.hide()
	tutorial_overlay.hide_tutorial()

func _on_tutorial_button_pressed() -> void:
	start_screen_visible = false
	start_screen.hide()
	tutorial_overlay.start_tutorial()

func _on_all_mute_toggled(muted: bool) -> void:
	set_all_muted_visual(muted)
	all_lsystems_mute_toggled.emit(muted)

func _on_master_volume_changed(new_value: float) -> void:
	master_volume_value_label.text = "%d%%" % int(round(new_value * 100.0))
	if is_zero_approx(new_value) and not all_muted:
		set_all_muted_visual(true)
		all_lsystems_mute_toggled.emit(true)
	elif new_value > 0.0 and all_muted:
		set_all_muted_visual(false)
		all_lsystems_mute_toggled.emit(false)
	master_volume_changed.emit(new_value)

func _on_export_midi_pressed() -> void:
	if not export_midi_dialog:
		return

	export_dialog_mode = "midi"
	export_midi_voice_index = -1
	export_midi_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	export_midi_dialog.title = "Export MIDI"
	export_midi_dialog.filters = PackedStringArray(["*.mid ; MIDI files"])
	export_midi_dialog.current_file = _build_default_midi_filename()
	export_midi_dialog.popup_centered(Vector2i(760, 520))

func _on_export_lsystems_pressed() -> void:
	if not export_midi_dialog:
		return

	export_dialog_mode = "lsystems"
	export_midi_voice_index = -1
	export_midi_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	export_midi_dialog.title = "Export L-systems"
	export_midi_dialog.filters = PackedStringArray(["*.json ; JSON files"])
	export_midi_dialog.current_file = _build_default_lsystems_filename()
	export_midi_dialog.popup_centered(Vector2i(760, 520))

func _on_import_lsystems_pressed() -> void:
	if not export_midi_dialog:
		return

	export_dialog_mode = "import_lsystems"
	export_midi_voice_index = -1
	export_midi_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	export_midi_dialog.title = "Import L-systems"
	export_midi_dialog.filters = PackedStringArray(["*.json ; JSON files"])
	export_midi_dialog.current_file = ""
	export_midi_dialog.popup_centered(Vector2i(760, 520))

func _on_export_midi_file_selected(path: String) -> void:
	if path.is_empty():
		export_midi_voice_index = -1
		export_dialog_mode = ""
		return

	if export_dialog_mode == "import_lsystems":
		import_lsystems_requested.emit(path)
	elif (
		(export_dialog_mode == "lsystems" or export_dialog_mode == "lsystem_voice")
		and path.get_extension().to_lower() != "json"
	):
		path += ".json"
	elif (
		export_dialog_mode != "lsystems"
		and export_dialog_mode != "lsystem_voice"
		and path.get_extension().to_lower() != "mid"
	):
		path += ".mid"

	if export_dialog_mode == "lsystems":
		export_lsystems_requested.emit(path)
	elif export_dialog_mode == "lsystem_voice":
		export_lsystem_requested.emit(export_midi_voice_index, path)
	elif export_dialog_mode == "import_lsystems":
		pass
	elif export_midi_voice_index >= 0:
		export_midi_voice_requested.emit(export_midi_voice_index, path)
	else:
		export_midi_requested.emit(path)

	export_midi_voice_index = -1
	export_dialog_mode = ""


func _build_default_midi_filename() -> String:
	var date := Time.get_datetime_dict_from_system()
	return "tonnetz_%04d%02d%02d_%02d%02d.mid" % [
		int(date["year"]),
		int(date["month"]),
		int(date["day"]),
		int(date["hour"]),
		int(date["minute"])
	]

func _build_default_lsystems_filename() -> String:
	var date := Time.get_datetime_dict_from_system()
	return "lsystems_%04d%02d%02d_%02d%02d.json" % [
		int(date["year"]),
		int(date["month"]),
		int(date["day"]),
		int(date["hour"]),
		int(date["minute"])
	]

func _build_default_voice_lsystem_filename(index: int) -> String:
	var date := Time.get_datetime_dict_from_system()
	return "tonnetz_voice_%d_%04d%02d%02d_%02d%02d.json" % [
		index + 1,
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


func set_all_muted_visual(muted: bool) -> void:
	all_muted = muted
	if not all_mute_button:
		return

	all_mute_button.set_pressed_no_signal(all_muted)
	all_mute_button.text = "Unmute" if all_muted else "Mute"
	all_mute_button.tooltip_text = "Unmute all voices" if all_muted else "Mute all voices"
	_apply_toggle_button_state(all_mute_button, all_muted)

func _on_bpm_value_changed(new_value: float) -> void:
	bpm_value_label.text = "%d" % int(new_value)

func on_bpm_changed(ended: bool) -> void:
	if not ended:
		return
	var new_value := int(bpm_slider.value)
	CL.bpm = new_value
	bpm_value_label.text = "%d" % new_value
