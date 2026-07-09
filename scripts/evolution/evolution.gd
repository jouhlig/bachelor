extends RefCounted

const RecombinationScript = preload("res://scripts/evolution/recombination.gd")
const InitialPopulationScript = preload("res://scripts/evolution/initial_population.gd")
const MutationScript = preload("res://scripts/evolution/mutation.gd")
const TournamentSelectionScript = preload("res://scripts/evolution/selection/tournament_selection.gd")
const IndexAlignedComparisonScript = preload("res://scripts/evolution/comparison/index_aligned_comparison.gd")
const TonnetzMovementDistanceScript = preload("res://scripts/evolution/distance/tonnetz_movement_distance.gd")
const TonnetzConfigResource = preload("res://config/config.tres")

#stay the same for every config, only params change
static var recombination_fn: Callable = RecombinationScript.recombine
static var mutation_fn: Callable = MutationScript.mutate

const INTERPRETER_PATH := "Game/Interpreter"

# Number of individuals that survive into the next generation.
const MU := 100
# Number of children created during each generation step.
const LAMBDA := 100
const GENERATIONS := 20
const CROSSOVER_RATE := 0.3
const MUTATION_RATE := 0.5
const TOURNAMENT_SIZE := 3
const FITNESS_WEIGHTS := {
	"distance_weight": 20.0,
	"duration_weight": 0.0,
	"total_duration_weight": 200.0,
	"missing_event_weight": 20.0,
	"extra_event_weight": 20.0,
	"anchor_match_weight": 0.0,
	"pitch_match_weight": 0.0,
	"event_match_weight": 0.0
}
const SURVIVAL_MU_PLUS_LAMBDA := "mu_plus_lambda"
const SURVIVAL_MU_COMMA_LAMBDA := "mu_comma_lambda"

static func generate_lsystem_from_recording(
	recorded_score: Array,
	origin,
	scene_tree: SceneTree,
	parent_selection_fn: Callable = TournamentSelectionScript.select, #might be changed
	survival_type: String = SURVIVAL_MU_PLUS_LAMBDA, #might be changed
	distance_fn: Callable = TonnetzMovementDistanceScript.get_distance #might be changed
) -> Dictionary:
	var config := create_default_config()
	config["target_score"] = recorded_score
	config["target_origin"] = origin
	config["interpreter"] = scene_tree.root.get_node_or_null(INTERPRETER_PATH) 
	config["survival_type"] = survival_type
	config["distance_fn"] = distance_fn

	var population: Array = InitialPopulationScript.create_initial(config)

	for _generation in range(config["generations"]):
		population = generation_step(
			population,
			config,
			parent_selection_fn
		)

		await _wait_one_frame(scene_tree)
		var generation_best = population[0]
		#stop the evolution if the best score is equal to 0.0
		if generation_best.fitness == 0.0:
			break

	var best_individual = population[0]
	return {
		"ok": true,
		"lsystem": best_individual.lsystem,
		"score": best_individual.fitness,
		"initial_dir": best_individual.initial_dir,
		"initial_edge": best_individual.initial_edge
	}

static func generate_lsystem_from_score(
	recorded_score: Array,
	origin,
	interpreter,
	parent_selection_fn: Callable = TournamentSelectionScript.select, #might be changed
	survival_type: String = SURVIVAL_MU_PLUS_LAMBDA, #might be changed
	distance_fn: Callable = TonnetzMovementDistanceScript.get_distance, #might be changed
	generation_completed_fn: Callable = Callable(),
	base_config: Dictionary = {}
) -> Dictionary:
	var config := create_default_config()
	for key in base_config.keys():
		config[key] = base_config[key]
	config["target_score"] = recorded_score
	config["target_origin"] = origin
	config["interpreter"] = interpreter
	config["survival_type"] = survival_type
	config["distance_fn"] = distance_fn

	var population: Array = InitialPopulationScript.create_initial(config)
	population = run_generations(
		population,
		config,
		parent_selection_fn,
		generation_completed_fn
	)
	var best_individual = population[0]
	return {
		"ok": true,
		"lsystem": best_individual.lsystem,
		"score": best_individual.fitness,
		"initial_dir": best_individual.initial_dir,
		"initial_edge": best_individual.initial_edge
	}

