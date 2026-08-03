#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -z "${GODOT:-}" ]]; then
	if [[ "$(uname)" == "Darwin" ]]; then
		GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
	else
		GODOT="/scratch/godot4/Godot4_current"
	fi
fi

TARGET_COUNT="${TARGET_COUNT:-1000}"
TARGET_SCORES_PATH="${TARGET_SCORES_PATH:-res://scripts/evolution/experiments/target_scores/random_target_scores.json}"
RESULTS_ROOT="${RESULTS_ROOT:-res://scripts/evolution/experiments/results}"
# Current entry config after short-run probes. Keep this as the shared baseline;
# override individual values per machine/run when testing combination-specific variants.
CROSSOVER_RATE="${CROSSOVER_RATE:-0.3}"
MUTATION_RATE="${MUTATION_RATE:-0.7}"
TOURNAMENT_SIZE="${TOURNAMENT_SIZE:-3}"
PITCH_WEIGHT="${PITCH_WEIGHT:-1.5}"
DISTANCE_WEIGHT="${DISTANCE_WEIGHT:-1.5}"
DURATION_MATCH_WEIGHT="${DURATION_MATCH_WEIGHT:-0.75}"
TOTAL_DURATION_WEIGHT="${TOTAL_DURATION_WEIGHT:-0.5}"
MISSING_WEIGHT="${MISSING_WEIGHT:-2.0}"
EXTRA_WEIGHT="${EXTRA_WEIGHT:-2.0}"
RAW_HOST_ID="${HOST_ID:-${HOSTNAME:-$(hostname)}}"
HOST_ID="${RAW_HOST_ID//[^A-Za-z0-9_.-]/_}"
RUN_ID="${RUN_ID:-$(date +%Y%m%d_%H%M%S)_${HOST_ID}}"
RESULTS_DIR="${RESULTS_DIR:-${RESULTS_ROOT}/${RUN_ID}}"

