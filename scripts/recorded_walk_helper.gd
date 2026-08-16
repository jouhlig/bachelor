class_name RecordedWalkHelper
extends RefCounted

# This class handles recorded walks and the start of generation.

const RECORDED_WALK_CLICK_SOUND_DURATION := 0.25

var walk_recorder: WalkRecorder
var lsystem_list
var audio_manager: AudioManager
var pending_score: Array = []
var pending_origin = null
var pending_color: Color = Color.WHITE
var reference_score: Array = []
var reference_origin = null
var reference_color: Color = Color.WHITE
var next_click_voice_id := -1000

func _init(
	new_walk_recorder: WalkRecorder,
	new_lsystem_list,
	new_audio_manager: AudioManager
) -> void:
	walk_recorder = new_walk_recorder
	lsystem_list = new_lsystem_list
	audio_manager = new_audio_manager

func is_recording() -> bool:
	return walk_recorder.is_recording()

func start_recording() -> void:
	if walk_recorder.is_recording():
		lsystem_list.return_color(walk_recorder.get_color())

	clear_reference()

	if not pending_score.is_empty():
		lsystem_list.return_color(pending_color)
		clear_pending()

	walk_recorder.start(lsystem_list.get_next_color())

func cancel_recording() -> void:
	lsystem_list.return_color(walk_recorder.get_color())
	walk_recorder.cancel()

func set_duration(duration_beats: float) -> void:
	walk_recorder.set_duration(duration_beats)

func undo_step() -> void:
	walk_recorder.undo_step()

func finish_recording() -> void:
	if not walk_recorder.is_recording():
		return

	if not walk_recorder.has_recorded_step():
		cancel_recording()
		return

	var score: Array = walk_recorder.build_score()

	if not has_recorded_step(score):
		cancel_recording()
		return

	pending_score = score
	pending_origin = walk_recorder.get_origin()
	pending_color = walk_recorder.get_color()

	walk_recorder.finish()

	print("Recorded walk ready for L-system generation.")

func get_generation_source() -> Dictionary:
	var source_score := pending_score
	var source_origin = pending_origin
	var source_color := pending_color

	if not has_recorded_step(source_score):
		source_score = reference_score
		source_origin = reference_origin
		source_color = reference_color

	if not has_recorded_step(source_score):
		return {
			"ok": false,
			"message": "Record a walk before generating an L-system."
		}

	if source_origin == null:
		return {
			"ok": false,
			"message": "The recorded walk has no origin."
		}

	return {
		"ok": true,
		"score": source_score.duplicate(true),
		"origin": source_origin,
		"color": source_color
	}

func store_reference(score: Array, origin, color: Color) -> void:
	clear_reference()
	reference_score = score.duplicate(true)
	reference_origin = origin
	reference_color = color

func clear_pending() -> void:
	pending_score.clear()
	pending_origin = null
	pending_color = Color.WHITE

func clear_reference() -> void:
	reference_score.clear()
	reference_origin = null
	reference_color = Color.WHITE

func handle_click(click_pos: Vector2) -> void:
	var recorded_anchor = walk_recorder.handle_click(click_pos)

	if recorded_anchor:
		_play_click_sound(recorded_anchor)

func has_recorded_step(score: Array) -> bool:
	if score.size() < 2:
		return false

	var first_anchor = score[0].get("anchor")
	var second_anchor = score[1].get("anchor")
	return first_anchor != null and second_anchor != null and first_anchor != second_anchor

func _play_click_sound(anchor) -> void:
	var voice_id := next_click_voice_id
	next_click_voice_id -= 1

	if anchor is TonnetzTriangle:
		audio_manager.play_notes(
			anchor.nodes,
			0.8,
			RECORDED_WALK_CLICK_SOUND_DURATION,
			voice_id
		)
	elif anchor is TonnetzNode:
		audio_manager.play_notes(
			[anchor],
			0.8,
			RECORDED_WALK_CLICK_SOUND_DURATION,
			voice_id
		)