static func create_default_config() -> Dictionary:
	return {
		"mu": MU,
		"lambda": LAMBDA,
		"generations": GENERATIONS,
		"crossover_rate": CROSSOVER_RATE,
		"mutation_rate": MUTATION_RATE,
		"tournament_size": TOURNAMENT_SIZE,
		"survival_type": SURVIVAL_MU_PLUS_LAMBDA,
		"iterations": TonnetzConfigResource.number_iterations,
		"fitness_weights": FITNESS_WEIGHTS.duplicate(true),
		"comparison_fn": IndexAlignedComparisonScript.compare,
		"distance_fn": TonnetzMovementDistanceScript.get_distance,
		"target_score": [],
		"target_origin": null,
		"interpreter": null
	}

static func evaluate_fitness(individual, config: Dictionary) -> float:
	var candidate_score: Array = config["interpreter"].set_actions(
		individual.lsystem.generated_string,
		config["target_origin"],
		0.0, # beat start
		1, # play once
		true, # draw_tail - only for visual 
		individual.initial_dir,
		individual.initial_edge
	)

	var measures: Dictionary = config["comparison_fn"].call(
		candidate_score,
		config["target_score"],
		config
	)
	var weights: Dictionary = config["fitness_weights"]
	individual.fitness = (
		+ measures["distance"] * weights["distance_weight"]
		+ measures["duration"] * weights["duration_weight"]
		+ measures["total_duration"] * weights["total_duration_weight"]
		+ measures["missing"] * weights["missing_event_weight"]
		+ measures["extra"] * weights["extra_event_weight"]
		+ measures["anchor_match"] * weights["anchor_match_weight"]
		+ measures["pitch_match"] * weights["pitch_match_weight"]
		+ measures["event_match"] * weights["event_match_weight"]
	)
	return individual.fitness

static func generation_step(
	population: Array,
	config: Dictionary,
	selection_fn: Callable
) -> Array:
	_evaluate_population(population, config)

	var offspring: Array = []

	#recombination
	#While the number of offspring is less than the desired number of 
	#offspring (lambda), select two parents from the population using the 
	#selection function.  If a random float is less than the 
	#mutation rate, mutate the child. Append the child to the offspring array.
	while offspring.size() < config["lambda"]:
		var parent_a = selection_fn.call(population, config)
		var parent_b = selection_fn.call(population, config)

		#If a parent is null, break the loop. 
		if parent_a == null || parent_b == null:
			break

		#Create a child by copying one parent or recombining both parents.
		var child = parent_a.copy()
		if randf() < config["crossover_rate"]:
			child = recombination_fn.call(parent_a, parent_b, config)

		#If a random float is less than the mutation rate, mutate.
		if randf() < config["mutation_rate"]:
			child = mutation_fn.call(child, config)

		offspring.append(child)

	_evaluate_population(offspring, config)
	return _select_survivors(population, offspring, config)

static func run_generations(
	population: Array,
	config: Dictionary,
	selection_fn: Callable,
	generation_completed_fn: Callable = Callable()
) -> Array:
	for generation in range(config["generations"]):
		population = generation_step(
			population,
			config,
			selection_fn
		)
		var stats := get_statistics(population)

		if generation_completed_fn.is_valid():
			generation_completed_fn.call(generation, population, stats)

		#stop the evolution if the best score is equal to 0.0
		if stats["best_fitness"] == 0.0:
			break

	return population

static func _select_survivors(
	parents: Array,
	offspring: Array,
	config: Dictionary
) -> Array:
	var candidates: Array = []
	#if the survival type is mu + lambda, include the parents in the candidates
	if config["survival_type"] == SURVIVAL_MU_PLUS_LAMBDA:
		candidates.append_array(parents)
	#always include the offspring in the candidates
	candidates.append_array(offspring)
	candidates.sort_custom(func(a, b): return a.fitness < b.fitness)
	return candidates.slice(0, min(config["mu"], candidates.size()))

static func get_statistics(population: Array) -> Dictionary:

	var best_fitness := INF
	var worst_fitness := -INF
	var total := 0.0

	for individual in population:
		best_fitness = min(best_fitness, individual.fitness)
		worst_fitness = max(worst_fitness, individual.fitness)
		total += individual.fitness

	return {
		"best_fitness": best_fitness,
		"mean_fitness": total / float(population.size()),
		"worst_fitness": worst_fitness
	}

static func _evaluate_population(
	population: Array,
	config: Dictionary
) -> void:
	for individual in population:
		individual.fitness = evaluate_fitness(individual, config)

static func _wait_one_frame(scene_tree: SceneTree) -> void:
	if scene_tree == null:
		return
	#give the scene tree a chance to process other stuff before continuing
	await scene_tree.process_frame
