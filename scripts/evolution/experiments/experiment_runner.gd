class_name ExperimentRunner
extends RefCounted

const EvolutionScript = preload("res://scripts/evolution/evolution.gd")
const TournamentSelectionScript = preload("res://scripts/evolution/tournament_selection.gd")
const SkipAheadComparisonScript = preload("res://scripts/evolution/comparison/skip_ahead_comparison.gd")
const MusicalEventDistanceScript = preload("res://scripts/evolution/distance/musical_event_distance.gd")
const TonnetzMovementDistanceScript = preload("res://scripts/evolution/distance/tonnetz_movement_distance.gd")
const EventMatchFitnessScript = preload("res://scripts/evolution/fitness/event_match_fitness.gd")
const PitchMatchFitnessScript = preload("res://scripts/evolution/fitness/pitch_match_fitness.gd")
const DistanceFitnessScript = preload("res://scripts/evolution/fitness/distance_fitness.gd")

const RESULTS_DIR := "res://scripts/evolution/experiments/results"
const DEFAULT_EXPERIMENT_COMBINATION_NAME := "tournament_mu_plus_lambda_skip_ahead_comparison_event_match_default_config"
const CONFIG_PROFILES: Array[Dictionary] = [
	{
		"name": "default_config",
		"values": {}
	},
]

static func run(
	walks: Array[Dictionary],
	interpreter,
	base_config: Dictionary = {},
	results_dir: String = RESULTS_DIR
) -> void:
	test_one_combination(
		walks,
		DEFAULT_EXPERIMENT_COMBINATION_NAME,
		interpreter,
		base_config,
		results_dir
	)

static func test_all_combinations(
	walks: Array[Dictionary],
	interpreter,
	base_config: Dictionary = {},
	results_dir: String = RESULTS_DIR
) -> void:
	_run_experiments(
		walks,
		_get_all_experiment_combinations(),
		interpreter,
		base_config,
		results_dir
	)

static func test_one_combination(
	walks: Array[Dictionary],
	combination_name: String,
	interpreter,
	base_config: Dictionary = {},
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
		interpreter,
		base_config,
		results_dir
	)

static func get_combination_names() -> PackedStringArray:
	var names := PackedStringArray()
	for experiment in _get_all_experiment_combinations():
		names.append(str(experiment["name"]))
	return names

static func _run_experiments(
	walks: Array[Dictionary],
	experiments: Array[Dictionary],
	interpreter,
	base_config: Dictionary,
	results_dir: String
) -> void:
	var config: Dictionary = EvolutionScript.create_default_config()
	for key in base_config.keys():
		config[key] = base_config[key]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(results_dir))
	var raw_dir := "%s/raw" % results_dir
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(raw_dir))
	_write_manifest(results_dir, experiments, config, walks)

	for experiment in experiments:
		var result_path := "%s/evolution_results_%s.csv" % [
			raw_dir,
			_sanitize_experiment_name(str(experiment["name"]))
		]
		var file := FileAccess.open(result_path, FileAccess.WRITE)

		if file == null:
			push_error("Could not open %s for writing." % result_path)
			return

		file.store_line(
			"run,anchor_type,walk_length,generation,fitness_evaluations,best_fitness,mean_fitness,worst_fitness,match_rate,pitch_match_rate,mean_tonnetz_distance,mean_pitch_distance,mean_duration_error,total_duration_error,missing_events,extra_events,target_reached"
		)

		for walk in walks:
			var score: Array = walk["score"]
			var origin = score[0]["anchor"]
			var run_config := _copy_config(config)
			run_config["comparison_fn"] = experiment["comparison"]
			run_config["fitness_fn"] = experiment["fitness"]
			for key in experiment["config_values"].keys():
				var value = experiment["config_values"][key]
				if value is Dictionary or value is Array:
					value = value.duplicate(true)
				run_config[key] = value
			EvolutionScript.generate_lsystem_from_score(
				score,
				origin,
				interpreter,
				experiment["selection"],
				experiment["survival_type"],
				experiment["distance"],
				_write_generation_result.bind(file, walk, interpreter, run_config),
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
		}
	]
	var comparisons := [
		{
			"name": "skip_ahead_comparison",
			"function": SkipAheadComparisonScript.compare
		}
	]
	var fitness_modes := [
		{
			"name": "event_match",
			"fitness": EventMatchFitnessScript.evaluate,
			"distance": TonnetzMovementDistanceScript.get_distance,
			"config_values": {
				"skip_ahead_cost_mode": "event_match"
			}
		},
		{
			"name": "pitch_match",
			"fitness": PitchMatchFitnessScript.evaluate,
			"distance": TonnetzMovementDistanceScript.get_distance,
			"config_values": {
				"skip_ahead_cost_mode": "pitch_match"
			}
		},
		{
			"name": "tonnetz_distance",
			"fitness": DistanceFitnessScript.evaluate,
			"distance": TonnetzMovementDistanceScript.get_distance,
			"config_values": {
				"skip_ahead_cost_mode": "distance",
				"skip_ahead_distance_weight": 0.5,
				"skip_ahead_duration_weight": 0.5
			}
		},
		{
			"name": "pitch_distance",
			"fitness": DistanceFitnessScript.evaluate,
			"distance": MusicalEventDistanceScript.get_distance,
			"config_values": {
				"skip_ahead_cost_mode": "distance",
				"skip_ahead_distance_weight": 0.1,
				"skip_ahead_duration_weight": 0.5
			}
		}
	]
	var config_profiles := CONFIG_PROFILES.duplicate(true)
	var experiments: Array[Dictionary] = []

	for selection in selections:
		for survival_type in survival_types:
			for comparison in comparisons:
				for fitness_mode in fitness_modes:
					for config_profile in config_profiles:
						experiments.append({
							"name": "%s_%s_%s_%s_%s" % [
								selection["name"],
								survival_type["name"],
								comparison["name"],
								fitness_mode["name"],
								config_profile["name"]
							],
							"selection": selection["function"],
							"selection_name": selection["name"],
							"survival_type": survival_type["value"],
							"survival_type_name": survival_type["name"],
							"comparison": comparison["function"],
							"comparison_name": comparison["name"],
							"distance": fitness_mode["distance"],
							"fitness": fitness_mode["fitness"],
							"fitness_name": fitness_mode["name"],
							"config_values": _merge_config_values(
								config_profile["values"],
								fitness_mode["config_values"]
							),
							"config_profile_name": config_profile["name"]
						})

	return experiments

