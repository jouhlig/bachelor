class_name ExperimentRunner
extends RefCounted

const EvolutionScript = preload("res://scripts/evolution/evolution.gd")
const TournamentSelectionScript = preload("res://scripts/evolution/selection/tournament_selection.gd")
const IndexAlignedComparisonScript = preload("res://scripts/evolution/comparison/index_aligned_comparison.gd")
const BeatBasedComparisonScript = preload("res://scripts/evolution/comparison/beat_based_comparison.gd")
const MusicalEventDistanceScript = preload("res://scripts/evolution/distance/musical_event_distance.gd")

const RESULTS_DIR := "res://scripts/evolution/experiments/results"
const DEFAULT_EXPERIMENT_COMBINATION_NAME := "tournament_mu_plus_lambda_pitch_distance_index_based_comparison_with_recombination"
const CONFIG_PROFILES: Array[Dictionary] = [
	{
		"name": "small_population",
		"values": {
			"mu": 50,
			"lambda": 50
		}
	},
	{
		"name": "large_population",
		"values": {
			"mu": 200,
			"lambda": 200
		}
	},
	{
		"name": "no_recombination",
		"values": {
			"crossover_rate": 0.0
		}
	},
	{
		"name": "with_recombination",
		"values": {
			"crossover_rate": 0.7
		}
	},
	{
		"name": "more_generations",
		"values": {
			"generations": 40
		}
	},
	{
		"name": "small_tournament",
		"values": {
			"tournament_size": 2
		}
	},
	{
		"name": "large_tournament",
		"values": {
			"tournament_size": 5
		}
	},
	{
		"name": "very_large_search",
		"values": {
			"mu": 300,
			"lambda": 300,
			"generations": 80,
			"crossover_rate": 0.7,
			"tournament_size": 5
		}
	},
	{
		"name": "fitness_no_duration",
		"values": {
			"fitness_weights": {
				"distance_weight": 20.0,
				"duration_weight": 0.0,
				"total_duration_weight": 0.0,
				"missing_event_weight": 20.0,
				"extra_event_weight": 20.0,
				"anchor_match_bonus": 0.0,
				"pitch_match_bonus": 0.0,
				"event_match_bonus": 0.0
			}
		}
	},
	{
		"name": "fitness_with_duration",
		"values": {
			"fitness_weights": {
				"distance_weight": 20.0,
				"duration_weight": 20.0,
				"total_duration_weight": 200.0,
				"missing_event_weight": 20.0,
				"extra_event_weight": 20.0,
				"anchor_match_bonus": 0.0,
				"pitch_match_bonus": 0.0,
				"event_match_bonus": 0.0
			}
		}
	}
]

static func run(
	walks: Array[Dictionary],
	base_config: Dictionary = {},
	seeds: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
	results_dir: String = RESULTS_DIR
) -> void:
	test_one_combination(
		walks,
		DEFAULT_EXPERIMENT_COMBINATION_NAME,
		base_config,
		seeds,
		results_dir
	)

static func test_all_combinations(
	walks: Array[Dictionary],
	base_config: Dictionary = {},
	seeds: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
	results_dir: String = RESULTS_DIR
) -> void:
	_run_experiments(
		walks,
		_get_all_experiment_combinations(),
		base_config,
		seeds,
		results_dir
	)

static func test_one_combination(
	walks: Array[Dictionary],
	combination_name: String,
	base_config: Dictionary = {},
	seeds: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
	results_dir: String = RESULTS_DIR
) -> void:
	var experiments: Array[Dictionary] = []

	for experiment in _get_all_experiment_combinations():
		if experiment["name"] == combination_name:
			experiments.append(experiment)
			break

	if experiments.is_empty():
		push_error("Unknown experiment combination: %s" % combination_name)
		return

	_run_experiments(
		walks,
		experiments,
		base_config,
		seeds,
		results_dir
	)

static func _run_experiments(
	walks: Array[Dictionary],
	experiments: Array[Dictionary],
	base_config: Dictionary,
	seeds: Array[int],
	results_dir: String
) -> void:
	var config: Dictionary = EvolutionScript.create_default_config()
	for key in base_config.keys():
		config[key] = base_config[key]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(results_dir))

	for experiment in experiments:
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
				for key in experiment["config_values"].keys():
					var value = experiment["config_values"][key]
					if value is Dictionary or value is Array:
						value = value.duplicate(true)
					run_config[key] = value
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

static func _get_all_experiment_combinations() -> Array[Dictionary]:
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
	var config_profiles := CONFIG_PROFILES.duplicate(true)
	var experiments: Array[Dictionary] = []

	for selection in selections:
		for survival_type in survival_types:
			for distance in distances:
				for comparison in comparisons:
					for config_profile in config_profiles:
						experiments.append({
							"name": "%s_%s_%s_%s_%s" % [
								selection["name"],
								survival_type["name"],
								distance["name"],
								comparison["name"],
								config_profile["name"]
							],
							"selection": selection["function"],
							"selection_name": selection["name"],
							"survival_type": survival_type["value"],
							"survival_type_name": survival_type["name"],
							"distance": distance["function"],
							"distance_name": distance["name"],
							"comparison": comparison["function"],
							"comparison_name": comparison["name"],
							"config_values": config_profile["values"],
							"config_profile_name": config_profile["name"]
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
