extends Control

##################################################
########## SIGNALS #############
##################################################
signal add_random_lsystem_requested
signal lsystem_selected(index: int)
signal lsystem_randomize_requested(index: int)
signal lsystem_duplicate_requested(index: int)
signal lsystem_remove_requested(index: int)
signal lsystem_stop_requested(index: int)
signal lsystem_resume_requested(index: int)
signal lsystem_solo_toggled(index: int, solo: bool)
signal lsystem_axiom_changed(index: int, new_axiom: String)
signal lsystem_iterations_changed(index: int, iterations: int)
signal lsystem_rule_changed(index: int, symbol: String, production: String)
signal lsystem_volume_changed(index: int, volume: float)
signal lsystem_mute_toggled(index: int, muted: bool)
signal lsystem_preview_direction_changed(index: int, delta: int)
signal walk_recording_started
signal walk_recording_cancelled
signal walk_recording_undo_requested
signal walk_recording_duration_changed(duration_beats: float)
signal walk_lsystem_generate_requested
signal walk_lsystem_regenerate_requested
signal tonnetz_clicked(world_position: Vector2)
signal global_play_pause_toggled(paused: bool)
signal stop_all_lsystems_requested
signal export_midi_requested(path: String)
signal export_midi_voice_requested(index: int, path: String)

##################################################
########## ONREADY VARS #############
##################################################
@onready var config = Config.config

@onready var tonnetz_viewport_container: SubViewportContainer = $TonnetzViewportContainer
@onready var tonnetz_viewport: SubViewport = $TonnetzViewportContainer/TonnetzViewport

##################################################
########## CONST #############
##################################################
const OUTER_MARGIN := 0.0
const LEFT_PANEL_MIN_WIDTH := 320.0
const LEFT_PANEL_MAX_WIDTH := 460.0
const LEFT_PANEL_WIDTH_RATIO := 0.23
const TONNETZ_MIN_WIDTH := 420.0

const PANEL_PADDING := 12.0
const PANEL_GAP := 12.0
const TAB_CONTENT_TOP_MARGIN := 14.0
const LSYSTEM_CARD_WIDTH := 288.0
const MUTED_ICON_PATH := "res://icons/muted.svg"
const UNMUTED_ICON_PATH := "res://icons/unmuted.svg"
const STOP_ICON_PATH := "res://icons/cancel.svg"
const GENERAL_PANEL_HEIGHT := 190.0
const WALK_PREVIEW_SIZE := Vector2(252.0, 82.0)
const WALK_PREVIEW_NODE_DIRECTIONS := [
	Vector2i(1, -1), Vector2i(0, -1), Vector2i(-1, 0),
	Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 0)
]
const TonnetzTileLayerScript := preload("res://scripts/tonnetz_tile_layer.gd")


##################################################
########## VAR DECLARATIO S #############
##################################################
var left_panel: Panel
var tonnetz_panel: Panel
var tonnetz_tile_layer: Control
var controls_panel: Panel
var controls_container: VBoxContainer
var lsystem_content_container: VBoxContainer
var voice_scroll: ScrollContainer
var voice_list: VBoxContainer
var bpm_value_label: Label
var bpm_slider: Slider
var walk_record_button: Button
var walk_undo_button: Button
var walk_generate_button: Button
var walk_regenerate_button: Button
var walk_duration_button: OptionButton
var global_play_pause_button: Button
var stop_all_button: Button
var export_midi_button: Button
var export_midi_dialog: FileDialog
var master_bpm_panel: PanelContainer
var start_screen: Control
var start_pattern: Control
var start_button: Button
var export_midi_voice_index := -1
var global_paused := false
var start_screen_visible := true
var tonnetz_view_offset := Vector2.ZERO
var tonnetz_view_zoom := 1.0
var tonnetz_bounds := Rect2()
var tonnetz_bounds_available := false
var tonnetz_builder: TonnetzBuilder = null
var walk_card_visible := false
var icon_cache := {}

##################################################
########## SETUP UI #############
##################################################
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_viewport().size_changed.connect(_on_viewport_size_changed)

	_setup_layout_panels()
	_setup_global_play_pause_button()
	_setup_master_bpm_control()
	_setup_export_midi_dialog()
	_setup_start_screen()
	_apply_layout()
	tonnetz_viewport_container.mouse_filter = Control.MOUSE_FILTER_PASS
	tonnetz_viewport_container.gui_input.connect(_on_tonnetz_viewport_gui_input)
	_setup_lsystem_voice_list()
	_apply_layout()
	
	bpm_value_label.text = "%d BPM" % int(config.bpm)
	bpm_slider.value = config.bpm
	set_global_paused_visual(true)

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

	return tonnetz_viewport.canvas_transform.affine_inverse() * _get_wrapped_tonnetz_viewport_position(viewport_position)


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

	if tonnetz_tile_layer:
		tonnetz_tile_layer.queue_redraw()

