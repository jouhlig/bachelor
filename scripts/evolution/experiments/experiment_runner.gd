class_name ExperimentRunner
extends RefCounted

const EvolutionScript = preload("res://scripts/evolution/evolution.gd")
const TournamentSelectionScript = preload("res://scripts/evolution/tournament_selection.gd")
const IdentityInitialPopulationScript = preload("res://scripts/evolution/initial_population/identity_initial_population.gd")
const RandomLSystemInitialPopulationScript = preload("res://scripts/evolution/initial_population/random_lsystem_initial_population.gd")
const SkipAheadComparisonScript = preload("res://scripts/evolution/comparison/skip_ahead_comparison.gd")
const BeatBasedComparisonScript = preload("res://scripts/evolution/comparison/beat_based_comparison.gd")
const IndexAlignedComparisonScript = preload("res://scripts/evolution/comparison/index_aligned_comparison.gd")
const MusicalEventDistanceScript = preload("res://scripts/evolution/distance/musical_event_distance.gd")
const TonnetzMovementDistanceScript = preload("res://scripts/evolution/distance/tonnetz_movement_distance.gd")
const TupleWiseFitnessScript = preload("res://scripts/evolution/fitness/tuple_wise_fitness.gd")
const EntryWiseFitnessScript = preload("res://scripts/evolution/fitness/entry_wise_fitness.gd")
const DistanceFitnessScript = preload("res://scripts/evolution/fitness/distance_fitness.gd")
const LegacyEntryMatchFitnessScript = preload("res://scripts/evolution/fitness/legacy_entry_match_fitness.gd")
const LegacyDistanceFitnessScript = preload("res://scripts/evolution/fitness/legacy_distance_fitness.gd")

const RESULTS_DIR := "res://scripts/evolution/experiments/results"
const DEFAULT_EXPERIMENT_COMBINATION_NAME := "tournament_mu_plus_lambda_identity_target_direction_rules_beat_based_comparison_entry_wise_fitness"

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

	for experiment in _get_selectable_experiment_combinations():
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
	for experiment in _get_selectable_experiment_combinations():
		names.append(str(experiment["name"]))
	return names

static func _get_selectable_experiment_combinations() -> Array[Dictionary]:
	var experiments := _get_all_experiment_combinations()
	experiments.append_array(_get_legacy_comparison_combinations())
	return experiments

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
			"run,anchor_type,walk_length,generation,fitness_evaluations,best_fitness,mean_fitness,worst_fitness,match_rate,mean_match_rate,pitch_match_rate,mean_pitch_match_rate,duration_match_rate,mean_duration_match_rate,mean_tonnetz_distance,population_mean_tonnetz_distance,mean_pitch_distance,population_mean_pitch_distance,duration_error_rate,mean_duration_error_rate,missing_event_rate,mean_missing_event_rate,extra_event_rate,mean_extra_event_rate,total_duration_error,mean_total_duration_error,missing_beats,mean_missing_beats,extra_beats,mean_extra_beats,target_reached"
		)

		for walk in walks:
			var score: Array = walk["score"]
			var origin = score[0]["anchor"]
			var run_config := _copy_config(config)
			run_config["initial_population_fn"] = experiment["initial_population"]
			run_config["comparison_fn"] = experiment["comparison"]
			run_config["fitness_fn"] = experiment["fitness"]
			run_config["experiment_name"] = experiment["name"]
			run_config["results_dir"] = results_dir
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
		},
		{
			"name": "mu_comma_lambda",
			"value": EvolutionScript.SURVIVAL_MU_COMMA_LAMBDA
		}
	]
	var initial_populations := [
		{
			"name": "identity_target_direction_rules",
			"function": IdentityInitialPopulationScript.create_initial
		},
		{
			"name": "random_rules",
			"function": RandomLSystemInitialPopulationScript.create_initial
		}
	]
	var comparisons := [
		{
			"name": "skip_ahead_comparison",
			"function": SkipAheadComparisonScript.compare
		},
		{
			"name": "beat_based_comparison",
			"function": BeatBasedComparisonScript.compare
		},
		{
			"name": "index_aligned_comparison",
			"function": IndexAlignedComparisonScript.compare
		}
	]
	var fitness_modes := [
		{
			"name": "tuple_wise_fitness",
			"fitness": TupleWiseFitnessScript.evaluate,
			"distance": TonnetzMovementDistanceScript.get_distance,
			"config_values": {}
		},
		{
			"name": "entry_wise_fitness",
			"fitness": EntryWiseFitnessScript.evaluate,
			"distance": TonnetzMovementDistanceScript.get_distance,
			"config_values": {}
		},
		{
			"name": "tonnetz_distance",
			"fitness": DistanceFitnessScript.evaluate,
			"distance": TonnetzMovementDistanceScript.get_distance,
			"config_values": {}
		},
		{
			"name": "pitch_distance",
			"fitness": DistanceFitnessScript.evaluate,
			"distance": MusicalEventDistanceScript.get_distance,
			"config_values": {}
		}
	]
	var experiments: Array[Dictionary] = []

	for selection in selections:
		for survival_type in survival_types:
			for initial_population in initial_populations:
				for comparison in comparisons:
					for fitness_mode in fitness_modes:
						experiments.append({
							"name": "%s_%s_%s_%s_%s" % [
								selection["name"],
								survival_type["name"],
								initial_population["name"],
								comparison["name"],
								fitness_mode["name"]
							],
							"selection": selection["function"],
							"selection_name": selection["name"],
							"survival_type": survival_type["value"],
							"survival_type_name": survival_type["name"],
							"initial_population": initial_population["function"],
							"initial_population_name": initial_population["name"],
							"comparison": comparison["function"],
							"comparison_name": comparison["name"],
							"distance": fitness_mode["distance"],
							"fitness": fitness_mode["fitness"],
							"fitness_name": fitness_mode["name"],
							"config_values": fitness_mode["config_values"].duplicate(true)
						})

	return experiments

