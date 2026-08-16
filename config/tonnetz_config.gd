extends Resource
class_name TonnetzConfig

# This resource keeps all Tonnetz, UI, and gameplay values in one place.

const NOTE_NAMES := ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

@export_group("font")
@export var font = load("res://fonts/IBM_Plex_Mono,Inter_Tight/IBM_Plex_Mono/IBMPlexMono-Regular.ttf")

@export_group("tonnetz grid")
@export var column_count: int = 12
@export var row_count: int = 10
# pixel origin for axial coordinate (0, 0) inside the tonnetz viewport
@export var start_pos: Vector2 = Vector2(0, 20)
# pixel spacing between tonnetz nodes.
@export var offset: int = 100

@export_group("tonnetz pitch mapping")
# MIDI note used at axial coordinate (0, 0). 24 is C2.
@export var base_midi_note: int = 24

@export_group("tonnetz drawing")
@export var note_color: Color = Color.WHITE
@export var note_label_color: Color = Color("#14150fff")
@export var note_border_color: Color = Color("#14150fff")
@export var note_radius: float = 14
@export var node_note_font_size: int = 13
@export var node_octave_font_size: int = 9
# radius for the border of the nodes
@export var outline_width: float = 1.0
@export var line_color: Color = Color("#14150fff")
#lines between the nodes
@export var line_width: float = 0.75
# shrink triangles away from the notes
@export_range(0.5, 1.0, 0.01)
var triangle_scale: float = 0.72  

@export_group("ui")
@export var ui_panel_color: Color = Color.WHITE
@export var ui_panel_border_color: Color = Color("#14150fff")
@export var ui_panel_border_width: int = 2
@export var ui_text_color: Color = Color("#14150fff")
@export var ui_muted_color: Color = Color("#7e98b466")
@export var ui_input_color: Color = Color.WHITE
@export var ui_input_focus_color: Color = Color("#f5ef51ff")
# Semi-transparent selection fill for text inputs and selected UI states.
@export var ui_selection_color: Color = Color("#7e98b466")
@export var tonnetz_background_color: Color = Color.WHITE
@export var tonnetz_border_color: Color = Color("#14150fff")

@export_group("ui layout")
@export var outer_margin: float = 14.0
# inner padding used by the layout panels
@export var panel_padding: float = 16.0
# horizontal gap between the left controls and the Tonnetz panel.
@export var panel_gap: float = 14.0
# Fixed width of the left L-system/control column.
@export var left_panel_width: float = 480.0
# Fixed height for the three right-side control boxes below the Tonnetz.
@export var right_controls_height: float = 135.0
# Reserved height for the Tonnetz panel title above the viewport.
@export var tonnetz_title_height: float = 36.0
@export var tonnetz_view_zoom: float = 1.0
# Size of the small node/triangle direction preview in each L-system card.
@export var walk_preview_size: Vector2 = Vector2(252.0, 82.0)
# Vertical distance between the main topics inside an expanded L-system card,
# for example volume, direction preview, and grammar.
@export var lsystem_section_gap: float = 42.0

@export_group("turtle")
@export var trail_width: float = 6.0
# Size of the small direction arrow drawn at the current turtle position.
@export var turtle_arrow_length: float = 14.0
@export var turtle_arrow_width: float = 14.0
# Distance the turtle travels past the Tonnetz edge before it fades out and
# reappears before the wrapped target position.
@export var turtle_wrap_visual_distance: float = 28.0
# Fraction of each wrap segment used for fading at the beginning and end.
@export var turtle_wrap_fade_fraction: float = 0.08
# Maximum trail length measured in Tonnetz steps, not raw pixels.
@export var turtle_trail_max_steps: int = 6
# Maximum trail distance removed per prune tick. This avoids visible jumps when
# the trail length slider is moved to a much shorter value.
@export var turtle_trail_prune_max_step_fraction: float = 0.18
# Interval for pruning old trail points while playback is running.
@export var turtle_trail_prune_update_interval: float = 0.1
# Voice colors sampled from the UI reference image.
@export var VOICE_COLORS : Array[Color]= [
	Color("#1460D8"),
	Color("#FF5622"),
	Color("#FAF446"),
	Color("#FA8AD3"),
	Color("#E43746"),
	Color("#ABC7E4"),
	Color("#7E98B4"),
	Color("#BEC142"),
	Color("#65663D"),
	Color("#FF922C"),
	Color("#F1C7E2")
]

@export_group("walk recorder")
# Drawing order for the temporary walk path and next-step hints.
@export var walk_preview_line_z_index: int = 1
@export var walk_highlight_z_index: int = 50
# Width of the temporary line that shows the recorded walk while recording.
@export var walk_preview_line_width: float = 4.0
# Ignore accidental ultra-short recorded steps below this duration in beats.
@export var recorded_walk_min_step_duration: float = 0.05
# Random target walk lengths are sampled from this clamped normal distribution.
@export var random_walk_min_length: int = 5
@export var random_walk_max_length: int = 20
@export var random_walk_mean_length: float = 12.5
@export var random_walk_length_deviation: float = 3.5
@export var random_walk_durations: Array[float] = [0.5, 1.0, 2.0, 4.0]

@export_group("interaction")
# Click radius for triangle anchors, relative to the Tonnetz node spacing.
@export var anchor_click_radius_factor: float = 0.45
# Click radius for note nodes, relative to note_radius.
@export var node_click_radius_multiplier: float = 2.0
	