func _get_wrapped_tonnetz_viewport_position(viewport_position: Vector2) -> Vector2:
	if not tonnetz_viewport_container or not tonnetz_viewport or not tonnetz_builder:
		return viewport_position

	var target_rect := Rect2(Vector2.ZERO, tonnetz_viewport_container.size)
	var best_position := viewport_position
	var best_distance := INF

	for tile in _get_tonnetz_screen_tiles():
		var tile_offset: Vector2 = tile["offset"]
		var wrapped_position := viewport_position - tile_offset

		if not target_rect.has_point(wrapped_position):
			continue

		var world_position := tonnetz_viewport.canvas_transform.affine_inverse() * wrapped_position
		var anchor = tonnetz_builder.get_nearest_spawn_anchor(world_position)

		if anchor == null:
			continue

		var anchor_screen_position: Vector2 = (
			tonnetz_viewport.canvas_transform * anchor.get_center()
			+ tile_offset
		)
		var distance := anchor_screen_position.distance_squared_to(viewport_position)

		if distance < best_distance:
			best_position = wrapped_position
			best_distance = distance

	return best_position

func _get_tonnetz_screen_tiles() -> Array[Dictionary]:
	var tiles: Array[Dictionary] = []
	var radius := TonnetzConfig.TONNETZ_VIEWPORT_TILING_RADIUS

	for row in range(-radius, radius + 1):
		for column in range(-radius, radius + 1):
			var world_offset := tonnetz_builder.get_tile_offset(Vector2i(column, row))
			var screen_offset := tonnetz_viewport.canvas_transform.basis_xform(world_offset)
			tiles.append({
				"offset": screen_offset,
				"distance": max(abs(column), abs(row))
			})

	tiles.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["distance"]) > int(b["distance"])
	)
	return tiles

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

	if show_record_button:
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

	column.add_child(edit_row)

	return column


func _create_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.modulate = config.ui_text_color
	return label


# The top-level layout fills whatever game area Godot exposes after stretch.
func _setup_layout_panels() -> void:
	left_panel = _create_layout_panel("LeftControlPanel", config.ui_panel_color, config.ui_panel_border_color, 4)
	tonnetz_panel = _create_layout_panel("TonnetzPanel", config.tonnetz_background_color, config.tonnetz_border_color, 4)
	tonnetz_tile_layer = TonnetzTileLayerScript.new()
	tonnetz_tile_layer.name = "TonnetzTileLayer"
	tonnetz_tile_layer.tonnetz_viewport = tonnetz_viewport
	tonnetz_tile_layer.builder = tonnetz_builder
	controls_panel = _create_layout_panel("ControlsPanel", config.ui_panel_color, config.ui_panel_border_color, 4)

	add_child(left_panel)
	add_child(tonnetz_panel)
	add_child(tonnetz_tile_layer)
	add_child(controls_panel)
	move_child(left_panel, 0)
	move_child(tonnetz_panel, 1)
	move_child(tonnetz_tile_layer, 2)
	move_child(tonnetz_viewport_container, 3)
	move_child(controls_panel, 4)

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
	var lsystems_height: float = top_height

	left_panel.visible = true
	controls_panel.visible = false
	controls_container.visible = false
	lsystem_content_container.visible = true

	left_panel.position = Vector2(OUTER_MARGIN, OUTER_MARGIN)
	left_panel.size = Vector2(left_width, lsystems_height)

	tonnetz_panel.position = Vector2(tonnetz_x, OUTER_MARGIN)
	tonnetz_panel.size = Vector2(tonnetz_width, top_height)
	tonnetz_tile_layer.position = tonnetz_panel.position
	tonnetz_tile_layer.size = tonnetz_panel.size
	tonnetz_tile_layer.queue_redraw()

	controls_panel.position = Vector2(OUTER_MARGIN, OUTER_MARGIN)
	controls_panel.size = Vector2.ZERO

	controls_container.position = controls_panel.position
	controls_container.size = Vector2.ZERO
	controls_container.custom_minimum_size = Vector2.ZERO

	lsystem_content_container.position = left_panel.position + Vector2(PANEL_PADDING, PANEL_PADDING)
	lsystem_content_container.size = left_panel.size - Vector2(PANEL_PADDING * 2.0, PANEL_PADDING * 2.0)
	lsystem_content_container.custom_minimum_size = lsystem_content_container.size

	tonnetz_viewport_container.position = tonnetz_panel.position
	tonnetz_viewport_container.size = tonnetz_panel.size
	tonnetz_viewport_container.custom_minimum_size = tonnetz_viewport_container.size
	if not tonnetz_viewport_container.stretch:
		tonnetz_viewport.size = Vector2i(tonnetz_viewport_container.size)

	config.start_pos = Vector2(0, 20)

	if master_bpm_panel:
		master_bpm_panel.custom_minimum_size = Vector2(lsystem_content_container.size.x, 54.0)

	if start_screen:
		start_screen.visible = start_screen_visible
		start_screen.size = canvas_size
		start_screen.position = Vector2.ZERO
		start_pattern.size = canvas_size
		start_pattern.queue_redraw()