# Active experiment list.
# Comment out whole blocks to split the full experiment grid across machines.
EXPERIMENTS=(
	# Block 1: mu_plus_lambda + identity_rules
	"tournament_mu_plus_lambda_identity_rules_skip_ahead_comparison_tuple_match"
	"tournament_mu_plus_lambda_identity_rules_skip_ahead_comparison_entry_match"
	"tournament_mu_plus_lambda_identity_rules_skip_ahead_comparison_tonnetz_distance"
	"tournament_mu_plus_lambda_identity_rules_skip_ahead_comparison_pitch_distance"
	"tournament_mu_plus_lambda_identity_rules_beat_based_comparison_tuple_match"
	"tournament_mu_plus_lambda_identity_rules_beat_based_comparison_entry_match"
	"tournament_mu_plus_lambda_identity_rules_beat_based_comparison_tonnetz_distance"
	"tournament_mu_plus_lambda_identity_rules_beat_based_comparison_pitch_distance"
	"tournament_mu_plus_lambda_identity_rules_index_aligned_comparison_tuple_match"
	"tournament_mu_plus_lambda_identity_rules_index_aligned_comparison_entry_match"
	"tournament_mu_plus_lambda_identity_rules_index_aligned_comparison_tonnetz_distance"
	"tournament_mu_plus_lambda_identity_rules_index_aligned_comparison_pitch_distance"

	# Block 2: mu_plus_lambda + random_rules
	# "tournament_mu_plus_lambda_random_rules_skip_ahead_comparison_tuple_match"
	# "tournament_mu_plus_lambda_random_rules_skip_ahead_comparison_entry_match"
	# "tournament_mu_plus_lambda_random_rules_skip_ahead_comparison_tonnetz_distance"
	# "tournament_mu_plus_lambda_random_rules_skip_ahead_comparison_pitch_distance"
	# "tournament_mu_plus_lambda_random_rules_beat_based_comparison_tuple_match"
	# "tournament_mu_plus_lambda_random_rules_beat_based_comparison_entry_match"
	# "tournament_mu_plus_lambda_random_rules_beat_based_comparison_tonnetz_distance"
	# "tournament_mu_plus_lambda_random_rules_beat_based_comparison_pitch_distance"
	# "tournament_mu_plus_lambda_random_rules_index_aligned_comparison_tuple_match"
	# "tournament_mu_plus_lambda_random_rules_index_aligned_comparison_entry_match"
	# "tournament_mu_plus_lambda_random_rules_index_aligned_comparison_tonnetz_distance"
	# "tournament_mu_plus_lambda_random_rules_index_aligned_comparison_pitch_distance"

	# Block 3: mu_comma_lambda + identity_rules
	# "tournament_mu_comma_lambda_identity_rules_skip_ahead_comparison_tuple_match"
	# "tournament_mu_comma_lambda_identity_rules_skip_ahead_comparison_entry_match"
	# "tournament_mu_comma_lambda_identity_rules_skip_ahead_comparison_tonnetz_distance"
	# "tournament_mu_comma_lambda_identity_rules_skip_ahead_comparison_pitch_distance"
	# "tournament_mu_comma_lambda_identity_rules_beat_based_comparison_tuple_match"
	# "tournament_mu_comma_lambda_identity_rules_beat_based_comparison_entry_match"
	# "tournament_mu_comma_lambda_identity_rules_beat_based_comparison_tonnetz_distance"
	# "tournament_mu_comma_lambda_identity_rules_beat_based_comparison_pitch_distance"
	# "tournament_mu_comma_lambda_identity_rules_index_aligned_comparison_tuple_match"
	# "tournament_mu_comma_lambda_identity_rules_index_aligned_comparison_entry_match"
	# "tournament_mu_comma_lambda_identity_rules_index_aligned_comparison_tonnetz_distance"
	# "tournament_mu_comma_lambda_identity_rules_index_aligned_comparison_pitch_distance"

	# Block 4: mu_comma_lambda + random_rules
	# "tournament_mu_comma_lambda_random_rules_skip_ahead_comparison_tuple_match"
	# "tournament_mu_comma_lambda_random_rules_skip_ahead_comparison_entry_match"
	# "tournament_mu_comma_lambda_random_rules_skip_ahead_comparison_tonnetz_distance"
	# "tournament_mu_comma_lambda_random_rules_skip_ahead_comparison_pitch_distance"
	# "tournament_mu_comma_lambda_random_rules_beat_based_comparison_tuple_match"
	# "tournament_mu_comma_lambda_random_rules_beat_based_comparison_entry_match"
	# "tournament_mu_comma_lambda_random_rules_beat_based_comparison_tonnetz_distance"
	# "tournament_mu_comma_lambda_random_rules_beat_based_comparison_pitch_distance"
	# "tournament_mu_comma_lambda_random_rules_index_aligned_comparison_tuple_match"
	# "tournament_mu_comma_lambda_random_rules_index_aligned_comparison_entry_match"
	# "tournament_mu_comma_lambda_random_rules_index_aligned_comparison_tonnetz_distance"
	# "tournament_mu_comma_lambda_random_rules_index_aligned_comparison_pitch_distance"

	# Block 5: mu_plus_lambda + target_step_rules
	# "tournament_mu_plus_lambda_target_step_rules_skip_ahead_comparison_tuple_match"
	# "tournament_mu_plus_lambda_target_step_rules_skip_ahead_comparison_entry_match"
	# "tournament_mu_plus_lambda_target_step_rules_skip_ahead_comparison_tonnetz_distance"
	# "tournament_mu_plus_lambda_target_step_rules_skip_ahead_comparison_pitch_distance"
	# "tournament_mu_plus_lambda_target_step_rules_beat_based_comparison_tuple_match"
	# "tournament_mu_plus_lambda_target_step_rules_beat_based_comparison_entry_match"
	# "tournament_mu_plus_lambda_target_step_rules_beat_based_comparison_tonnetz_distance"
	# "tournament_mu_plus_lambda_target_step_rules_beat_based_comparison_pitch_distance"
	# "tournament_mu_plus_lambda_target_step_rules_index_aligned_comparison_tuple_match"
	# "tournament_mu_plus_lambda_target_step_rules_index_aligned_comparison_entry_match"
	# "tournament_mu_plus_lambda_target_step_rules_index_aligned_comparison_tonnetz_distance"
	# "tournament_mu_plus_lambda_target_step_rules_index_aligned_comparison_pitch_distance"

	# Block 6: mu_comma_lambda + target_step_rules
	# "tournament_mu_comma_lambda_target_step_rules_skip_ahead_comparison_tuple_match"
	# "tournament_mu_comma_lambda_target_step_rules_skip_ahead_comparison_entry_match"
	# "tournament_mu_comma_lambda_target_step_rules_skip_ahead_comparison_tonnetz_distance"
	# "tournament_mu_comma_lambda_target_step_rules_skip_ahead_comparison_pitch_distance"
	# "tournament_mu_comma_lambda_target_step_rules_beat_based_comparison_tuple_match"
	# "tournament_mu_comma_lambda_target_step_rules_beat_based_comparison_entry_match"
	# "tournament_mu_comma_lambda_target_step_rules_beat_based_comparison_tonnetz_distance"
	# "tournament_mu_comma_lambda_target_step_rules_beat_based_comparison_pitch_distance"
	# "tournament_mu_comma_lambda_target_step_rules_index_aligned_comparison_tuple_match"
	# "tournament_mu_comma_lambda_target_step_rules_index_aligned_comparison_entry_match"
	# "tournament_mu_comma_lambda_target_step_rules_index_aligned_comparison_tonnetz_distance"
	# "tournament_mu_comma_lambda_target_step_rules_index_aligned_comparison_pitch_distance"

	#TO DO: test best combination mit tournament size
)

