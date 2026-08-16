extends Control
class_name TutorialOverlay

# shows the tutorial hints and callouts.

const HIGHLIGHT_COLOR := Color("#FF5622")
const LAST_PAGE := 3
const overlay_box_width := 480

var config: TonnetzConfig = Config.config
var left_panel: Control
var tonnetz_panel: Control
var controls_panel: Control
var voice_card: Control
var playback_panel: Control
var tempo_panel: Control
var export_panel: Control
var page := 0

var drawing_layer: Control
var body: Control
var back_button: Button
var next_button: Button

##################################################
########## PUBLIC API #############
##################################################
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 500
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)

	var input_blocker := ColorRect.new()
	input_blocker.name = "TutorialInputBlocker"
	input_blocker.color = Color.TRANSPARENT
	input_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	input_blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(input_blocker)

	drawing_layer = Control.new()
	drawing_layer.name = "TutorialDrawing"
	drawing_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drawing_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	drawing_layer.draw.connect(_draw_tutorial)
	add_child(drawing_layer)

	body = Control.new()
	body.name = "TutorialBody"
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(body)

func set_targets(
	new_left_panel: Control,
	new_tonnetz_panel: Control,
	new_controls_panel: Control,
	extra_targets: Dictionary = {}
) -> void:
	left_panel = new_left_panel
	tonnetz_panel = new_tonnetz_panel
	controls_panel = new_controls_panel
	voice_card = extra_targets.get("voice_card")
	playback_panel = extra_targets.get("playback_panel")
	tempo_panel = extra_targets.get("tempo_panel")
	export_panel = extra_targets.get("export_panel")
	_render_page()

func start_tutorial() -> void:
	page = 0
	show()
	_render_page()

func hide_tutorial() -> void:
	hide()

func refresh() -> void:
	if drawing_layer:
		drawing_layer.queue_redraw()

##################################################
########## PAGE CONTENT #############
##################################################
func _render_page() -> void:
	if not body:
		return

	for child in body.get_children():
		child.queue_free()

	if not left_panel or not tonnetz_panel or not controls_panel:
		return

	if page == 0:
		_build_tonnetz_page()
	elif page == 1:
		_build_voice_card_page()
	elif page == 2:
		_build_global_controls_page()
	else:
		_build_tonnetz_playback_page()

	if back_button:
		back_button.disabled = page == 0
	if next_button:
		next_button.text = "Let's go" if page == LAST_PAGE else "Next"

	refresh()

func _build_tonnetz_page() -> void:
	var text := "The Tonnetz arranges notes by harmonic distance. Neighboring nodes are connected by fifths, major thirds, and minor thirds. Upward triangles form major chords; downward triangles form minor chords. A turtle moves through this grid and turns the path into music."
	var content := _add_note(
		"The Tonnetz",
		text,
		_get_note_rect(tonnetz_panel.position + Vector2(70, 70), text, 74.0),
		false
	)
	_add_interval_legend(content)
	_add_navigation(content)

func _build_voice_card_page() -> void:
	var text := "A voice card contains one L-system. The axiom is the starting string. Rules replace symbols. Iterations define how often rewriting is applied. The generated string is the final instruction sequence. The buttons duplicate, randomize, delete, or export this voice."
	_add_note(
		"Voice Card",
		text,
		_get_note_rect(left_panel.position + Vector2(left_panel.size.x + 62, 100), text)
	)

func _build_tonnetz_playback_page() -> void:
	var text := "Place an L-system into the Tonnetz to start a voice. You can choose either a node or a triangle as the starting point. The voice follows its generated path and plays the corresponding pitches."
	_add_note(
		"Into The Tonnetz",
		text,
		_get_note_rect(left_panel.position + Vector2(left_panel.size.x + 62, 360), text)
	)

func _build_global_controls_page() -> void:
	var text := "Playback controls global volume and mute. Tempo changes the shared clock. Export saves MIDI or L-system JSON files for the full composition."
	_add_note(
		"Global Controls",
		text,
		_get_note_rect(controls_panel.position + Vector2(controls_panel.size.x/2, -265), text)
	)

func _get_note_rect(position: Vector2, text: String, extra_height: float = 0.0) -> Rect2:
	return Rect2(position, Vector2(overlay_box_width, _get_note_height(text) + extra_height))