func _on_viewport_size_changed() -> void:
	_apply_layout()

func center_tonnetz_view(builder: TonnetzBuilder) -> void:
	if not builder or builder.nodes.is_empty() or not tonnetz_viewport:
		return

	tonnetz_builder = builder
	tonnetz_tile_layer.builder = builder
	if tonnetz_tile_layer.has_method("refresh_tonnetz"):
		tonnetz_tile_layer.refresh_tonnetz()
	var bounds := _get_tonnetz_bounds(builder)

	if bounds.size == Vector2.ZERO:
		return

	tonnetz_bounds = bounds
	tonnetz_bounds_available = true
	var viewport_center := tonnetz_viewport_container.size * 0.5
	var content_center := _get_central_tonnetz_tile_center(builder)
	tonnetz_view_zoom = 1.0
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

func _get_central_tonnetz_tile_center(builder: TonnetzBuilder) -> Vector2:
	var origin_coord := builder._coord_from_row_column(0, 0)
	var right_coord := builder._coord_from_row_column(0, int(config.column_count))
	var bottom_coord := builder._coord_from_row_column(
		builder._get_wrap_row_period(),
		builder.get_row_tile_column_shift()
	)
	var origin := builder.get_coord_center(origin_coord)
	var right := builder.get_coord_center(right_coord)
	var bottom := builder.get_coord_center(bottom_coord)
	return (origin + right + bottom + right + bottom - origin) * 0.25

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

	if walk_card_visible:
		voice_list.add_child(_create_walk_lsystem_card())

	if lsystems.is_empty():
		voice_list.add_child(_create_empty_lsystem_card())
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

func _create_walk_lsystem_card() -> Control:
	var panel := PanelContainer.new()
	panel.name = "GenerateWalkCard"
	panel.custom_minimum_size = Vector2(0, 0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	var style := StyleBoxFlat.new()
	style.bg_color = config.ui_panel_color
	style.border_color = config.ui_panel_border_color
	style.set_corner_radius_all(8)
	style.set_border_width_all(3)
	style.set_content_margin(SIDE_LEFT, 16)
	style.set_content_margin(SIDE_TOP, 16)
	style.set_content_margin(SIDE_RIGHT, 16)
	style.set_content_margin(SIDE_BOTTOM, 16)
	panel.add_theme_stylebox_override("panel", style)

	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 8)
	panel.add_child(card)

	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_child(header)

	var title := Label.new()
	title.text = "Generate walk"
	title.modulate = config.ui_text_color
	title.add_theme_font_size_override("font_size", 24)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var close_button := Button.new()
	_setup_lsystem_icon_button(close_button, "res://icons/cancel.svg")
	close_button.tooltip_text = "Close walk generator"
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
	style.border_color = config.ui_muted_color
	style.set_corner_radius_all(8)
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
	title.text = "No grammar yet."
	title.add_theme_font_size_override("font_size", 20)
	card.add_child(title)

	var description := Label.new()
	description.text = "Start with a random grammar or draw a walk."
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(description)

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 8)
	action_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_child(action_row)

	var add_button := _create_generation_card_button(
		"Generate random",
		"Create a random L-system",
		"res://icons/shuffle.svg"
	)
	add_button.pressed.connect(_on_add_random_lsystem_pressed)
	action_row.add_child(add_button)

	var walk_button := _create_generation_card_button(
		"Draw a walk",
		"Show walk generation controls",
		"res://icons/play.svg"
	)
	walk_button.pressed.connect(_on_generate_walk_tile_pressed)
	action_row.add_child(walk_button)

	return panel