static func _get_legacy_comparison_combinations() -> Array[Dictionary]:
	return [
		{
			"name": "tournament_mu_plus_lambda_random_rules_beat_based_comparison_entry_match_legacy_20260803_fitness",
			"selection": TournamentSelectionScript.select,
			"selection_name": "tournament",
			"survival_type": EvolutionScript.SURVIVAL_MU_PLUS_LAMBDA,
			"survival_type_name": "mu_plus_lambda",
			"initial_population": RandomLSystemInitialPopulationScript.create_initial,
			"initial_population_name": "random_rules",
			"comparison": BeatBasedComparisonScript.compare,
			"comparison_name": "beat_based_comparison",
			"distance": TonnetzMovementDistanceScript.get_distance,
			"fitness": LegacyEntryMatchFitnessScript.evaluate,
			"fitness_name": "entry_match_legacy_20260803",
			"config_values": {}
		},
		{
			"name": "tournament_mu_plus_lambda_random_rules_index_aligned_comparison_pitch_distance_legacy_20260803_fitness",
			"selection": TournamentSelectionScript.select,
			"selection_name": "tournament",
			"survival_type": EvolutionScript.SURVIVAL_MU_PLUS_LAMBDA,
			"survival_type_name": "mu_plus_lambda",
			"initial_population": RandomLSystemInitialPopulationScript.create_initial,
			"initial_population_name": "random_rules",
			"comparison": IndexAlignedComparisonScript.compare,
			"comparison_name": "index_aligned_comparison",
			"distance": MusicalEventDistanceScript.get_distance,
			"fitness": LegacyDistanceFitnessScript.evaluate,
			"fitness_name": "pitch_distance_legacy_20260803",
			"config_values": {}
		}
	]

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
	var metrics := _get_population_common_metrics(population, walk, interpreter, config, generation)
	file.store_line(_format_csv_line(
		walk,
		generation,
		stats,
		metrics
	))
	if bool(config.get("debug_final_scores", false)) and (
		bool(stats["target_reached"]) or generation == int(config["generations"]) - 1
	):
		_write_debug_score_result(population[0], walk, interpreter, config, generation, stats, metrics)

