extends RefCounted

# runs the evolution loop  

const RecombinationScript = preload("res://scripts/evolution/recombination.gd")
const MutationScript = preload("res://scripts/evolution/mutation.gd")

const RandomLSystemInitialPopulationScript = preload("res://scripts/evolution/initial_population/random_lsystem_initial_population.gd")
# const IdentityInitialPopulationScript = preload("res://scripts/evolution/initial_population/identity_initial_population.gd")

const RandomParentSelectionScript = preload("res://scripts/evolution/random_parent_selection.gd")
const TournamentSurvivalSelectionScript = preload("res://scripts/evolution/tournament_survival_selection.gd")

const SkipAheadComparisonScript = preload("res://scripts/evolution/comparison/skip_ahead_comparison.gd")
# const BeatBasedComparisonScript = preload("res://scripts/evolution/comparison/beat_based_comparison.gd")
# const IndexAlignedComparisonScript = preload("res://scripts/evolution/comparison/index_aligned_comparison.gd")

const MusicalEventDistanceScript = preload("res://scripts/evolution/fitness/musical_event_distance.gd")
# const TonnetzMovementDistanceScript = preload("res://scripts/evolution/fitness/tonnetz_movement_distance.gd")
# const EntryWiseFitnessScript = preload("res://scripts/evolution/fitness/entry_wise_fitness.gd")
# const TupleWiseFitnessScript = preload("res://scripts/evolution/fitness/tuple_wise_fitness.gd")
# DistanceFitnessScript is the helper for both distance based fitness functions
const DistanceFitnessScript = preload("res://scripts/evolution/fitness/distance_fitness.gd")

const TonnetzConfigResource = preload("res://config/config.tres")

#stay the same for every config, only params change
static var recombination_fn: Callable = RecombinationScript.recombine
static var mutation_fn: Callable = MutationScript.mutate

const SURVIVAL_MU_PLUS_LAMBDA := "mu_plus_lambda"
const SURVIVAL_MU_COMMA_LAMBDA := "mu_comma_lambda"
const SURVIVAL_SELECTION_TOURNAMENT := "tournament"