func _setup_lsystem_voice_list() -> void:
	var header := VBoxContainer.new()
	header.name = "LSystemHeader"
	header.add_theme_constant_override("separation", 10)
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

	var generate_cards := HBoxContainer.new()
	generate_cards.name = "GenerateCards"
	generate_cards.add_theme_constant_override("separation", 8)
	generate_cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(generate_cards)

	var add_button := _create_generation_card_button(
		"Random Grammar",
		"Create a random L-system",
		"res://icons/shuffle.svg"
	)
	add_button.pressed.connect(_on_add_random_lsystem_pressed)
	generate_cards.add_child(add_button)

	var generate_walk_button := _create_generation_card_button(
		"Generate Walk",
		"Show walk generation controls",
		"res://icons/play.svg"
	)
	generate_walk_button.pressed.connect(_on_generate_walk_tile_pressed)
	generate_cards.add_child(generate_walk_button)

	var margin := MarginContainer.new()
	margin.name = "LSystemContentMargin"
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lsystem_content_container.add_child(margin)

	voice_scroll = ScrollContainer.new()
	voice_scroll.name = "LSystemVoiceScroll"
	voice_scroll.custom_minimum_size = Vector2.ZERO
	voice_scroll.follow_focus = true
	voice_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	voice_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	voice_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	voice_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(voice_scroll)

	voice_list = VBoxContainer.new()
	voice_list.name = "LSystemVoiceList"
	voice_list.add_theme_constant_override("separation", 10)
	voice_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	voice_list.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	voice_scroll.add_child(voice_list)

func _create_generation_card_button(text: String, tooltip: String, icon_path: String) -> Button:
	var button := Button.new()
	button.text = text
	button.icon = _get_icon(icon_path)
	button.tooltip_text = tooltip
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, 52)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.add_theme_font_size_override("font_size", 14)
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

	var style := StyleBoxFlat.new()
	style.bg_color = config.ui_panel_color
	style.border_color = color
	style.set_corner_radius_all(8)
	style.set_border_width_all(3 if is_active else 1)
	style.set_content_margin(SIDE_LEFT, 0)
	style.set_content_margin(SIDE_TOP, 0)
	style.set_content_margin(SIDE_RIGHT, 0)
	style.set_content_margin(SIDE_BOTTOM, 10 if is_active else 0)
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

	var header_color := color
	var header_text_color := _get_voice_header_text_color(header_color)
	var header_style := StyleBoxFlat.new()
	header_style.bg_color = header_color
	header_style.set_corner_radius_all(6)
	header_style.set_content_margin(SIDE_LEFT, 12)
	header_style.set_content_margin(SIDE_TOP, 8)
	header_style.set_content_margin(SIDE_RIGHT, 12)
	header_style.set_content_margin(SIDE_BOTTOM, 8)
	header_panel.add_theme_stylebox_override("panel", header_style)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.mouse_filter = Control.MOUSE_FILTER_PASS
	header_panel.add_child(header)

	var accordion_icon := Label.new()
	accordion_icon.text = "▼" if is_active else "▶"
	accordion_icon.modulate = header_text_color
	accordion_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(accordion_icon)
	
########## TITLE #############
	var title := Label.new()
	title.text = "Voice %d" % int(info.get("display_number", index + 1))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fv := FontVariation.new()
	fv.base_font = load("res://fonts/Rubik-VariableFont_wght.ttf")
	fv.variation_opentype = {"weight": 700}
	title.add_theme_font_size_override("font_size", 20)
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

	var solo_button := Button.new()
	solo_button.text = "S"
	solo_button.toggle_mode = true
	solo_button.button_pressed = bool(info.get("solo", false))
	solo_button.tooltip_text = "Solo voice"
	solo_button.focus_mode = Control.FOCUS_NONE
	solo_button.custom_minimum_size = Vector2(30, 30)
	solo_button.toggled.connect(_on_voice_solo_toggled.bind(index))
	header.add_child(solo_button)

	var actions_menu := MenuButton.new()
	actions_menu.text = "⋮"
	actions_menu.tooltip_text = "Voice actions"
	actions_menu.focus_mode = Control.FOCUS_NONE
	actions_menu.custom_minimum_size = Vector2(30, 30)
	actions_menu.flat = true
	var popup := actions_menu.get_popup()
	popup.add_item("Duplicate", 0)
	popup.add_item("Randomize", 1)
	popup.add_item("Export", 2)
	popup.add_separator()
	popup.add_item("Delete", 3)
	popup.id_pressed.connect(_on_voice_action_menu_pressed.bind(index))
	header.add_child(actions_menu)

	if not is_active:
		return panel

	var body_margin := MarginContainer.new()
	body_margin.add_theme_constant_override("margin_left", 16)
	body_margin.add_theme_constant_override("margin_top", 12)
	body_margin.add_theme_constant_override("margin_right", 16)
	body_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_child(body_margin)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.mouse_filter = Control.MOUSE_FILTER_PASS
	body_margin.add_child(body)

	if info.has("fitness"):
		var fitness_value := float(info.get("fitness", INF))
		var fitness_label := Label.new()
		fitness_label.text = "Fitness: %s" % _format_voice_fitness(fitness_value)
		fitness_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_child(fitness_label)

	var playback_section := _create_voice_section("Playback")
	body.add_child(playback_section)
	_add_voice_playback_controls(playback_section, index, volume)

	body.add_child(_create_lsystem_walk_previews(index, color, info))

	var grammar_section := _create_voice_section("Grammar")
	body.add_child(grammar_section)
	