cd "$PROJECT_DIR"

experiment_count=${#EXPERIMENTS[@]}
if [[ "$experiment_count" -eq 0 ]]; then
	echo "No experiments selected."
	exit 1
fi

echo "Running $experiment_count experiment configurations with $TARGET_COUNT targets each."
echo "Crossover rate: $CROSSOVER_RATE"
echo "Mutation rate: $MUTATION_RATE"
echo "Tournament size: $TOURNAMENT_SIZE"
echo "Pitch weight: $PITCH_WEIGHT"
echo "Distance weight: $DISTANCE_WEIGHT"
echo "Duration match weight: $DURATION_MATCH_WEIGHT"
echo "Total duration weight: $TOTAL_DURATION_WEIGHT"
echo "Missing weight: $MISSING_WEIGHT"
echo "Extra weight: $EXTRA_WEIGHT"
echo "Results dir: $RESULTS_DIR"

overall_start_seconds=$(date +%s)
experiment_index=0

for experiment in "${EXPERIMENTS[@]}"; do
	experiment_index=$((experiment_index + 1))
	experiment_start_seconds=$(date +%s)
	echo "[$experiment_index/$experiment_count] Running $experiment"
	"$GODOT" \
		--headless \
		--path "$PROJECT_DIR" \
		--run \
		-- \
		--run-recorded-walk-experiments \
		--experiment "$experiment" \
		--target-count "$TARGET_COUNT" \
		--target-scores "$TARGET_SCORES_PATH" \
		--results-dir "$RESULTS_DIR" \
		--crossover-rate "$CROSSOVER_RATE" \
		--mutation-rate "$MUTATION_RATE" \
		--tournament-size "$TOURNAMENT_SIZE" \
		--pitch-weight "$PITCH_WEIGHT" \
		--distance-weight "$DISTANCE_WEIGHT" \
		--duration-match-weight "$DURATION_MATCH_WEIGHT" \
		--total-duration-weight "$TOTAL_DURATION_WEIGHT" \
		--missing-weight "$MISSING_WEIGHT" \
		--extra-weight "$EXTRA_WEIGHT"
	experiment_end_seconds=$(date +%s)
	experiment_duration_seconds=$((experiment_end_seconds - experiment_start_seconds))
	overall_duration_seconds=$((experiment_end_seconds - overall_start_seconds))
	echo "[$experiment_index/$experiment_count] Finished $experiment in ${experiment_duration_seconds}s. Total elapsed: ${overall_duration_seconds}s."
done