static func _copy_config(config: Dictionary) -> Dictionary:
	var copy := config.duplicate(true)
	copy["target_origin"] = config.get("target_origin")
	copy["comparison_fn"] = config.get("comparison_fn")
	copy["distance_fn"] = config.get("distance_fn")
	copy["fitness_fn"] = config.get("fitness_fn")
	return copy

static func _merge_config_values(base_values: Dictionary, override_values: Dictionary) -> Dictionary:
	var merged := base_values.duplicate(true)
	for key in override_values.keys():
		var value = override_values[key]
		if value is Dictionary or value is Array:
			value = value.duplicate(true)
		merged[key] = value
	return merged

static func _write_generation_result(
	generation: int,
	population: Array,
	stats: Dictionary,
	file: FileAccess,
	walk: Dictionary,
	interpreter,
	config: Dictionary
) -> void:
	var metrics := _get_common_metrics(population[0], walk, interpreter, config, generation)
	file.store_line(_format_csv_line(
		walk,
		generation,
		stats,
		metrics
	))

static func _format_csv_line(
	walk: Dictionary,
	generation: int,
	stats: Dictionary,
	metrics: Dictionary
) -> String:
	return "%s,%s,%d,%d,%d,%.2f,%.2f,%.2f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.2f,%.2f,%s" % [
		str(walk["name"]),
		_get_anchor_type(walk),
		_get_walk_length(walk),
		generation,
		int(metrics["fitness_evaluations"]),
		float(stats["best_fitness"]),
		float(stats["mean_fitness"]),
		float(stats["worst_fitness"]),
		float(metrics["match_rate"]),
		float(metrics["pitch_match_rate"]),
		float(metrics["mean_tonnetz_distance"]),
		float(metrics["mean_pitch_distance"]),
		float(metrics["mean_duration_error"]),
		float(metrics["total_duration_error"]),
		float(metrics["missing_events"]),
		float(metrics["extra_events"]),
		str(stats["target_reached"])
	]

static func _get_walk_length(walk: Dictionary) -> int:
	return walk.get("score", []).size()

static func _get_anchor_type(walk: Dictionary) -> String:
	var score: Array = walk.get("score", [])
	if score.is_empty():
		return "unknown"

	var anchor = score[0].get("anchor")
	if anchor is TonnetzNode:
		return "node"
	if anchor is TriangleArea:
		return "triangle"

	return "unknown"