########## AXIOM #############
	var axiom_row := HBoxContainer.new()
	grammar_section.add_child(axiom_row)

	var axiom_label := Label.new()
	axiom_label.text = "Axiom"
	axiom_label.custom_minimum_size = Vector2(58, 0)
	#axiom_label.modulate = Color.BLACK
	axiom_row.add_child(axiom_label)

	var axiom_edit := LineEdit.new()
	axiom_edit.text = lsystem.axiom
	axiom_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_lsystem_line_edit_style(axiom_edit)
	axiom_edit.text_submitted.connect(_on_voice_axiom_submitted.bind(index))
	axiom_row.add_child(axiom_edit)

	var rules_header := HBoxContainer.new()
	rules_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grammar_section.add_child(rules_header)

	var symbol_header := _create_mono_label("Symbol")
	symbol_header.custom_minimum_size = Vector2(64, 0)
	rules_header.add_child(symbol_header)

	var replacement_header := _create_mono_label("Replacement")
	replacement_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rules_header.add_child(replacement_header)
	
########## PROD RULES #############
	for key in lsystem.rules:
		grammar_section.add_child(_create_rule_row(index, key, lsystem.rules[key]))

	grammar_section.add_child(_create_iterations_stepper(index, lsystem.iterations))
	grammar_section.add_child(_create_generated_string_foldout(lsystem.generated_string))

	return panel

func _create_voice_section(title_text: String) -> VBoxContainer:
	var section := VBoxContainer.new()
	section.name = title_text + "Section"
	section.add_theme_constant_override("separation", 8)
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var title := _create_label(title_text)
	title.add_theme_font_size_override("font_size", 15)
	section.add_child(title)

	var line := HSeparator.new()
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section.add_child(line)
	return section

func _add_voice_playback_controls(section: VBoxContainer, index: int, volume: float) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section.add_child(row)

	var play_button := Button.new()
	_setup_lsystem_icon_button(play_button, "res://icons/play.svg")
	play_button.tooltip_text = "Play voice"
	play_button.pressed.connect(_on_voice_resume_pressed.bind(index))
	row.add_child(play_button)

	var stop_button := Button.new()
	_setup_lsystem_icon_button(stop_button, STOP_ICON_PATH)
	stop_button.tooltip_text = "Stop voice"
	stop_button.pressed.connect(_on_voice_stop_pressed.bind(index))
	row.add_child(stop_button)

	_add_voice_volume_controls(section, index, volume)

func _create_iterations_stepper(index: int, iterations: int) -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var label := _create_label("Iterations")
	label.add_theme_font_size_override("font_size", 13)
	column.add_child(label)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(row)

	var down_button := Button.new()
	_setup_lsystem_icon_button(down_button, "res://icons/left.svg")
	down_button.tooltip_text = "Decrease iterations"
	row.add_child(down_button)

	var value := Label.new()
	value.text = str(iterations)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value.custom_minimum_size = Vector2(70, 38)
	value.add_theme_font_size_override("font_size", 20)
	row.add_child(value)

	var up_button := Button.new()
	_setup_lsystem_icon_button(up_button, "res://icons/right.svg")
	up_button.tooltip_text = "Increase iterations"
	row.add_child(up_button)

	down_button.pressed.connect(_on_voice_iterations_stepper_pressed.bind(index, value, -1))
	up_button.pressed.connect(_on_voice_iterations_stepper_pressed.bind(index, value, 1))
	return column

func _create_generated_string_foldout(generated_string: String) -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var button := Button.new()
	button.text = "▶ Generated String"
	button.toggle_mode = true
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(button)

	var generated_label := _create_mono_label(generated_string)
	generated_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	generated_label.visible = false
	generated_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(generated_label)

	button.toggled.connect(_on_generated_string_foldout_toggled.bind(button, generated_label))
	return column

func _create_mono_label(text: String) -> Label:
	var label := _create_label(text)
	label.add_theme_font_size_override("font_size", 12)
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
	column.add_theme_constant_override("separation", 6)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.mouse_filter = Control.MOUSE_FILTER_PASS

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(row)

	var left_button := Button.new()
	left_button.text = "↺"
	left_button.focus_mode = Control.FOCUS_NONE
	left_button.tooltip_text = "Rotate counterclockwise"
	left_button.pressed.connect(_on_lsystem_preview_direction_pressed.bind(index, -1))
	row.add_child(left_button)

	var preview := Control.new()
	preview.name = "DirectionPreview"
	preview.custom_minimum_size = WALK_PREVIEW_SIZE
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
	right_button.text = "↻"
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
	preview.draw_rect(rect, config.ui_muted_color, false, 1.0)
	var nodes_center := Vector2(rect.size.x * 0.32, rect.size.y * 0.5)
	var triangles_center := Vector2(rect.size.x * 0.74, rect.size.y * 0.5)
	var label_y := 14.0
	var inactive_color: Color = config.ui_muted_color
	var base_line_color: Color = inactive_color.darkened(0.18)

	preview.draw_string(
		config.font,
		Vector2(18.0, label_y),
		"Nodes",
		HORIZONTAL_ALIGNMENT_LEFT,
		72.0,
		12,
		config.ui_text_color
	)
	preview.draw_string(
		config.font,
		Vector2(rect.size.x - 84.0, label_y),
		"Triangles",
		HORIZONTAL_ALIGNMENT_LEFT,
		72.0,
		12,
		config.ui_text_color
	)

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

