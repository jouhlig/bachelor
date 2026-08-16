extends Node
class_name Clock

# keeps the time and helps beats

var time_sec := 0.0 #timer general
var time_beat := 0.0 #number of beats that have passed since beginning
@export var bpm: int = 120
var progress : float
var is_playing := false

func _ready() -> void:
	pass

func _process(delta: float) -> void:
	if is_playing:
		time_sec += delta
		time_beat += delta * get_beats_per_second()

func get_beats_per_second() -> float:
	return float(bpm) / 60.0
	
func get_time_beat():
	return time_beat
	
func get_progress() -> float:
	return time_beat - floor(time_beat)

func get_current_beat() -> int:
	return floor(time_beat)

func seek_to_beat(beat: float) -> void:
	time_beat = max(0.0, beat)
	time_sec = time_beat / get_beats_per_second()

func stop_clock():
	is_playing = false
	
func start_clock(): 
	is_playing = true
