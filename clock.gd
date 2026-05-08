extends Node
class_name Clock

var bpm : int = 120
var time_sec := 0.0 #timer general
var time_beat := 0.0 #number of beats that have passed since beginning
var progress : float
var is_playing := true

func _ready() -> void:
	pass

func _process(delta: float) -> void:
	if is_playing:
		time_sec += delta
		#beats per second* passed seconds
		time_beat = time_sec * (bpm / 60.0)

func get_beats_per_second():
	return CL.bpm / 60.0
	
func get_time_beat():
	return time_beat
	
func get_progress() -> float:
	return time_beat - floor(time_beat)

func get_current_beat() -> int:
	return floor(time_beat)

func stop_clock():
	is_playing = false
	
func start_clock(): 
	is_playing = true