func _axial_to_preview_position(direction: Vector2i) -> Vector2:
	return Vector2(
		0.5 * float(direction.x - direction.y),
		0.866 * float(direction.x + direction.y)
	)

func _draw_node_direction_marker(
	preview: Control,
	center: Vector2,
	color: Color,
	base_line_color: Color,
	node_direction_index: int
) -> void:
	var active_index := posmod(node_direction_index, WALK_PREVIEW_NODE_DIRECTIONS.size())
	var node_radius := 7.0
	var marker_distance := 24.0

	for direction_index in range(WALK_PREVIEW_NODE_DIRECTIONS.size()):
		var direction: Vector2 = _axial_to_preview_position(
			WALK_PREVIEW_NODE_DIRECTIONS[direction_index]
		).normalized()
		var marker_color := color if direction_index == active_index else base_line_color
		var start := center + direction * (node_radius + 2.0)
		var end := center + direction * marker_distance
		preview.draw_line(start, end, marker_color, 2.2, true)

	preview.draw_circle(center, node_radius + 2.0, config.ui_panel_border_color, true, -1.0, true)
	preview.draw_circle(center, node_radius, config.note_color, true, -1.0, true)

func _draw_triangle_direction_marker(
	preview: Control,
	center: Vector2,
	color: Color,
	base_line_color: Color,
	triangle_edge: int
) -> void:
	var active_edge := posmod(triangle_edge, 3)
	var radius := 17.0
	var points := PackedVector2Array()

	for point_index in range(3):
		var angle := -PI / 2.0 + float(point_index) * TAU / 3.0
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)

	preview.draw_colored_polygon(points, config.note_color)

	for edge_index in range(3):
		var from_point := points[edge_index]
		var to_point := points[(edge_index + 1) % 3]
		var edge_color := color if edge_index == active_edge else base_line_color
		var edge_width := 3.2 if edge_index == active_edge else 2.0
		preview.draw_line(from_point, to_point, edge_color, edge_width, true)


func _setup_lsystem_icon_button(button: Button, icon_path: String) -> void:
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.icon = _get_icon(icon_path)

func _apply_lsystem_line_edit_style(line_edit: LineEdit) -> void:
	var normal_style := _create_lsystem_line_edit_style(
		config.ui_input_color,
		config.ui_muted_color,
		1
	)
	var focus_style := _create_lsystem_line_edit_style(
		config.ui_input_focus_color,
		config.ui_panel_border_color,
		2
	)

	line_edit.add_theme_stylebox_override("normal", normal_style)
	line_edit.add_theme_stylebox_override("focus", focus_style)
	line_edit.add_theme_color_override("font_color", config.ui_text_color)
	line_edit.add_theme_color_override("caret_color", config.ui_text_color)
	line_edit.add_theme_color_override("selection_color", config.ui_selection_color)

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
	return color.lerp(config.ui_muted_color, 0.62)

func _get_voice_header_text_color(color: Color) -> Color:
	var luminance := color.r * 0.299 + color.g * 0.587 + color.b * 0.114
	return config.ui_text_color if luminance > 0.62 else config.ui_panel_color


func _update_voice_mute_button(button: Button, muted: bool) -> void:
	button.icon = _get_icon(MUTED_ICON_PATH if muted else UNMUTED_ICON_PATH)
	button.modulate = config.ui_muted_color if muted else config.ui_panel_color
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
	volume_row.add_theme_constant_override("separation", 4)
	card.add_child(volume_row)

	var volume_label := Label.new()
	volume_label.text = "Volume"
	volume_label.add_theme_font_size_override("font_size", 13)
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
	input_row.add_theme_constant_override("separation", 6)
	input_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(input_row)

	var symbol_label := _create_mono_label(symbol)
	symbol_label.custom_minimum_size = Vector2(24, 30)
	symbol_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	input_row.add_child(symbol_label)

	var arrow_label := _create_mono_label("→")
	arrow_label.custom_minimum_size = Vector2(22, 30)
	arrow_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	input_row.add_child(arrow_label)

	var production_edit := LineEdit.new()
	production_edit.text = production
	production_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_lsystem_line_edit_style(production_edit)
	production_edit.add_theme_font_override("font", config.font)
	production_edit.add_theme_font_size_override("font_size", 12)
	input_row.add_child(production_edit)

	var warning := Label.new()
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


