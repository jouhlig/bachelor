class_name RecordedWalkExperimentHelper
extends RefCounted

# This class helps turn a recorded walk into an experiment.

const EvolutionScript = preload("res://scripts/evolution/evolution.gd")
const ExperimentRunnerScript = preload("res://scripts/evolution/experiments/experiment_runner.gd")
const TargetScoreStoreScript = preload("res://scripts/evolution/experiments/target_score_store.gd")

const RECORDED_WALK_EXPERIMENT_RESULTS_DIR := "res://scripts/evolution/experiments/results"
const RECORDED_WALK_TARGET_SCORES_PATH := "res://scripts/evolution/experiments/target_scores/random_target_scores.json"
const GENERATE_RECORDED_WALK_TARGETS_ARG := "--generate-recorded-walk-targets"
const RUN_RECORDED_WALK_EXPERIMENTS_ARG := "--run-recorded-walk-experiments"
const EXPERIMENT_ARG := "--experiment"
const RESULTS_DIR_ARG := "--results-dir"
const TARGET_SCORES_ARG := "--target-scores"
const TARGET_COUNT_ARG := "--target-count"
const TARGET_START_ARG := "--target-start"
const CROSSOVER_RATE_ARG := "--crossover-rate"
const MUTATION_RATE_ARG := "--mutation-rate"
const TOURNAMENT_SIZE_ARG := "--tournament-size"
const GENERATIONS_ARG := "--generations"
const PITCH_WEIGHT_ARG := "--pitch-weight"
const DISTANCE_WEIGHT_ARG := "--distance-weight"
const DURATION_MATCH_WEIGHT_ARG := "--duration-match-weight"
const TOTAL_DURATION_WEIGHT_ARG := "--total-duration-weight"
const MISSING_WEIGHT_ARG := "--missing-weight"
const EXTRA_WEIGHT_ARG := "--extra-weight"
const DEBUG_FINAL_SCORES_ARG := "--debug-final-scores"
const APPEND_RESULTS_ARG := "--append-results"
const ASYMMETRIC_RECOMBINATION_ARG := "--asymmetric-recombination"
const DEFAULT_TARGET_SCORE_COUNT := 1000

var walk_recorder: WalkRecorder
var builder: TonnetzBuilder
var interpreter

func _init(
	new_walk_recorder: WalkRecorder,
	new_builder: TonnetzBuilder,
	new_interpreter
) -> void:
	walk_recorder = new_walk_recorder
	builder = new_builder
	interpreter = new_interpreter

func run_from_command_line() -> Dictionary:
	var target_args := _get_recorded_walk_target_args()
	if not target_args.is_empty():
		if not bool(target_args["ok"]):
			return {"handled": true, "ok": false}

		return {
			"handled": true,
			"ok": _generate_recorded_walk_targets(
				str(target_args["target_scores_path"]),
				int(target_args["target_count"])
			)
		}

	var experiment_args := _get_recorded_walk_experiment_args()
	if not experiment_args.is_empty():
		if not bool(experiment_args["ok"]):
			return {"handled": true, "ok": false}

		return {
			"handled": true,
			"ok": _run_recorded_walk_experiments(
				str(experiment_args["experiment"]),
				str(experiment_args["results_dir"]),
				str(experiment_args["target_scores_path"]),
				int(experiment_args["target_count"]),
				int(experiment_args["target_start"]),
				float(experiment_args["crossover_rate"]),
				float(experiment_args["mutation_rate"]),
				int(experiment_args["tournament_size"]),
				int(experiment_args["generations"]),
				experiment_args["fitness_weights"],
				bool(experiment_args["debug_final_scores"]),
				bool(experiment_args["append_results"]),
				bool(experiment_args["symmetric_recombination"])
			)
			}

	return {"handled": false, "ok": true}

func _generate_recorded_walk_targets(
	target_scores_path: String,
	target_score_count: int
) -> bool:
	var target_scores := walk_recorder.generate_walks(target_score_count)
	if target_scores.is_empty():
		push_warning("No target scores generated.")
		return false

	TargetScoreStoreScript.save_scores(target_scores_path, target_scores)
	print("Generated ", target_scores.size(), " recorded walk targets at ", target_scores_path, ".")
	return true

