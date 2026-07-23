#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"

TARGET_COUNT="${TARGET_COUNT:-1000}"
TARGET_SCORES_PATH="${TARGET_SCORES_PATH:-res://scripts/evolution/experiments/target_scores/random_target_scores.json}"
RESULTS_ROOT="${RESULTS_ROOT:-res://scripts/evolution/experiments/results}"
RUN_ID="${RUN_ID:-$(date +%Y%m%d_%H%M%S)}"
RESULTS_DIR="${RESULTS_DIR:-${RESULTS_ROOT}/${RUN_ID}}"

EXPERIMENTS=(
	"tournament_mu_plus_lambda_skip_ahead_comparison_event_match_default_config"
	"tournament_mu_plus_lambda_skip_ahead_comparison_pitch_match_default_config"
	"tournament_mu_plus_lambda_skip_ahead_comparison_tonnetz_distance_default_config"
	"tournament_mu_plus_lambda_skip_ahead_comparison_pitch_distance_default_config"
)

cd "$PROJECT_DIR"

for experiment in "${EXPERIMENTS[@]}"; do
	echo "Running $experiment"
	"$GODOT" \
		--headless \
		--path "$PROJECT_DIR" \
		-- \
		--run-recorded-walk-experiments \
		--experiment "$experiment" \
		--target-count "$TARGET_COUNT" \
		--target-scores "$TARGET_SCORES_PATH" \
		--results-dir "$RESULTS_DIR"
done