static func generate_lsystem_from_score(
	recorded_score: Array,
	origin,
	interpreter,
	parent_selection_fn: Callable = RandomParentSelectionScript.select, #might be changed
	survival_type: String = SURVIVAL_MU_COMMA_LAMBDA, #might be changed
	distance_fn: Callable = MusicalEventDistanceScript.get_distance, #might be changed
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

	var population: Array = config["initial_population_fn"].call(config)
	population = select_initial_population(population, config)
	base_config["initial_population_size"] = config["initial_population_size"]
	var completed_fn := generation_completed_fn
	if generation_completed_fn.is_valid():
		completed_fn = func(generation: int, current_population: Array, stats: Dictionary) -> void:
			base_config["fitness_evaluation_count"] = int(config.get("fitness_evaluation_count", 0))
			generation_completed_fn.call(generation, current_population, stats)
	population = run_generations(
		population,
		config,
		parent_selection_fn,
		completed_fn
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
		# Number of individuals that survive into the next generation.
		"mu": 20,
		# Number of children created during each generation step.
		"lambda": 40,
		"generations": 100,
		"crossover_rate": 0.3,
		"mutation_rate": 0.7,
		"start_state_mutation_rate": 0.0,
		"tournament_size": 3,
		#mu+lamda -> next generation is selected from parents and offspring
		#mu,lamda -> next generation is selected only from the offspring
		"survival_type": SURVIVAL_MU_COMMA_LAMBDA,
		"survival_selection": SURVIVAL_SELECTION_TOURNAMENT,
		"symmetric_recombination": true,
		"fitness_evaluation_count": 0,
		"iterations": 3,
		"fitness_weights": {
			"distance_weight": 1.5,
			"pitch_weight": 1.5,
			"duration_match_weight": 0.75,
			"total_duration_weight": 0.5,
			"missing_weight": 2.0,
			"extra_weight": 2.0
		},
		"comparison_fn": SkipAheadComparisonScript.compare,
		# "comparison_fn": BeatBasedComparisonScript.compare,
		# "comparison_fn": IndexAlignedComparisonScript.compare,
		"distance_fn": MusicalEventDistanceScript.get_distance,
		# "distance_fn": TonnetzMovementDistanceScript.get_distance,
		"fitness_fn": DistanceFitnessScript.evaluate,
		# "fitness_fn": EntryWiseFitnessScript.evaluate,
		# "fitness_fn": TupleWiseFitnessScript.evaluate,
		"initial_population_fn": RandomLSystemInitialPopulationScript.create_initial,
		# "initial_population_fn": IdentityInitialPopulationScript.create_initial,
		"initial_population_size": 0,
		"target_score": [],
		"target_origin": null,
		"interpreter": null
	}
static func evaluate_fitness(individual, config: Dictionary) -> float:
	config["fitness_evaluation_count"] = int(config.get("fitness_evaluation_count", 0)) + 1
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
	var fitness_fn: Callable = config["fitness_fn"]
	individual.fitness_penalty = fitness_fn.call(measures, config)
	individual.fitness = individual.fitness_penalty
	return individual.fitness

static func generation_step(
	population: Array,
	config: Dictionary,
	parent_selection_fn: Callable
) -> Array:
	var offspring: Array = []

	#recombination
	#While the number of offspring is less than the desired number of 
	#offspring (lambda), draw two parents from the population by parent selection.
	#Create two symmetric children from the parent pair: one based on parent A,
	#one based on parent B.
	#If a random float is less than the 
	#mutation rate, mutate the child. Append the child to the offspring array.
	while offspring.size() < config["lambda"]:
		var parent_a = parent_selection_fn.call(population, config)
		var parent_b = parent_selection_fn.call(population, config)

		#If a parent is null, break the loop. 
		if parent_a == null || parent_b == null:
			break

		var recombine_pair: bool = randf() < config["crossover_rate"]
		var symmetric_recombination := bool(config.get("symmetric_recombination", true))

		#Create a child by copying one parent or recombining both parents
		var child_a = parent_a.copy()
		if recombine_pair:
			child_a = recombination_fn.call(parent_a, parent_b, config)

		#If a random float is less than the mutation rate, mutate
		if randf() < config["mutation_rate"]:
			child_a = mutation_fn.call(child_a, config)

		offspring.append(child_a)

		if not symmetric_recombination:
			continue

		if offspring.size() >= config["lambda"]:
			break

		#Create the symmetric child with parent B as the copy/recombination base
		var child_b = parent_b.copy()
		if recombine_pair:
			child_b = recombination_fn.call(parent_b, parent_a, config)

		#If a random float is less than the mutation rate, mutate
		if randf() < config["mutation_rate"]:
			child_b = mutation_fn.call(child_b, config)

		offspring.append(child_b)

	_evaluate_population(offspring, config)
	if config["survival_type"] == SURVIVAL_MU_PLUS_LAMBDA:
		_evaluate_population(population, config)
	return _select_survivors(population, offspring, config)

static func select_initial_population(
	population: Array,
	config: Dictionary
) -> Array:
	config["initial_population_size"] = population.size()

	if population.size() <= config["mu"]:
		return population

	return population.slice(0, config["mu"])

static func run_generations(
	population: Array,
	config: Dictionary,
	parent_selection_fn: Callable,
	generation_completed_fn: Callable = Callable()
) -> Array:
	for generation in range(config["generations"]):
		population = generation_step(
			population,
			config,
			parent_selection_fn
		)
		var stats := get_statistics(population)

		if generation_completed_fn.is_valid():
			generation_completed_fn.call(generation, population, stats)

		#stop the evolution if the target has no remaining penalty
		if stats["target_reached"]:
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
	if config["survival_selection"] == SURVIVAL_SELECTION_TOURNAMENT:
		return TournamentSurvivalSelectionScript.select(
			candidates,
			min(config["mu"], candidates.size()),
			config
		)
	candidates.sort_custom(func(a, b): return a.fitness < b.fitness)
	return candidates.slice(0, min(config["mu"], candidates.size()))

static func get_statistics(population: Array) -> Dictionary:

	var best_fitness := INF
	var worst_fitness := -INF
	var total := 0.0
	var target_reached := false

	for individual in population:
		best_fitness = min(best_fitness, individual.fitness)
		worst_fitness = max(worst_fitness, individual.fitness)
		total += individual.fitness
		if is_zero_approx(individual.fitness_penalty):
			target_reached = true

	return {
		"best_fitness": best_fitness,
		"mean_fitness": total / float(population.size()),
		"worst_fitness": worst_fitness,
		"target_reached": target_reached
	}

static func _evaluate_population(
	population: Array,
	config: Dictionary
) -> void:
	for individual in population:
		if is_inf(individual.fitness):
			individual.fitness = evaluate_fitness(individual, config)

static func _wait_one_frame(scene_tree: SceneTree) -> void:
	if scene_tree == null:
		return
	#give the scene tree a chance to process other stuff before continuing
	await scene_tree.process_frame