func _run_recorded_walk_experiments(
	experiment_name: String,
	results_dir: String,
	target_scores_path: String,
	target_score_count: int,
	target_score_start: int = 0,
	crossover_rate: float = -1.0,
	mutation_rate: float = -1.0,
	tournament_size: int = 0,
	generations: int = 0,
	fitness_weights: Dictionary = {},
	debug_final_scores: bool = false,
	append_results: bool = false,
	symmetric_recombination: bool = true
) -> bool:
	var target_scores := TargetScoreStoreScript.load_scores(
		target_scores_path,
		builder
	)
	if target_score_start > 0 and target_score_start < target_scores.size():
		target_scores = target_scores.slice(target_score_start)
	elif target_score_start >= target_scores.size():
		target_scores = []
	if target_scores.size() > target_score_count:
		target_scores = target_scores.slice(0, target_score_count)
	if target_scores.is_empty():
		target_scores = walk_recorder.generate_walks(target_score_count)
		TargetScoreStoreScript.save_scores(
			target_scores_path,
			target_scores
		)

	if target_scores.is_empty():
		push_warning("No target scores available for experiments.")
		return false

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(results_dir))

	var experiment_config := EvolutionScript.create_default_config()
	if crossover_rate >= 0.0:
		experiment_config["crossover_rate"] = crossover_rate
	if mutation_rate >= 0.0:
		experiment_config["mutation_rate"] = mutation_rate
	if tournament_size > 0:
		experiment_config["tournament_size"] = tournament_size
	if generations > 0:
		experiment_config["generations"] = generations
	for key in fitness_weights.keys():
		experiment_config["fitness_weights"][key] = fitness_weights[key]
	experiment_config["debug_final_scores"] = debug_final_scores
	experiment_config["target_scores_path"] = target_scores_path
	experiment_config["target_score_start"] = target_score_start
	experiment_config["target_score_count"] = target_scores.size()
	experiment_config["append_results"] = append_results
	experiment_config["symmetric_recombination"] = symmetric_recombination
	print("Running recorded walk experiment ", experiment_name, " for ", target_scores.size(), " target scores starting at ", target_score_start, ".")

	if experiment_name == "all":
		ExperimentRunnerScript.test_all_combinations(
			target_scores,
			interpreter,
			experiment_config,
			results_dir
		)
	else:
		ExperimentRunnerScript.test_one_combination(
			target_scores,
			experiment_name,
			interpreter,
			experiment_config,
			results_dir
		)

	print("Recorded walk experiments finished.")
	return true

func _get_recorded_walk_target_args() -> Dictionary:
	var args := OS.get_cmdline_user_args()
	if not args.has(GENERATE_RECORDED_WALK_TARGETS_ARG):
		return {}

	return _get_recorded_walk_target_options(args, GENERATE_RECORDED_WALK_TARGETS_ARG)

