class_name Individual
extends RefCounted

var lsystem: LSystem
var fitness: float = INF
var fitness_penalty: float = INF
var initial_dir: Vector2i = Vector2i(1, 0)
var initial_edge: int = 0

func _init(
	new_lsystem: LSystem,
	new_fitness: float,
	new_initial_dir: Vector2i,
	new_initial_edge: int
) -> void:
	lsystem = new_lsystem
	fitness = new_fitness
	initial_dir = new_initial_dir
	initial_edge = new_initial_edge

func copy():
	var copied_lsystem: LSystem = null

	if lsystem != null:
		copied_lsystem = lsystem.duplicate_system()

	var copied_individual = get_script().new(copied_lsystem, fitness, initial_dir, initial_edge)
	copied_individual.fitness_penalty = fitness_penalty
	return copied_individual