static func _format_csv_line(
	walk: Dictionary,
	generation: int,
	stats: Dictionary,
	metrics: Dictionary
) -> String:
	return "%s,%s,%d,%d,%d,%.2f,%.2f,%.2f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.2f,%.2f,%.2f,%.2f,%s" % [
		str(walk["name"]),
		_get_anchor_type(walk),
		_get_walk_length(walk),
		generation,
		int(metrics["fitness_evaluations"]),
		float(stats["best_fitness"]),
		float(stats["mean_fitness"]),
		float(stats["worst_fitness"]),
		float(metrics["match_rate"]),
		float(metrics["mean_match_rate"]),
		float(metrics["pitch_match_rate"]),
		float(metrics["mean_pitch_match_rate"]),
		float(metrics["duration_match_rate"]),
		float(metrics["mean_duration_match_rate"]),
		float(metrics["mean_tonnetz_distance"]),
		float(metrics["population_mean_tonnetz_distance"]),
		float(metrics["mean_pitch_distance"]),
		float(metrics["population_mean_pitch_distance"]),
		float(metrics["duration_error_rate"]),
		float(metrics["mean_duration_error_rate"]),
		float(metrics["missing_event_rate"]),
		float(metrics["mean_missing_event_rate"]),
		float(metrics["extra_event_rate"]),
		float(metrics["mean_extra_event_rate"]),
		float(metrics["total_duration_error"]),
		float(metrics["mean_total_duration_error"]),
		float(metrics["missing_beats"]),
		float(metrics["mean_missing_beats"]),
		float(metrics["extra_beats"]),
		float(metrics["mean_extra_beats"]),
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

static func _get_population_common_metrics(
	population: Array,
	walk: Dictionary,
	interpreter,
	config: Dictionary,
	generation: int
) -> Dictionary:
	var best_metrics := _get_common_metrics(population[0], walk, interpreter, config, generation)
	var totals := {}
	var metric_names := [
		"match_rate",
		"pitch_match_rate",
		"duration_match_rate",
		"mean_tonnetz_distance",
		"mean_pitch_distance",
		"duration_error_rate",
		"missing_event_rate",
		"extra_event_rate",
		"total_duration_error",
		"missing_beats",
		"extra_beats"
	]

	for metric_name in metric_names:
		totals[metric_name] = 0.0

	for individual in population:
		var individual_metrics := _get_common_metrics(individual, walk, interpreter, config, generation)
		for metric_name in metric_names:
			totals[metric_name] += float(individual_metrics[metric_name])

	var population_size: float = max(1.0, float(population.size()))
	best_metrics["mean_match_rate"] = totals["match_rate"] / population_size
	best_metrics["mean_pitch_match_rate"] = totals["pitch_match_rate"] / population_size
	best_metrics["mean_duration_match_rate"] = totals["duration_match_rate"] / population_size
	best_metrics["population_mean_tonnetz_distance"] = totals["mean_tonnetz_distance"] / population_size
	best_metrics["population_mean_pitch_distance"] = totals["mean_pitch_distance"] / population_size
	best_metrics["mean_duration_error_rate"] = totals["duration_error_rate"] / population_size
	best_metrics["mean_missing_event_rate"] = totals["missing_event_rate"] / population_size
	best_metrics["mean_extra_event_rate"] = totals["extra_event_rate"] / population_size
	best_metrics["mean_total_duration_error"] = totals["total_duration_error"] / population_size
	best_metrics["mean_missing_beats"] = totals["missing_beats"] / population_size
	best_metrics["mean_extra_beats"] = totals["extra_beats"] / population_size
	return best_metrics

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
	var tonnetz_measures: Dictionary = BeatBasedComparisonScript.compare(
		candidate_score,
		target_score,
		tonnetz_config
	)
	var pitch_config := _copy_config(config)
	pitch_config["distance_fn"] = MusicalEventDistanceScript.get_distance
	var pitch_measures: Dictionary = BeatBasedComparisonScript.compare(
		candidate_score,
		target_score,
		pitch_config
	)
	var target_duration: float = max(1.0, _get_score_duration(target_score))
	var target_event_count: float = max(1.0, float(target_score.size()))
	var paired_duration: float = max(1.0, float(tonnetz_measures["paired"]))
	return {
		"fitness_evaluations": _get_fitness_evaluations(config, generation),
		"match_rate": float(tonnetz_measures["event_match"]) / target_duration,
		"pitch_match_rate": float(tonnetz_measures["pitch_match"]) / target_duration,
		"duration_match_rate": float(tonnetz_measures["duration_match"]) / target_duration,
		"mean_tonnetz_distance": float(tonnetz_measures["distance"]) / paired_duration,
		"mean_pitch_distance": float(pitch_measures["distance"]) / paired_duration,
		"duration_error_rate": float(tonnetz_measures["duration"]) / target_duration,
		"missing_event_rate": float(tonnetz_measures["missing_events"]) / target_event_count,
		"extra_event_rate": float(tonnetz_measures["extra_events"]) / target_event_count,
		"total_duration_error": float(tonnetz_measures["total_duration"]),
		"missing_beats": float(tonnetz_measures["missing"]),
		"extra_beats": float(tonnetz_measures["extra"])
	}

static func _get_fitness_evaluations(config: Dictionary, generation: int) -> int:
	return (generation + 1) * (int(config["mu"]) + int(config["lambda"]))

static func _write_debug_score_result(
	individual,
	walk: Dictionary,
	interpreter,
	config: Dictionary,
	generation: int,
	stats: Dictionary,
	metrics: Dictionary
) -> void:
	var target_score: Array = walk["score"]
	var generated_score: Array = interpreter.set_actions(
		individual.lsystem.generated_string,
		target_score[0]["anchor"],
		0.0, # beat start
		1, # play once
		true, # draw_tail - only for visual
		individual.initial_dir,
		individual.initial_edge
	)
	var debug_dir := "%s/debug_scores" % str(config.get("results_dir", RESULTS_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(debug_dir))
	var debug_path := "%s/%s_%s.json" % [
		debug_dir,
		_sanitize_experiment_name(str(config.get("experiment_name", "experiment"))),
		_sanitize_experiment_name(str(walk["name"]))
	]
	var file := FileAccess.open(debug_path, FileAccess.WRITE)
	if file == null:
		push_error("Could not write debug score result: %s" % debug_path)
		return

	file.store_string(JSON.stringify({
		"experiment": str(config.get("experiment_name", "")),
		"run": str(walk["name"]),
		"generation": generation,
		"target_reached": bool(stats["target_reached"]),
		"fitness": float(stats["best_fitness"]),
		"metrics": metrics,
		"lsystem": {
			"axiom": individual.lsystem.axiom,
			"rules": individual.lsystem.rules,
			"generated_string": individual.lsystem.generated_string,
			"initial_dir": _format_vector2i(individual.initial_dir),
			"initial_edge": int(individual.initial_edge)
		},
		"target_score": _format_score_for_debug(target_score),
		"generated_score": _format_score_for_debug(generated_score)
	}, "\t"))

static func _format_score_for_debug(score: Array) -> Array:
	var formatted: Array = []
	var beat := 0.0
	for event in score:
		var duration := float(event.get("duration_beats", 0.0))
		formatted.append({
			"start": beat,
			"end": beat + duration,
			"duration": duration,
			"anchor": _format_anchor_for_debug(event.get("anchor"))
		})
		beat += duration
	return formatted

static func _format_anchor_for_debug(anchor) -> Dictionary:
	if anchor is TonnetzNode:
		return {
			"type": "node",
			"q": int(anchor.q),
			"r": int(anchor.r),
			"pitch": int(anchor.pitch)
		}
	if anchor is TriangleArea:
		return {
			"type": "triangle",
			"nodes": _format_vector2i_array(anchor.get_node_coords()),
			"pitches": anchor.get_pitches()
		}
	return {}

static func _format_vector2i_array(values: Array) -> Array:
	var formatted: Array = []
	for value in values:
		formatted.append(_format_vector2i(value))
	return formatted

static func _format_vector2i(value: Vector2i) -> Array:
	return [value.x, value.y]

static func _get_score_duration(score: Array) -> float:
	var duration := 0.0
	for event in score:
		duration += float(event.get("duration_beats", 0.0))
	return duration

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
			"parent_selection": str(experiment["selection_name"]),
			"survival_selection": "best_fitness",
			"survival_type": str(experiment["survival_type_name"]),
			"initial_population": str(experiment["initial_population_name"]),
			"comparison": str(experiment["comparison_name"]),
			"fitness": str(experiment["fitness_name"]),
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
