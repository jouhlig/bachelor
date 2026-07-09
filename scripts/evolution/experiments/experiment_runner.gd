class_name ExperimentRunner
extends RefCounted

const EvolutionScript = preload("res://scripts/evolution/evolution.gd")
const TournamentSelectionScript = preload("res://scripts/evolution/selection/tournament_selection.gd")
const IndexAlignedComparisonScript = preload("res://scripts/evolution/comparison/index_aligned_comparison.gd")
const BeatBasedComparisonScript = preload("res://scripts/evolution/comparison/beat_based_comparison.gd")
const MusicalEventDistanceScript = preload("res://scripts/evolution/distance/musical_event_distance.gd")
const TonnetzMovementDistanceScript = preload("res://scripts/evolution/distance/tonnetz_movement_distance.gd")

const RESULTS_DIR := "res://scripts/evolution/experiments/results"

static func run(
	walks: Array[Dictionary],
	base_config: Dictionary = {},
	seeds: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
	results_dir: String = RESULTS_DIR
) -> void:
	var config: Dictionary = base_config 
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(results_dir))

	for experiment in _get_experiments():
		var result_path := "%s/evolution_results_%s.csv" % [
			results_dir,
			_sanitize_experiment_name(str(experiment["name"]))
		]
		var file := FileAccess.open(result_path, FileAccess.WRITE)

		if file == null:
			push_error("Could not open %s for writing." % result_path)
			return

		file.store_line("walk,seed,generation,best_fitness,mean_fitness,worst_fitness")

		for walk in walks:
			for seed_value in seeds:
				seed(seed_value)
				var run_config := _copy_config(config)
				run_config["comparison_fn"] = experiment["comparison"]
				run_config["fitness_weights"] = experiment["fitness_weights"].duplicate(true)
				EvolutionScript.generate_lsystem_from_score(
					walk["score"],
					walk["origin"],
					run_config["interpreter"],
					experiment["selection"],
					experiment["survival_type"],
					experiment["distance"],
					_write_generation_result.bind(file, walk, seed_value),
					run_config
				)

		file.close()

static func _get_experiments() -> Array[Dictionary]:
	var selections := [
		{
			"name": "tournament",
			"function": TournamentSelectionScript.select
		}
	]
	var survival_types := [
		{
			"name": "mu_plus_lambda",
			"value": EvolutionScript.SURVIVAL_MU_PLUS_LAMBDA
		},
		{
			"name": "mu_comma_lambda",
			"value": EvolutionScript.SURVIVAL_MU_COMMA_LAMBDA
		}
	]
	var distances := [
		{
			"name": "pitch_distance",
			"function": MusicalEventDistanceScript.get_distance
		},
		{
			"name": "tonnetz_distance",
			"function": TonnetzMovementDistanceScript.get_distance
		}
	]
	var comparisons := [
		{
			"name": "index_based_comparison",
			"function": IndexAlignedComparisonScript.compare
		},
		{
			"name": "beat_based_comparison",
			"function": BeatBasedComparisonScript.compare
		}
	]
	var no_duration_weights: Dictionary = EvolutionScript.FITNESS_WEIGHTS.duplicate(true)
	no_duration_weights["duration_weight"] = 0.0
	var duration_weights: Dictionary = EvolutionScript.FITNESS_WEIGHTS.duplicate(true)
	duration_weights["duration_weight"] = 20.0
	var fitness_profiles := [
		{
			"name": "no_duration_weights",
			"weights": no_duration_weights
		},
		{
			"name": "duration_weights",
			"weights": duration_weights
		}
	]
	var experiments: Array[Dictionary] = []

	for selection in selections:
		for survival_type in survival_types:
			for distance in distances:
				for comparison in comparisons:
					for fitness_profile in fitness_profiles:
						experiments.append({
							"name": "%s_%s_%s_%s_%s" % [
								selection["name"],
								survival_type["name"],
								distance["name"],
								comparison["name"],
								fitness_profile["name"]
							],
							"selection": selection["function"],
							"selection_name": selection["name"],
							"survival_type": survival_type["value"],
							"survival_type_name": survival_type["name"],
							"distance": distance["function"],
							"distance_name": distance["name"],
							"comparison": comparison["function"],
							"comparison_name": comparison["name"],
							"fitness_weights": fitness_profile["weights"],
							"fitness_profile_name": fitness_profile["name"]
						})

	return experiments

static func _copy_config(config: Dictionary) -> Dictionary:
	var copy := config.duplicate(true)
	copy["target_origin"] = config.get("target_origin")
	copy["interpreter"] = config.get("interpreter")
	copy["comparison_fn"] = config.get("comparison_fn")
	copy["distance_fn"] = config.get("distance_fn")
	return copy

static func _write_generation_result(
	generation: int,
	_population: Array,
	stats: Dictionary,
	file: FileAccess,
	walk: Dictionary,
	seed_value: int
) -> void:
	file.store_line(_format_csv_line(
		walk,
		seed_value,
		generation,
		stats
	))

static func _format_csv_line(
	walk: Dictionary,
	seed_value: int,
	generation: int,
	stats: Dictionary
) -> String:
	return "%s,%d,%d,%.2f,%.2f,%.2f" % [
		str(walk["name"]),
		seed_value,
		generation,
		float(stats["best_fitness"]),
		float(stats["mean_fitness"]),
		float(stats["worst_fitness"])
	]

static func _sanitize_experiment_name(value: String) -> String:
	var result := ""
	var allowed := "abcdefghijklmnopqrstuvwxyz0123456789_"
	for index in range(value.length()):
		var character := value.substr(index, 1).to_lower()
		if allowed.contains(character):
			result += character
		else:
			result += "_"

	while result.begins_with("_"):
		result = result.substr(1)

	while result.ends_with("_"):
		result = result.substr(0, result.length() - 1)

	return result