func _get_note_height(text: String) -> float:
	var usable_width: float = overlay_box_width - 48.0
	var average_character_width: float = 8.0
	var characters_per_line: int = max(1, int(usable_width / average_character_width))
	var line_count: int = ceili(float(text.length()) / float(characters_per_line))
	return max(190.0, 128.0 + float(line_count) * 23.0)

##################################################
########## CALLOUT BOXES #############
##################################################
func _add_note(
	title_text: String,
	text: String,
	rect: Rect2,
	add_navigation: bool = true
) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.custom_minimum_size = rect.size
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", _create_style(
		config.ui_panel_color,
		HIGHLIGHT_COLOR,
		config.ui_panel_border_width,
		24,
		18
	))
	body.add_child(panel)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(content)

	var title := _create_label(title_text, 22)
	content.add_child(title)

	var label := _create_label(text, 14)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(label)

	if add_navigation:
		_add_navigation(content)
	return content

func _add_interval_legend(content: VBoxContainer) -> void:
	var legend := VBoxContainer.new()
	legend.add_theme_constant_override("separation", 4)
	content.add_child(legend)

	for entry in ["→ perfect fifth", "↗ major third", "↘ minor third"]:
		var label := _create_label(entry, 14)
		label.modulate = HIGHLIGHT_COLOR
		legend.add_child(label)

func _add_navigation(content: VBoxContainer) -> void:
	var navigation := HBoxContainer.new()
	navigation.add_theme_constant_override("separation", 10)
	navigation.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(navigation)

	back_button = Button.new()
	back_button.text = "Back"
	_apply_button_style(back_button)
	back_button.custom_minimum_size = Vector2(120, 36)
	back_button.focus_mode = Control.FOCUS_NONE
	back_button.pressed.connect(_on_back_pressed)
	navigation.add_child(back_button)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	navigation.add_child(spacer)

	next_button = Button.new()
	next_button.text = "Let's go" if page == LAST_PAGE else "Next"
	_apply_button_style(next_button)
	next_button.custom_minimum_size = Vector2(120, 36)
	next_button.focus_mode = Control.FOCUS_NONE
	next_button.pressed.connect(_on_next_pressed)
	navigation.add_child(next_button)

##################################################
########## HIGHLIGHTS AND ARROWS #############
##################################################
func _draw_tutorial() -> void:
	if not left_panel or not tonnetz_panel or not controls_panel:
		return

	if page == 0:
		_draw_highlight(Rect2(tonnetz_panel.position, tonnetz_panel.size))
	elif page == 1:
		_draw_control_highlight(voice_card)
	elif page == 2:
		_draw_control_highlight(playback_panel)
		_draw_control_highlight(tempo_panel)
		_draw_control_highlight(export_panel)
	else:
		_draw_highlight(Rect2(tonnetz_panel.position, tonnetz_panel.size))

func _draw_highlight(rect: Rect2) -> void:
	drawing_layer.draw_rect(
		rect.grow(-4.0),
		HIGHLIGHT_COLOR,
		false,
		float(config.ui_panel_border_width)
	)

func _draw_control_highlight(control: Control) -> void:
	if not is_instance_valid(control):
		return

	_draw_highlight(Rect2(control.global_position - global_position, control.size))

##################################################
########## NAVIGATION #############
##################################################
func _on_back_pressed() -> void:
	page = max(0, page - 1)
	_render_page()

func _on_next_pressed() -> void:
	if page >= LAST_PAGE:
		hide_tutorial()
		return

	page += 1
	_render_page()

##################################################
########## STYLING HELPERS #############
##################################################
func _create_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.modulate = config.ui_text_color
	label.add_theme_font_override("font", config.font)
	label.add_theme_font_size_override("font_size", font_size)
	return label

func _apply_button_style(button: Control) -> void:
	button.add_theme_font_override("font", config.font)
	button.add_theme_stylebox_override("normal", _create_style(
		config.ui_panel_color,
		config.ui_panel_border_color,
		1,
		10,
		5
	))
	button.add_theme_stylebox_override("hover", _create_style(
		Color(0.94, 0.94, 0.94, 1.0),
		config.ui_panel_border_color,
		1,
		10,
		5
	))
	button.add_theme_stylebox_override("pressed", _create_style(
		Color(0.88, 0.88, 0.88, 1.0),
		config.ui_panel_border_color,
		1,
		10,
		5
	))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", config.ui_text_color)
	button.add_theme_color_override("font_hover_color", config.ui_text_color)
	button.add_theme_color_override("font_pressed_color", config.ui_text_color)

func _create_style(
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