func _on_voice_active_toggled(_enabled: bool, index: int) -> void:
	lsystem_selected.emit(index)


func _on_voice_randomize_pressed(index: int) -> void:
	lsystem_randomize_requested.emit(index)

func _on_voice_duplicate_pressed(index: int) -> void:
	lsystem_duplicate_requested.emit(index)

func _on_voice_stop_pressed(index: int) -> void:
	lsystem_stop_requested.emit(index)

func _on_voice_resume_pressed(index: int) -> void:
	lsystem_resume_requested.emit(index)

func _on_voice_solo_toggled(solo: bool, index: int) -> void:
	lsystem_solo_toggled.emit(index, solo)

func _on_voice_action_menu_pressed(action_id: int, index: int) -> void:
	match action_id:
		0:
			_on_voice_duplicate_pressed(index)
		1:
			_on_voice_randomize_pressed(index)
		2:
			_on_voice_export_midi_pressed(index)
		3:
			_on_voice_remove_pressed(index)

func _on_voice_export_midi_pressed(index: int) -> void:
	if not export_midi_dialog:
		return

	export_midi_voice_index = index
	export_midi_dialog.current_file = _build_default_voice_midi_filename(index)
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

func _on_voice_iterations_stepper_pressed(index: int, iterations_value: Label, delta: int) -> void:
	var iterations := int(clamp(
		int(iterations_value.text) + delta,
		0,
		10
	))
	iterations_value.text = str(iterations)
	lsystem_iterations_changed.emit(index, iterations)

func _on_generated_string_foldout_toggled(
	expanded: bool,
	button: Button,
	generated_label: Label
) -> void:
	button.text = "▼ Generated String" if expanded else "▶ Generated String"
	generated_label.visible = expanded

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
	walk_recording_started.emit()

func _on_walk_undo_pressed() -> void:
	walk_recording_undo_requested.emit()

func _on_walk_generate_pressed() -> void:
	if walk_record_button:
		walk_record_button.button_pressed = false
	walk_lsystem_generate_requested.emit()

func _on_walk_regenerate_pressed() -> void:
	walk_lsystem_regenerate_requested.emit()

func _on_walk_cancel_pressed() -> void:
	if walk_record_button:
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
	var title := _create_label("Playback")
	var fv := FontVariation.new()
	fv.base_font = load("res://fonts/Rubik-VariableFont_wght.ttf")
	fv.variation_opentype = {"weight": 700}
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_font_override("font", fv)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls_container.add_child(title)

	var playback_row := HBoxContainer.new()
	playback_row.add_theme_constant_override("separation", 8)
	playback_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls_container.add_child(playback_row)

	global_play_pause_button = Button.new()
	global_play_pause_button.name = "GlobalPlayPauseButton"
	global_play_pause_button.text = "Play all"
	global_play_pause_button.icon = _get_icon("res://icons/play.svg")
	global_play_pause_button.tooltip_text = "Play all voices"
	global_play_pause_button.focus_mode = Control.FOCUS_NONE
	global_play_pause_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	global_play_pause_button.pressed.connect(_on_global_play_pause_pressed)
	playback_row.add_child(global_play_pause_button)

	stop_all_button = Button.new()
	stop_all_button.name = "StopAllButton"
	stop_all_button.text = "Stop all"
	stop_all_button.icon = _get_icon(STOP_ICON_PATH)
	stop_all_button.tooltip_text = "Stop all voices"
	stop_all_button.focus_mode = Control.FOCUS_NONE
	stop_all_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stop_all_button.pressed.connect(_on_stop_all_pressed)
	playback_row.add_child(stop_all_button)

	var separator := HSeparator.new()
	separator.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls_container.add_child(separator)

	export_midi_button = Button.new()
	export_midi_button.name = "ExportMidiButton"
	export_midi_button.text = "Export all"
	export_midi_button.tooltip_text = "Export all voices as MIDI"
	export_midi_button.focus_mode = Control.FOCUS_NONE
	export_midi_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	export_midi_button.mouse_filter = Control.MOUSE_FILTER_STOP
	export_midi_button.pressed.connect(_on_export_midi_pressed)
	export_midi_button.visible = false


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
	lsystem_content_container.add_child(master_bpm_panel)

	var bpm_row := HBoxContainer.new()
	bpm_row.name = "BPMRow"
	bpm_row.add_theme_constant_override("separation", 4)
	bpm_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	master_bpm_panel.add_child(bpm_row)

	var title := _create_label("Tempo")
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bpm_row.add_child(title)

	bpm_value_label = _create_label("120 BPM")
	bpm_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bpm_value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bpm_value_label.custom_minimum_size = Vector2(70, 0)
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
	panel_style.bg_color = Color(config.ui_panel_color, 0.76)
	panel_style.set_border_width_all(0)
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
	title.text = "Interaktive Musikgenerierung mit Tonnetz-basierten\nLindenmayer-Systemen"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 28)
	var title_font := FontVariation.new()
	title_font.base_font = load("res://fonts/Rubik-VariableFont_wght.ttf")
	title_font.variation_opentype = {"weight": 760}
	title.add_theme_font_override("font", title_font)
	content.add_child(title)

	start_button = Button.new()
	start_button.name = "StartButton"
	start_button.text = "Start"
	start_button.custom_minimum_size = Vector2(180, 52)
	start_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	start_button.focus_mode = Control.FOCUS_NONE
	start_button.pressed.connect(_on_start_button_pressed)
	content.add_child(start_button)