func _get_recorded_walk_experiment_args() -> Dictionary:
	var args := OS.get_cmdline_user_args()
	if not args.has(RUN_RECORDED_WALK_EXPERIMENTS_ARG):
		return {}

	var experiment_name := ExperimentRunnerScript.DEFAULT_EXPERIMENT_COMBINATION_NAME
	var results_dir := RECORDED_WALK_EXPERIMENT_RESULTS_DIR
	var target_scores_path := RECORDED_WALK_TARGET_SCORES_PATH
	var target_count := DEFAULT_TARGET_SCORE_COUNT
	var target_start := 0
	var crossover_rate := -1.0
	var mutation_rate := -1.0
	var tournament_size := 0
	var generations := 0
	var fitness_weights := {}
	var debug_final_scores := false
	var append_results := false
	var symmetric_recombination := true
	var index := 0

	while index < args.size():
		var arg := str(args[index])
		if arg == RUN_RECORDED_WALK_EXPERIMENTS_ARG:
			index += 1
		elif arg == EXPERIMENT_ARG:
			experiment_name = _get_arg_value(args, index)
			index += 2
		elif arg == RESULTS_DIR_ARG:
			results_dir = _get_arg_value(args, index)
			index += 2
		elif arg == TARGET_SCORES_ARG:
			target_scores_path = _get_arg_value(args, index)
			index += 2
		elif arg == TARGET_COUNT_ARG:
			target_count = int(_get_arg_value(args, index))
			index += 2
		elif arg == TARGET_START_ARG:
			target_start = int(_get_arg_value(args, index))
			index += 2
		elif arg == CROSSOVER_RATE_ARG:
			crossover_rate = float(_get_arg_value(args, index))
			index += 2
		elif arg == MUTATION_RATE_ARG:
			mutation_rate = float(_get_arg_value(args, index))
			index += 2
		elif arg == TOURNAMENT_SIZE_ARG:
			tournament_size = int(_get_arg_value(args, index))
			index += 2
		elif arg == GENERATIONS_ARG:
			generations = int(_get_arg_value(args, index))
			index += 2
		elif arg == PITCH_WEIGHT_ARG:
			fitness_weights["pitch_weight"] = float(_get_arg_value(args, index))
			index += 2
		elif arg == DISTANCE_WEIGHT_ARG:
			fitness_weights["distance_weight"] = float(_get_arg_value(args, index))
			index += 2
		elif arg == DURATION_MATCH_WEIGHT_ARG:
			fitness_weights["duration_match_weight"] = float(_get_arg_value(args, index))
			index += 2
		elif arg == TOTAL_DURATION_WEIGHT_ARG:
			fitness_weights["total_duration_weight"] = float(_get_arg_value(args, index))
			index += 2
		elif arg == MISSING_WEIGHT_ARG:
			fitness_weights["missing_weight"] = float(_get_arg_value(args, index))
			index += 2
		elif arg == EXTRA_WEIGHT_ARG:
			fitness_weights["extra_weight"] = float(_get_arg_value(args, index))
			index += 2
		elif arg == DEBUG_FINAL_SCORES_ARG:
			debug_final_scores = true
			index += 1
		elif arg == APPEND_RESULTS_ARG:
			append_results = true
			index += 1
		elif arg == ASYMMETRIC_RECOMBINATION_ARG:
			symmetric_recombination = false
			index += 1
		else:
			push_error("Unknown experiment argument: %s" % arg)
			return {"ok": false}

	if results_dir.is_empty():
		push_error("Experiment results dir is empty.")
		return {"ok": false}

	if target_scores_path.is_empty():
		push_error("Target scores path is empty.")
		return {"ok": false}

	if target_count <= 0:
		push_error("Target score count must be greater than 0.")
		return {"ok": false}

	if target_start < 0:
		push_error("Target score start must not be negative.")
		return {"ok": false}

	if generations < 0:
		push_error("Generations must not be negative.")
		return {"ok": false}

	if experiment_name != "all" and not ExperimentRunnerScript.get_combination_names().has(experiment_name):
		push_error("Unknown experiment combination: %s" % experiment_name)
		print("Available combinations: ", ", ".join(ExperimentRunnerScript.get_combination_names()))
		return {"ok": false}

	return {
		"ok": true,
		"experiment": experiment_name,
		"results_dir": results_dir,
		"target_scores_path": target_scores_path,
		"target_count": target_count,
		"target_start": target_start,
		"crossover_rate": crossover_rate,
		"mutation_rate": mutation_rate,
		"tournament_size": tournament_size,
		"generations": generations,
		"fitness_weights": fitness_weights,
		"debug_final_scores": debug_final_scores,
		"append_results": append_results,
		"symmetric_recombination": symmetric_recombination
	}

func _get_recorded_walk_target_options(
	args: PackedStringArray,
	mode_arg: String
) -> Dictionary:
	var target_scores_path := RECORDED_WALK_TARGET_SCORES_PATH
	var target_count := DEFAULT_TARGET_SCORE_COUNT
	var index := 0

	while index < args.size():
		var arg := str(args[index])
		if arg == mode_arg:
			index += 1
		elif arg == TARGET_SCORES_ARG:
			target_scores_path = _get_arg_value(args, index)
			index += 2
		elif arg == TARGET_COUNT_ARG:
			target_count = int(_get_arg_value(args, index))
			index += 2
		else:
			push_error("Unknown target generation argument: %s" % arg)
			return {"ok": false}

	if target_scores_path.is_empty():
		push_error("Target scores path is empty.")
		return {"ok": false}

	if target_count <= 0:
		push_error("Target score count must be greater than 0.")
		return {"ok": false}

	return {
		"ok": true,
		"target_scores_path": target_scores_path,
		"target_count": target_count
	}

func _get_arg_value(args: PackedStringArray, index: int) -> String:
	if index + 1 >= args.size():
		push_error("Missing value for argument: %s" % args[index])
		return ""

	return str(args[index + 1])
