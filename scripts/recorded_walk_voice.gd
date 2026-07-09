class_name RecordedWalkVoice

var score: Array = []
var color: Color = Color.WHITE
var volume: float = 0.8
var origin = null
var origin_label: String = "Not set"
var anchor_mode: String = ""
var playback_mode: String = "explore"

func _init(
	new_score: Array = [],
	new_origin = null,
	new_anchor_mode: String = ""
):
	score = new_score.duplicate(true)
	origin = new_origin
	anchor_mode = new_anchor_mode

func duplicate_system() -> RecordedWalkVoice:
	var duplicate = RecordedWalkVoice.new(score, origin, anchor_mode)
	duplicate.color = color
	duplicate.volume = volume
	duplicate.origin_label = origin_label
	duplicate.playback_mode = playback_mode
	return duplicate

func set_volume(new_volume: float) -> void:
	volume = clamp(new_volume, 0.0, 1.0)

func set_playback_mode(new_mode: String) -> void:
	if new_mode != "local" and new_mode != "explore":
		return

	playback_mode = new_mode

func set_origin(new_origin, new_origin_label: String) -> void:
	origin = new_origin
	origin_label = new_origin_label

func get_step_count() -> int:
	return max(0, score.size() - 1)

func get_info() -> Dictionary:
	return {
		"voice_type": "recorded_walk",
		"origin": origin,
		"origin_label": origin_label,
		"step_count": get_step_count(),
		"anchor_mode": anchor_mode,
		"playback_mode": playback_mode
	}