func _draw_start_pattern() -> void:
	var rect := Rect2(Vector2.ZERO, start_pattern.size)
	start_pattern.draw_rect(rect, config.tonnetz_background_color, true)

	var start_center := rect.get_center()
	var anchor_coord := _coord_from_start_row_column(2, 4)
	var tile_origin := start_center - _get_start_coord_center(anchor_coord, Vector2.ZERO)
	var row_start := -3
	var row_end := int(rect.size.y / (config.offset * 0.866)) + 7
	var column_start := -5
	var column_end := int(rect.size.x / config.offset) + 8
	var line_color: Color = config.line_color
	line_color.a = 0.82
	var node_border_color: Color = config.note_border_color
	node_border_color.a = 0.9
	var node_fill_color: Color = config.note_color
	node_fill_color.a = 0.92
	var label_color: Color = config.note_label_color
	label_color.a = 0.82

	for row in range(row_start, row_end):
		for column in range(column_start, column_end):
			var coord := _coord_from_start_row_column(row, column)
			var center := _get_start_coord_center(coord, tile_origin)
			_draw_start_tonnetz_line(center, _coord_from_start_row_column(row, column + 1), tile_origin, line_color)
			_draw_start_tonnetz_line(center, coord + Vector2i(-1, 0), tile_origin, line_color)
			_draw_start_tonnetz_line(center, coord + Vector2i(0, -1), tile_origin, line_color)

	for row in range(row_start, row_end):
		for column in range(column_start, column_end):
			var center := _get_start_coord_center(
				_coord_from_start_row_column(row, column),
				tile_origin
			)
			start_pattern.draw_circle(center, config.note_radius + config.outline_width + 1.0, node_border_color, true, -1.0, true)
			start_pattern.draw_circle(center, config.note_radius, node_fill_color, true, -1.0, true)
			start_pattern.draw_string(
				config.font,
				center + Vector2(-config.note_radius, 5.0),
				_get_start_note_name(row, column),
				HORIZONTAL_ALIGNMENT_CENTER,
				config.note_radius * 2.0,
				13,
				label_color
			)

func _draw_start_tonnetz_line(
	center: Vector2,
	to_coord: Vector2i,
	tile_origin: Vector2,
	color: Color
) -> void:
	var to_center := _get_start_coord_center(to_coord, tile_origin)
	var unit := (to_center - center).normalized()
	var radius_offset: Vector2 = unit * config.note_radius
	start_pattern.draw_line(center + radius_offset, to_center - radius_offset, color, config.line_width, true)

func _get_start_note_name(row: int, column: int) -> String:
	var coord := _coord_from_start_row_column(row, column)
	var pitch: int = config.base_midi_note + coord.x * 3 - coord.y * 4
	return config.NOTE_NAMES[posmod(pitch, 12)]

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
	global_play_pause_button.text = "Play all" if global_paused else "Pause all"
	global_play_pause_button.tooltip_text = "Play all voices" if global_paused else "Pause all voices"

func _on_bpm_value_changed(new_value: float) -> void:
	bpm_value_label.text = "%d BPM" % int(new_value)

func _on_bpm_step_pressed(delta: int) -> void:
	var new_value := int(clamp(
		bpm_slider.value + delta,
		bpm_slider.min_value,
		bpm_slider.max_value
	))
	bpm_slider.value = new_value
	config.bpm = new_value
	bpm_value_label.text = "%d BPM" % new_value

func on_bpm_changed(ended: bool) -> void:
	if not ended:
		return
	var new_value := int(bpm_slider.value)
	config.bpm = new_value
	bpm_value_label.text = "%d BPM" % new_value