static func _get_common_metrics(
	individual,
	walk: Dictionary,
	interpreter,
	config: Dictionary,
	generation: int
) -> Dictionary:
	var target_score: Array = walk["score"]
	var candidate_score: Array = interpreter.set_actions(
		individual.lsystem.generated_string,
		target_score[0]["anchor"],
		0.0, # beat start
		1, # play once
		true, # draw_tail - only for visual
		individual.initial_dir,
		individual.initial_edge
	)
	var tonnetz_config := _copy_config(config)
	tonnetz_config["distance_fn"] = TonnetzMovementDistanceScript.get_distance
	var tonnetz_measures: Dictionary = SkipAheadComparisonScript.compare(
		candidate_score,
		target_score,
		tonnetz_config
	)
	var pitch_config := _copy_config(config)
	pitch_config["distance_fn"] = MusicalEventDistanceScript.get_distance
	var pitch_measures: Dictionary = SkipAheadComparisonScript.compare(
		candidate_score,
		target_score,
		pitch_config
	)
	var target_count: float = max(1.0, float(target_score.size()))
	var paired_count: float = max(1.0, float(tonnetz_measures["paired"]))
	return {
		"fitness_evaluations": _get_fitness_evaluations(config, generation),
		"match_rate": float(tonnetz_measures["event_match"]) / target_count,
		"pitch_match_rate": float(tonnetz_measures["pitch_match"]) / target_count,
		"mean_tonnetz_distance": float(tonnetz_measures["distance"]) / paired_count,
		"mean_pitch_distance": float(pitch_measures["distance"]) / paired_count,
		"mean_duration_error": float(tonnetz_measures["duration"]) / paired_count,
		"total_duration_error": float(tonnetz_measures["total_duration"]),
		"missing_events": float(tonnetz_measures["missing"]),
		"extra_events": float(tonnetz_measures["extra"])
	}

static func _get_fitness_evaluations(config: Dictionary, generation: int) -> int:
	return (generation + 1) * (int(config["mu"]) + int(config["lambda"]))

static func _write_manifest(
	results_dir: String,
	experiments: Array[Dictionary],
	config: Dictionary,
	walks: Array[Dictionary]
) -> void:
	var manifest_path := "%s/manifest.json" % results_dir
	var manifest := _load_manifest(manifest_path)
	manifest["results_dir"] = results_dir
	manifest["raw_dir"] = "%s/raw" % results_dir
	manifest["target_scores_path"] = str(config.get("target_scores_path", ""))
	manifest["target_score_count"] = int(config.get("target_score_count", walks.size()))
	manifest["walk_count"] = walks.size()
	manifest["anchor_type_counts"] = _get_anchor_type_counts(walks)
	manifest["ea_config"] = _get_manifest_config(config)
	manifest["experiments"] = _merge_manifest_experiments(
		manifest.get("experiments", []),
		experiments
	)

	var file := FileAccess.open(manifest_path, FileAccess.WRITE)
	if file == null:
		push_error("Could not write manifest: %s" % manifest_path)
		return

	file.store_string(JSON.stringify(manifest, "\t"))

static func _load_manifest(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}

	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return parsed

	return {}

static func _merge_manifest_experiments(
	existing_experiments,
	new_experiments: Array[Dictionary]
) -> Array:
	var result: Array = []
	var names := {}

	if existing_experiments is Array:
		for experiment in existing_experiments:
			if experiment is Dictionary:
				result.append(experiment)
				names[str(experiment.get("name", ""))] = true

	for experiment in new_experiments:
		var experiment_name := str(experiment["name"])
		if names.has(experiment_name):
			continue

		result.append({
			"name": experiment_name,
			"parent_selection": "uniform_random_with_replacement",
			"survival_selection": str(experiment["selection_name"]),
			"survival_type": str(experiment["survival_type_name"]),
			"comparison": str(experiment["comparison_name"]),
			"fitness": str(experiment["fitness_name"]),
			"config_profile": str(experiment["config_profile_name"]),
			"config_values": experiment["config_values"].duplicate(true)
		})
		names[experiment_name] = true

	return result

static func _get_manifest_config(config: Dictionary) -> Dictionary:
	return {
		"mu": int(config["mu"]),
		"lambda": int(config["lambda"]),
		"generations": int(config["generations"]),
		"crossover_rate": float(config["crossover_rate"]),
		"mutation_rate": float(config["mutation_rate"]),
		"tournament_size": int(config["tournament_size"]),
		"iterations": int(config["iterations"]),
		"survival_type": str(config["survival_type"]),
		"fitness_evaluations_per_generation": int(config["mu"]) + int(config["lambda"])
	}

static func _get_anchor_type_counts(walks: Array[Dictionary]) -> Dictionary:
	var counts := {
		"node": 0,
		"triangle": 0,
		"unknown": 0
	}

	for walk in walks:
		var anchor_type := _get_anchor_type(walk)
		counts[anchor_type] = int(counts.get(anchor_type, 0)) + 1

	return counts

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
