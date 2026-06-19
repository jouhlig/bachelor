extends Node
class_name NoteValueCalculator

const FALLBACK_NOTE_NAMES := ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

var note_aliases := {
	"Db": {"pitch": 1, "octave_offset": 0},
	"Eb": {"pitch": 3, "octave_offset": 0},
	"E#": {"pitch": 5, "octave_offset": 0},
	"Fb": {"pitch": 4, "octave_offset": 0},
	"Gb": {"pitch": 6, "octave_offset": 0},
	"Ab": {"pitch": 8, "octave_offset": 0},
	"Bb": {"pitch": 10, "octave_offset": 0},
	"B#": {"pitch": 0, "octave_offset": 1},
	"Cb": {"pitch": 11, "octave_offset": -1}
}

# Return the number value of a note from its name and octave (where C0 is 0)
func get_note_value(tone: String, octave: int = 4) -> int:
	var note_names := get_note_names()
	var canonical_index := note_names.find(tone)

	if canonical_index != -1:
		return canonical_index + 12 * octave

	if not note_aliases.has(tone):
		push_error("'" + str(tone) + "' is not a valid note!")
		return 0

	var alias: Dictionary = note_aliases[tone]
	return int(alias["pitch"]) + 12 * (octave + int(alias.get("octave_offset", 0)))

# Return the name of a note from its value
func get_note_name(value: int) -> String:
	return get_note_names()[posmod(value, 12)]

# Return the octave of a note from its value
func get_note_octave(value: int) -> int:
	return floori(float(value) / 12.0)

func get_note_names() -> Array:
	if Config and Config.config:
		return Config.config.NOTE_NAMES

	return FALLBACK_NOTE_NAMES
