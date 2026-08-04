from __future__ import annotations

import argparse
import csv
from collections import Counter, defaultdict
from pathlib import Path
from statistics import mean, median


# This script is the current one-stop evaluation pipeline.
# It reads the experiment CSVs from a result directory and writes:
# - processed CSV tables that are easier to inspect or import into a thesis document
# - SVG plots that can be opened without pandas/matplotlib
# - one Markdown report per experiment variant

# These weights must match the active fitness settings used in the experiment.
# They are needed to reconstruct coarse fitness components from the raw CSV.
FITNESS_WEIGHTS = {
	"total_duration_weight": 0.5,
	"missing_weight": 2.0,
	"extra_weight": 2.0,
}

# csv.DictReader reads every CSV value as a string.
# This map says which columns should be converted to int or float immediately.
NUMERIC_COLUMNS = {
	"walk_length": int,
	"generation": int,
	"fitness_evaluations": int,
	"best_fitness": float,
	"mean_fitness": float,
	"worst_fitness": float,
	"match_rate": float,
	"pitch_match_rate": float,
	"mean_tonnetz_distance": float,
	"mean_pitch_distance": float,
	"duration_error_rate": float,
	"total_duration_error": float,
	"missing_beats": float,
	"extra_beats": float,
}

# These metrics are summarized for final runs.
# The first block comes from the raw CSV, the last four are added by this script.
FINAL_METRICS = [
	"best_fitness",
	"improvement",
	"relative_improvement",
	"match_rate",
	"pitch_match_rate",
	"mean_tonnetz_distance",
	"mean_pitch_distance",
	"duration_error_rate",
	"total_duration_error",
	"missing_beats",
	"extra_beats",
	"event_mismatch_penalty",
	"duration_penalty",
	"missing_penalty",
	"extra_penalty",
]


def main() -> None:
	# The script accepts either:
	# - a result directory with a raw/ subfolder
	# - the raw/ directory itself
	# - a single CSV file
	parser = argparse.ArgumentParser(
		description="Summarize evolutionary experiment result CSV files."
	)
	parser.add_argument(
		"input",
		type=Path,
		help="Result directory, raw directory, or one CSV file.",
	)
	args = parser.parse_args()

	input_path = args.input
	output_root = get_output_root(input_path)

	# Load all rows first. Each row is one generation of one run.
	rows = read_results(input_path)
	# Add derived penalty columns before grouping, so all later summaries can use them.
	add_fitness_components(rows)
	# A result folder can contain multiple experiment CSVs.
	# Each variant gets its own processed/ and plots/ subfolder to avoid overwrites.
	variant_rows = group_rows_by_value(rows, "variant")

	for variant, rows_for_variant in variant_rows.items():
		# Variant names come from filenames and are long but filesystem-safe.
		variant_directory_name = safe_path_name(variant)
		processed_dir = output_root / "processed" / variant_directory_name
		plot_dir = output_root / "plots" / variant_directory_name
		processed_dir.mkdir(parents=True, exist_ok=True)
		plot_dir.mkdir(parents=True, exist_ok=True)

		# All CSV summaries, plots, and the Markdown report for this variant are
		# produced together so they are based on exactly the same input rows.
		write_variant_outputs(
			rows_for_variant,
			processed_dir,
			plot_dir,
		)

		print(f"Variant: {variant}")
		print(f"Rows: {len(rows_for_variant)}")
		print(f"Runs: {len(get_final_rows(rows_for_variant))}")
		print(f"Report: {processed_dir / 'report.md'}")

	if len(variant_rows) > 1:
		# If a result directory contains several variants, also write comparison
		# tables that put the variants next to each other.
		write_comparison_outputs(
			rows,
			output_root / "processed" / "comparison",
		)
		print(f"Comparison: {output_root / 'processed' / 'comparison'}")


def write_variant_outputs(
	rows: list[dict],
	processed_dir: Path,
	plot_dir: Path,
) -> None:
	# final_rows has one row per run: the last logged generation of that run.
	final_rows = get_final_rows(rows)
	# generation_summary is the source table for the convergence/budget plot.
	generation_summary = summarize_generations(rows)
	# anchor_summary compares node targets and triangle targets.
	anchor_summary = summarize_final_groups(final_rows, ["variant", "anchor_type"])
	# length_summary is used to show how final fitness changes with target length.
	length_summary = summarize_final_groups(final_rows, ["variant", "anchor_type", "walk_length"])
	# component_summary explains which coarse terms contributed to final fitness.
	component_summary = summarize_components(final_rows)
	# top_bottom_rows makes it easy to inspect unusually good or bad cases.
	top_bottom_rows = get_top_bottom_rows(final_rows, 20)

	# Processed CSVs are written first because they are the tabular basis for
	# checking and reusing the analysis.
	write_csv(processed_dir / "final_runs.csv", final_rows)
	write_csv(processed_dir / "summary_by_generation.csv", generation_summary)
	write_csv(processed_dir / "summary_by_anchor.csv", anchor_summary)
	write_csv(processed_dir / "summary_by_walk_length.csv", length_summary)
	write_csv(processed_dir / "summary_by_fitness_component.csv", component_summary)
	write_csv(processed_dir / "top_bottom_runs.csv", top_bottom_rows)
	# SVG plots are generated without matplotlib so the script works with the
	# system Python and does not depend on font caches.
	write_fitness_budget_plot(
		plot_dir / "fitness_vs_budget.svg",
		generation_summary,
	)
	write_fitness_length_plot(
		plot_dir / "final_fitness_by_target_length.svg",
		final_rows,
		length_summary,
	)
	write_component_plot(
		plot_dir / "final_fitness_components_by_anchor.svg",
		component_summary,
	)
	# The report is a short human-readable overview of the most important tables.
	write_report(
		processed_dir / "report.md",
		rows,
		final_rows,
		anchor_summary,
		component_summary,
		top_bottom_rows,
	)


def write_comparison_outputs(
	rows: list[dict],
	processed_dir: Path,
) -> None:
	# Comparison tables use only final rows, because the first question is:
	# which variant produced better final solutions?
	processed_dir.mkdir(parents=True, exist_ok=True)
	final_rows = get_final_rows(rows)

	# One row per variant: best overview for the thesis.
	variant_summary = summarize_final_groups(final_rows, ["variant"])
	# One row per variant and anchor type: shows node/triangle differences.
	variant_anchor_summary = summarize_final_groups(final_rows, ["variant", "anchor_type"])
	# One row per variant, anchor type, and target length: shows length effects.
	variant_length_summary = summarize_final_groups(final_rows, ["variant", "anchor_type", "walk_length"])
	# A compact hit table for the direct question: did a variant reach targets?
	target_reached_summary = summarize_target_reached(final_rows)

	write_csv(processed_dir / "variant_summary.csv", variant_summary)
	write_csv(processed_dir / "variant_summary_by_anchor.csv", variant_anchor_summary)
	write_csv(processed_dir / "variant_summary_by_length.csv", variant_length_summary)
	write_csv(processed_dir / "target_reached_by_variant.csv", target_reached_summary)
	write_comparison_report(
		processed_dir / "report.md",
		variant_summary,
		variant_anchor_summary,
		target_reached_summary,
	)


def read_results(input_path: Path) -> list[dict]:
	# Resolve the user's input path into one or more CSV files.
	files = get_input_files(input_path)
	rows: list[dict] = []

	for file in files:
		with file.open(newline="") as csv_file:
			reader = csv.DictReader(csv_file)
			for row in reader:
				# Older result files may not contain a variant column.
				# In that case the experiment variant is reconstructed from the filename.
				if "variant" not in row:
					row["variant"] = variant_from_filename(file)
				# Convert known numeric columns once at the boundary.
				# Everything downstream can then use normal numeric operations.
				for column, column_type in NUMERIC_COLUMNS.items():
					if column in row and row[column] != "":
						row[column] = column_type(row[column])
				# Booleans also arrive as strings from CSV.
				if "target_reached" in row:
					row["target_reached"] = str(row["target_reached"]).lower() == "true"
				rows.append(row)

	if not rows:
		raise ValueError(f"No result rows found in {input_path}")

	return rows


def add_fitness_components(rows: list[dict]) -> None:
	# The raw CSV stores final fitness and diagnostic comparison values.
	# It does not store every internal fitness term directly, so the primary
	# penalty is reconstructed as the remaining part after known weighted terms.
	for row in rows:
		variant = str(row.get("variant", ""))
		duration_penalty = 0.0
		missing_penalty = (
			float(row.get("missing_beats", 0.0))
			* FITNESS_WEIGHTS["missing_weight"]
		)
		extra_penalty = (
			float(row.get("extra_beats", 0.0))
			* FITNESS_WEIGHTS["extra_weight"]
		)
		# Current tuple-wise and entry-wise fitness use missing/extra penalties,
		# but no additional total-duration penalty.
		if "tonnetz_distance" in variant or "pitch_distance" in variant:
			# Current distance fitness uses distance plus total-duration penalty.
			# Missing and extra beats remain useful diagnostics, but are not part
			# of this fitness value anymore.
			duration_penalty = (
				float(row.get("total_duration_error", 0.0))
				* FITNESS_WEIGHTS["total_duration_weight"]
			)
			missing_penalty = 0.0
			extra_penalty = 0.0
		elif "tuple_wise_fitness" not in variant and "entry_wise_fitness" not in variant:
			# Legacy tuple_match/entry_match result folders used total-duration
			# as an extra fitness term, so keep old reports interpretable.
			duration_penalty = (
				float(row.get("total_duration_error", 0.0))
				* FITNESS_WEIGHTS["total_duration_weight"]
			)
		event_mismatch_penalty = (
			float(row["best_fitness"])
			- duration_penalty
			- missing_penalty
			- extra_penalty
		)
		# Add the derived columns directly to the row dict.
		row["duration_penalty"] = duration_penalty
		row["missing_penalty"] = missing_penalty
		row["extra_penalty"] = extra_penalty
		# Clamp tiny negative values that can happen through floating-point rounding.
		row["event_mismatch_penalty"] = max(0.0, event_mismatch_penalty)


def get_input_files(input_path: Path) -> list[Path]:
	# Single-file mode: summarize exactly this CSV.
	if input_path.is_file():
		return [input_path]

	# Result-directory mode: prefer the raw/ subdirectory when it exists.
	raw_dir = input_path / "raw"
	if raw_dir.is_dir():
		input_path = raw_dir

	# At this point input_path should be a directory full of raw CSV files.
	files = sorted(input_path.glob("*.csv"))
	if not files:
		raise FileNotFoundError(f"No CSV files found in {input_path}")

	return files


def get_output_root(input_path: Path) -> Path:
	# Outputs should live in the result directory, not inside raw/.
	# Examples:
	# - result_dir                         -> result_dir
	# - result_dir/raw                     -> result_dir
	# - result_dir/raw/evolution_...csv    -> result_dir
	# - some/standalone.csv                -> some
	if input_path.is_dir():
		if input_path.name == "raw":
			return input_path.parent
		return input_path
	if input_path.parent.name == "raw":
		return input_path.parent.parent
	return input_path.parent


def variant_from_filename(input_file: Path) -> str:
	# ExperimentRunner writes files as evolution_results_<variant>.csv.
	# The prefix is useful for files, but too noisy for plot/report titles.
	name = input_file.stem
	prefix = "evolution_results_"
	if name.startswith(prefix):
		return name[len(prefix):]
	return name


def get_final_rows(rows: list[dict]) -> list[dict]:
	# A "run" is one target score evaluated under one variant.
	# We group by variant as well so different experiments with the same run name
	# do not get mixed together.
	groups: dict[tuple[str, str], list[dict]] = defaultdict(list)
	for row in rows:
		groups[(str(row["variant"]), str(row["run"]))].append(row)

	final_rows: list[dict] = []
	for (_, _), run_rows in sorted(groups.items()):
		# The last generation is the final result for this run.
		run_rows = sorted(run_rows, key=lambda row: int(row["generation"]))
		first = run_rows[0]
		final = dict(run_rows[-1])
		start_best = float(first["best_fitness"])
		final_best = float(final["best_fitness"])
		# Keep both the starting and final values so improvement can be reported.
		final["start_best_fitness"] = start_best
		final["final_generation"] = int(final["generation"])
		final["improvement"] = start_best - final_best
		final["relative_improvement"] = (
			final["improvement"] / start_best
			if start_best > 0.0
			else 0.0
		)
		final_rows.append(final)

	return final_rows


def summarize_generations(rows: list[dict]) -> list[dict]:
	# This summary keeps the time/budget dimension.
	# It answers: how does best_fitness evolve over generations/evaluations?
	groups: dict[tuple[str, str, int], list[dict]] = defaultdict(list)
	for row in rows:
		key = (
			str(row["variant"]),
			str(row["anchor_type"]),
			int(row["generation"]),
		)
		groups[key].append(row)

	summary: list[dict] = []
	for (variant, anchor_type, generation), group_rows in sorted(groups.items()):
		best_values = [float(row["best_fitness"]) for row in group_rows]
		summary.append({
			"variant": variant,
			"anchor_type": anchor_type,
			"generation": generation,
			"runs": len(group_rows),
			# Node and triangle have slightly different initial population sizes.
			# Median keeps one representative budget value for this group/generation.
			"fitness_evaluations": median([
				int(row["fitness_evaluations"])
				for row in group_rows
			]),
			# Store min/median/quartiles/max so the plot can show both typical
			# behavior and the best observed run.
			"best_fitness_min": min(best_values),
			"best_fitness_q25": quantile(best_values, 0.25),
			"best_fitness_median": median(best_values),
			"best_fitness_mean": mean(best_values),
			"best_fitness_q75": quantile(best_values, 0.75),
			"best_fitness_max": max(best_values),
		})

	return summary


def summarize_final_groups(rows: list[dict], group_columns: list[str]) -> list[dict]:
	# This is a generic helper for final-run summaries.
	# Example group_columns:
	# - ["variant", "anchor_type"] compares node vs triangle
	# - ["variant", "anchor_type", "walk_length"] compares target lengths
	groups: dict[tuple, list[dict]] = defaultdict(list)
	for row in rows:
		groups[tuple(row[column] for column in group_columns)].append(row)

	summary: list[dict] = []
	for key, group_rows in sorted(groups.items()):
		# Rebuild the group identifiers as columns in the output CSV.
		summary_row = dict(zip(group_columns, key))
		summary_row["runs"] = len(group_rows)
		# target_reached is stored as a count, not a percentage.
		# That makes it easy to see whether there was any exact hit.
		summary_row["target_reached"] = sum(
			1
			for row in group_rows
			if bool(row.get("target_reached", False))
		)
		for metric in FINAL_METRICS:
			if metric in group_rows[0]:
				values = [float(row[metric]) for row in group_rows]
				# For each metric, write robust distribution statistics.
				# Median is the main "typical result"; q25/q75 describe spread.
				summary_row[f"{metric}_min"] = min(values)
				summary_row[f"{metric}_q25"] = quantile(values, 0.25)
				summary_row[f"{metric}_median"] = median(values)
				summary_row[f"{metric}_mean"] = mean(values)
				summary_row[f"{metric}_q75"] = quantile(values, 0.75)
				summary_row[f"{metric}_max"] = max(values)
		summary.append(summary_row)

	return summary


def summarize_components(rows: list[dict]) -> list[dict]:
	# This summary explains the coarse penalty parts that make up final fitness.
	# For distance fitness variants, the primary penalty is the distance term.
	groups: dict[tuple[str, str], list[dict]] = defaultdict(list)
	for row in rows:
		groups[(str(row["variant"]), str(row["anchor_type"]))].append(row)

	# These names match the derived columns from add_fitness_components().
	components = [
		"event_mismatch_penalty",
		"duration_penalty",
		"missing_penalty",
		"extra_penalty",
	]
	summary: list[dict] = []
	for (variant, anchor_type), group_rows in sorted(groups.items()):
		# The component share is measured against the mean final fitness.
		total_fitness = mean([float(row["best_fitness"]) for row in group_rows])
		for component in components:
			values = [float(row[component]) for row in group_rows]
			component_mean = mean(values)
			summary.append({
				"variant": variant,
				"anchor_type": anchor_type,
				"component": component,
				"runs": len(group_rows),
				"mean": component_mean,
				"median": median(values),
				"share_of_mean_fitness": (
					component_mean / total_fitness
					if total_fitness > 0.0
					else 0.0
				),
			})

	return summary


def summarize_target_reached(rows: list[dict]) -> list[dict]:
	# Target reached is useful enough to get its own compact comparison table.
	# It is grouped by variant and anchor type so node/triangle behavior is visible.
	groups: dict[tuple[str, str], list[dict]] = defaultdict(list)
	for row in rows:
		groups[(str(row["variant"]), str(row["anchor_type"]))].append(row)

	summary: list[dict] = []
	for (variant, anchor_type), group_rows in sorted(groups.items()):
		reached = sum(
			1
			for row in group_rows
			if bool(row.get("target_reached", False))
		)
		runs = len(group_rows)
		summary.append({
			"variant": variant,
			"anchor_type": anchor_type,
			"runs": runs,
			"target_reached": reached,
			"target_reached_rate": reached / runs if runs > 0 else 0.0,
		})

	return summary


def get_top_bottom_rows(rows: list[dict], count: int) -> list[dict]:
	# Sort final runs by final best_fitness.
	# Lower fitness is better, so the first rows are the best cases.
	sorted_rows = sorted(rows, key=lambda row: float(row["best_fitness"]))
	result: list[dict] = []
	for label, selected_rows in [
		("best", sorted_rows[:count]),
		("worst", list(reversed(sorted_rows[-count:]))),
	]:
		for row in selected_rows:
			# Copy the row before adding rank_group so the original final_rows stay clean.
			output_row = dict(row)
			output_row["rank_group"] = label
			result.append(output_row)
	return result


def group_rows_by_value(rows: list[dict], column: str) -> dict[str, list[dict]]:
	# Small grouping helper for splitting one result directory by experiment variant.
	groups: dict[str, list[dict]] = defaultdict(list)
	for row in rows:
		groups[str(row[column])].append(row)
	return dict(sorted(groups.items()))


def safe_path_name(value: str) -> str:
	# Keep generated output folders predictable and shell-friendly.
	# Current variant names are already safe, but this also protects future names.
	result = []
	for character in value.lower():
		if character.isalnum() or character in ["_", "-"]:
			result.append(character)
		else:
			result.append("_")
	return "".join(result).strip("_")


def write_csv(path: Path, rows: list[dict]) -> None:
	# Empty tables are skipped instead of creating headerless files.
	if not rows:
		return

	fieldnames: list[str] = []
	seen = set()
	# Preserve the first-seen column order.
	# This is nicer to inspect than sorted keys because identifiers stay first.
	for row in rows:
		for key in row.keys():
			if key not in seen:
				fieldnames.append(key)
				seen.add(key)

	with path.open("w", newline="") as csv_file:
		writer = csv.DictWriter(csv_file, fieldnames=fieldnames)
		writer.writeheader()
		writer.writerows(rows)


def write_report(
	path: Path,
	rows: list[dict],
	final_rows: list[dict],
	anchor_summary: list[dict],
	component_summary: list[dict],
	top_bottom_rows: list[dict],
) -> None:
	# The report is deliberately redundant with the CSVs.
	# It gives a quick first read without opening a spreadsheet.
	run_counts = Counter(row["anchor_type"] for row in final_rows)
	generation_counts = Counter(int(row["final_generation"]) for row in final_rows)
	final_fitness = [float(row["best_fitness"]) for row in final_rows]
	improvements = [float(row["improvement"]) for row in final_rows]
	target_reached = sum(
		1
		for row in final_rows
		if bool(row.get("target_reached", False))
	)

	lines = [
		"# Experiment Report",
		"",
		f"- Data rows: {len(rows)}",
		f"- Runs: {len(final_rows)}",
		f"- Anchor types: {format_counter(run_counts)}",
		f"- Final generation counts: {format_counter(generation_counts)}",
		f"- Final best fitness: min {min(final_fitness):.4g}, median {median(final_fitness):.4g}, mean {mean(final_fitness):.4g}, max {max(final_fitness):.4g}",
		f"- Improvement: min {min(improvements):.4g}, median {median(improvements):.4g}, mean {mean(improvements):.4g}, max {max(improvements):.4g}",
		f"- Target reached: {target_reached}/{len(final_rows)}",
		"- Fitness components: primary mismatch/distance is the residual after explicit weighted penalties.",
		"- Tuple-wise fitness penalizes a tuple when pitch or duration does not match.",
		"",
		"## Anchor Summary",
		"",
		"| Variant | Anchor | Runs | Final fitness median | Final fitness mean | Improvement median | Match-rate median |",
		"| --- | --- | ---: | ---: | ---: | ---: | ---: |",
	]

	for row in anchor_summary:
		# One compact table row per anchor type.
		lines.append(
			"| {variant} | {anchor_type} | {runs} | {fitness_median:.4g} | {fitness_mean:.4g} | {improvement_median:.4g} | {match_median:.4g} |".format(
				variant=row["variant"],
				anchor_type=row["anchor_type"],
				runs=row["runs"],
				fitness_median=float(row["best_fitness_median"]),
				fitness_mean=float(row["best_fitness_mean"]),
				improvement_median=float(row["improvement_median"]),
				match_median=float(row["match_rate_median"]),
			)
		)

	lines.extend([
		"",
		"## Fitness Components",
		"",
		"| Anchor | Component | Mean penalty | Median penalty | Share of mean fitness |",
		"| --- | --- | ---: | ---: | ---: |",
	])
	for row in component_summary:
		# Component percentages explain whether fitness mostly comes from
		# mismatched events, duration, missing beats, or extra beats.
		lines.append(
			"| {anchor_type} | {component} | {mean_value:.4g} | {median_value:.4g} | {share:.1%} |".format(
				anchor_type=row["anchor_type"],
				component=row["component"],
				mean_value=float(row["mean"]),
				median_value=float(row["median"]),
				share=float(row["share_of_mean_fitness"]),
			)
		)

	lines.extend([
		"",
		"## Best Runs",
		"",
		"| Run | Anchor | Length | Fitness | Improvement | Match rate |",
		"| --- | --- | ---: | ---: | ---: | ---: |",
	])
	for row in [row for row in top_bottom_rows if row["rank_group"] == "best"][:10]:
		# Best runs answer "how close did we get anywhere?"
		lines.append(format_run_table_row(row))

	lines.extend([
		"",
		"## Worst Runs",
		"",
		"| Run | Anchor | Length | Fitness | Improvement | Match rate |",
		"| --- | --- | ---: | ---: | ---: | ---: |",
	])
	for row in [row for row in top_bottom_rows if row["rank_group"] == "worst"][:10]:
		# Worst runs reveal hard target scores and possible failure modes.
		lines.append(format_run_table_row(row))

	path.write_text("\n".join(lines) + "\n")


def write_comparison_report(
	path: Path,
	variant_summary: list[dict],
	variant_anchor_summary: list[dict],
	target_reached_summary: list[dict],
) -> None:
	# Short report for comparing variants with the same external metrics.
	lines = [
		"# Variant Comparison",
		"",
		"- Native fitness is the fitness value optimized by each variant. It is useful within one variant, but different fitness functions may have different scales.",
		"- Match-rate, pitch-match-rate, and distances are external beat-based metrics and are better suited for comparing different fitness variants.",
		"",
		"## Overall",
		"",
		"| Variant | Runs | Native fitness median | Match-rate median | Pitch-match median | Tonnetz distance median | Target reached |",
		"| --- | ---: | ---: | ---: | ---: | ---: | ---: |",
	]

	for row in sorted(variant_summary, key=lambda item: str(item["variant"])):
		lines.append(
			"| {variant} | {runs} | {fitness:.4g} | {match_rate:.4g} | {pitch_match_rate:.4g} | {tonnetz_distance:.4g} | {target_reached} |".format(
				variant=row["variant"],
				runs=row["runs"],
				fitness=float(row["best_fitness_median"]),
				match_rate=float(row["match_rate_median"]),
				pitch_match_rate=float(row["pitch_match_rate_median"]),
				tonnetz_distance=float(row["mean_tonnetz_distance_median"]),
				target_reached=row["target_reached"],
			)
		)

	lines.extend([
		"",
		"## By Anchor",
		"",
		"| Variant | Anchor | Runs | Native fitness median | Match-rate median | Pitch-match median | Target reached |",
		"| --- | --- | ---: | ---: | ---: | ---: | ---: |",
	])

	for row in sorted(
		variant_anchor_summary,
		key=lambda item: (str(item["anchor_type"]), str(item["variant"])),
	):
		lines.append(
			"| {variant} | {anchor_type} | {runs} | {fitness:.4g} | {match_rate:.4g} | {pitch_match_rate:.4g} | {target_reached} |".format(
				variant=row["variant"],
				anchor_type=row["anchor_type"],
				runs=row["runs"],
				fitness=float(row["best_fitness_median"]),
				match_rate=float(row["match_rate_median"]),
				pitch_match_rate=float(row["pitch_match_rate_median"]),
				target_reached=row["target_reached"],
			)
		)

	lines.extend([
		"",
		"## Target Reached",
		"",
		"| Variant | Anchor | Runs | Target reached | Rate |",
		"| --- | --- | ---: | ---: | ---: |",
	])

	for row in target_reached_summary:
		lines.append(
			"| {variant} | {anchor_type} | {runs} | {target_reached} | {rate:.2%} |".format(
				variant=row["variant"],
				anchor_type=row["anchor_type"],
				runs=row["runs"],
				target_reached=row["target_reached"],
				rate=float(row["target_reached_rate"]),
			)
		)

	path.write_text("\n".join(lines) + "\n")


def write_fitness_budget_plot(path: Path, rows: list[dict]) -> None:
	# Input rows here come from summary_by_generation, not raw rows.
	# Each row already describes one generation for one anchor type.
	variant = get_single_value(rows, "variant")
	# series maps anchor_type -> points over the evaluation budget.
	series: dict[str, list[tuple[float, float, float, float]]] = defaultdict(list)
	for row in rows:
		label = str(row["anchor_type"])
		series[label].append((
			# x value: evaluation budget
			float(row["fitness_evaluations"]),
			# y value for the main line
			float(row["best_fitness_median"]),
			# y values for the interquartile band
			float(row["best_fitness_q25"]),
			float(row["best_fitness_q75"]),
			# y value for the dashed "best observed run" line
			float(row["best_fitness_min"]),
		))

	# Axis ranges are derived from all anchor-type series together.
	x_values = [
		point[0]
		for points in series.values()
		for point in points
	]
	y_values = [
		point[index]
		for points in series.values()
		for point in points
		for index in [1, 2, 3]
	]
	canvas = SvgCanvas(
		path,
		"Fitness vs. budget",
		920,
		560,
		format_variant_parameters(variant),
	)
	canvas.draw_axes(
		# Start the axis at zero for readability, even though the first logged
		# point is after initial population + generation 0.
		0.0,
		max(x_values),
		min(y_values),
		max(y_values),
		"Fitness evaluations",
		"Best fitness",
		x_ticks=create_budget_ticks(max(x_values)),
	)

	colors = {
		"node": "#2f6f9f",
		"triangle": "#b25545",
	}
	for label, points in sorted(series.items()):
		points = sorted(points)
		color = colors.get(label, "#4f5d75")
		# The filled band shows the middle 50% of runs.
		canvas.draw_band(
			[(point[0], point[2]) for point in points],
			[(point[0], point[3]) for point in points],
			color,
			0.16,
		)
		# Solid line: typical best_fitness, measured as median across runs.
		canvas.draw_line(
			[(point[0], point[1]) for point in points],
			color,
			f"{label} median",
		)
		# Dashed line: best observed run at each budget.
		# If this line reaches 0, at least one run hit the target.
		canvas.draw_line(
			[(point[0], point[4]) for point in points],
			color,
			f"{label} minimum",
			1.4,
			"5 4",
		)

	canvas.finish()


def write_fitness_length_plot(
	path: Path,
	final_rows: list[dict],
	length_summary: list[dict],
) -> None:
	# final_rows supplies individual points.
	# length_summary supplies the median line for each length and anchor type.
	variant = get_single_value(final_rows, "variant")
	x_values = [float(row["walk_length"]) for row in final_rows]
	y_values = [float(row["best_fitness"]) for row in final_rows]
	canvas = SvgCanvas(
		path,
		"Final fitness by target length",
		920,
		560,
		format_variant_parameters(variant),
	)
	canvas.draw_axes(
		# Keep the intended experiment length scale stable across runs.
		5.0,
		20.0,
		min(y_values),
		max(y_values),
		"Target score length",
		"Final best fitness",
	)

	colors = {
		"node": "#2f6f9f",
		"triangle": "#b25545",
	}
	for row in final_rows:
		# One point is one target score/run at its final generation.
		canvas.draw_point(
			float(row["walk_length"]),
			float(row["best_fitness"]),
			colors.get(str(row["anchor_type"]), "#4f5d75"),
			0.26,
		)

	for anchor_type in ["node", "triangle"]:
		# Median line: typical final fitness for each target length.
		points = [
			(
				float(row["walk_length"]),
				float(row["best_fitness_median"]),
			)
			for row in length_summary
			if row["anchor_type"] == anchor_type
		]
		canvas.draw_line(
			sorted(points),
			colors.get(anchor_type, "#4f5d75"),
			f"{anchor_type} median",
			2.6,
		)

	canvas.finish()


def write_component_plot(path: Path, rows: list[dict]) -> None:
	# Input rows here come from summary_by_fitness_component.
	variant = get_single_value(rows, "variant")
	anchors = sorted({str(row["anchor_type"]) for row in rows})
	# The stack order is kept stable so node and triangle bars are comparable.
	components = [
		"event_mismatch_penalty",
		"duration_penalty",
		"missing_penalty",
		"extra_penalty",
	]
	component_labels = {
		"event_mismatch_penalty": "primary mismatch/distance",
		"duration_penalty": "duration",
		"missing_penalty": "missing",
		"extra_penalty": "extra",
	}
	colors = {
		"event_mismatch_penalty": "#526a3f",
		"duration_penalty": "#d09a3f",
		"missing_penalty": "#8a5a99",
		"extra_penalty": "#4d8a8a",
	}
	values = {
		# Look up each component by (anchor type, component name).
		(str(row["anchor_type"]), str(row["component"])): float(row["mean"])
		for row in rows
	}
	totals = [
		# Total bar height is the sum of mean component penalties.
		sum(values.get((anchor, component), 0.0) for component in components)
		for anchor in anchors
	]

	canvas = SvgCanvas(
		path,
		"Final fitness components by anchor",
		920,
		560,
		format_variant_parameters(variant),
	)
	canvas.draw_axes(
		0.0,
		float(len(anchors)),
		0.0,
		max(totals),
		"Anchor type",
		"Mean final fitness contribution",
	)

	bar_width = 0.46
	for index, anchor in enumerate(anchors):
		x_center = index + 0.5
		y_base = 0.0
		for component in components:
			# Stacked bars are drawn segment by segment.
			value = values.get((anchor, component), 0.0)
			canvas.draw_bar_segment(
				x_center,
				bar_width,
				y_base,
				y_base + value,
				colors[component],
			)
			y_base += value
		canvas.draw_x_label(x_center, anchor)

	for component in components:
		# Add one legend entry per component color.
		canvas.add_legend(component_labels[component], colors[component])

	canvas.finish()


class SvgCanvas:
	# Minimal SVG writer for the three plots.
	# This avoids external plotting dependencies and keeps the output reproducible.
	def __init__(
		self,
		path: Path,
		title: str,
		width: int,
		height: int,
		subtitle: str = "",
	) -> None:
		# File path and canvas size.
		self.path = path
		self.title = title
		self.width = width
		self.height = height
		# Plot margins inside the SVG canvas.
		self.left = 88
		self.right = 28
		# Subtitles need a bit more room above the plot area.
		self.top = 72 if subtitle else 52
		self.bottom = 82
		# SVG elements are collected as strings and written at the end.
		self.items = [
			f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
			'<rect width="100%" height="100%" fill="#fbfaf7"/>',
			f'<text x="{width / 2:.1f}" y="28" text-anchor="middle" font-family="Arial, sans-serif" font-size="18" fill="#2b2b2b">{escape_svg(title)}</text>',
		]
		if subtitle:
			self.items.append(f'<text x="{width / 2:.1f}" y="50" text-anchor="middle" font-family="Arial, sans-serif" font-size="12" fill="#555">{escape_svg(subtitle)}</text>')
		# Legend items are deduplicated and drawn in finish().
		self.legend_items: list[tuple[str, str]] = []
		# Axis ranges are filled by draw_axes().
		self.x_min = 0.0
		self.x_max = 1.0
		self.y_min = 0.0
		self.y_max = 1.0

	def draw_axes(
		self,
		x_min: float,
		x_max: float,
		y_min: float,
		y_max: float,
		x_label: str,
		y_label: str,
		x_ticks: list[float] | None = None,
	) -> None:
		# Store axis ranges so later draw_* calls can transform data coordinates
		# into SVG pixel coordinates.
		self.x_min = x_min
		self.x_max = x_max
		# Keep y=0 visible when the data range is entirely above zero.
		self.y_min = min(0.0, y_min)
		self.y_max = y_max if y_max > self.y_min else self.y_min + 1.0
		# Pixel coordinates for the plot rectangle.
		x0 = self.left
		y0 = self.height - self.bottom
		x1 = self.width - self.right
		y1 = self.top
		# Main x/y axes.
		self.items.extend([
			f'<line x1="{x0}" y1="{y0}" x2="{x1}" y2="{y0}" stroke="#333" stroke-width="1"/>',
			f'<line x1="{x0}" y1="{y0}" x2="{x0}" y2="{y1}" stroke="#333" stroke-width="1"/>',
		])
		# If no custom x ticks are given, draw six evenly spaced labels.
		if x_ticks == None:
			x_ticks = [
				self.x_min + (self.x_max - self.x_min) * index / 5.0
				for index in range(6)
			]
		# Draw x-axis tick marks and labels.
		for x_value in x_ticks:
			x = self.scale_x(x_value)
			self.items.append(f'<line x1="{x:.1f}" y1="{y0}" x2="{x:.1f}" y2="{y0 + 5}" stroke="#333" stroke-width="1"/>')
			self.items.append(f'<text x="{x:.1f}" y="{y0 + 24}" text-anchor="middle" font-family="Arial, sans-serif" font-size="11" fill="#333">{format_axis_value(x_value)}</text>')
		# Draw y-axis tick marks, labels, and light horizontal grid lines.
		for index in range(6):
			t = index / 5.0
			y_value = self.y_min + (self.y_max - self.y_min) * t
			y = self.scale_y(y_value)
			self.items.append(f'<line x1="{x0 - 5}" y1="{y:.1f}" x2="{x0}" y2="{y:.1f}" stroke="#333" stroke-width="1"/>')
			self.items.append(f'<line x1="{x0}" y1="{y:.1f}" x2="{x1}" y2="{y:.1f}" stroke="#ddd8ce" stroke-width="1"/>')
			self.items.append(f'<text x="{x0 - 10}" y="{y + 4:.1f}" text-anchor="end" font-family="Arial, sans-serif" font-size="11" fill="#333">{format_axis_value(y_value)}</text>')
		# Axis captions.
		self.items.append(f'<text x="{(x0 + x1) / 2:.1f}" y="{self.height - 24}" text-anchor="middle" font-family="Arial, sans-serif" font-size="13" fill="#333">{escape_svg(x_label)}</text>')
		self.items.append(f'<text x="18" y="{(y0 + y1) / 2:.1f}" text-anchor="middle" transform="rotate(-90 18 {(y0 + y1) / 2:.1f})" font-family="Arial, sans-serif" font-size="13" fill="#333">{escape_svg(y_label)}</text>')

	def draw_band(
		self,
		lower_points: list[tuple[float, float]],
		upper_points: list[tuple[float, float]],
		color: str,
		opacity: float,
	) -> None:
		# A band is one polygon:
		# first the lower curve from left to right, then the upper curve backwards.
		points = [
			f"{self.scale_x(x):.1f},{self.scale_y(y):.1f}"
			for x, y in lower_points
		]
		points.extend([
			f"{self.scale_x(x):.1f},{self.scale_y(y):.1f}"
			for x, y in reversed(upper_points)
		])
		self.items.append(f'<polygon points="{" ".join(points)}" fill="{color}" opacity="{opacity}"/>')

	def draw_line(
		self,
		points: list[tuple[float, float]],
		color: str,
		label: str,
		width: float = 2.2,
		dasharray: str = "",
	) -> None:
		if not points:
			return
		# Build one SVG path with M for the first point and L for all following points.
		path_data = " ".join(
			f"{'M' if index == 0 else 'L'} {self.scale_x(x):.1f} {self.scale_y(y):.1f}"
			for index, (x, y) in enumerate(points)
		)
		dash_attribute = f' stroke-dasharray="{dasharray}"' if dasharray else ""
		self.items.append(f'<path d="{path_data}" fill="none" stroke="{color}" stroke-width="{width}" stroke-linejoin="round" stroke-linecap="round"{dash_attribute}/>')
		self.add_legend(label, color)

	def draw_point(self, x: float, y: float, color: str, opacity: float) -> None:
		# Scatter points use low opacity so overlapping runs become visually denser.
		self.items.append(f'<circle cx="{self.scale_x(x):.1f}" cy="{self.scale_y(y):.1f}" r="2.2" fill="{color}" opacity="{opacity}"/>')

	def draw_bar_segment(
		self,
		x_center: float,
		width: float,
		y0: float,
		y1: float,
		color: str,
	) -> None:
		# Convert a data-space rectangle into an SVG rect.
		# y is inverted because SVG y coordinates grow downward.
		x = self.scale_x(x_center - width / 2.0)
		bar_width = self.scale_x(x_center + width / 2.0) - x
		y = self.scale_y(y1)
		height = self.scale_y(y0) - y
		self.items.append(f'<rect x="{x:.1f}" y="{y:.1f}" width="{bar_width:.1f}" height="{height:.1f}" fill="{color}"/>')

	def draw_x_label(self, x: float, label: str) -> None:
		# Used by the bar chart to put anchor names under the bars.
		self.items.append(f'<text x="{self.scale_x(x):.1f}" y="{self.height - self.bottom + 24}" text-anchor="middle" font-family="Arial, sans-serif" font-size="12" fill="#333">{escape_svg(label)}</text>')

	def add_legend(self, label: str, color: str) -> None:
		# Avoid duplicate legend entries when the same label is drawn more than once.
		if (label, color) not in self.legend_items:
			self.legend_items.append((label, color))

	def scale_x(self, value: float) -> float:
		# Map data x values into the plot rectangle.
		width = self.width - self.left - self.right
		return self.left + (value - self.x_min) / (self.x_max - self.x_min) * width

	def scale_y(self, value: float) -> float:
		# Map data y values into the plot rectangle.
		# SVG y coordinates grow downward, so higher data values get smaller pixels.
		height = self.height - self.top - self.bottom
		return self.height - self.bottom - (value - self.y_min) / (self.y_max - self.y_min) * height

	def finish(self) -> None:
		# Draw the legend near the bottom after all data has registered legend entries.
		for index, (label, color) in enumerate(self.legend_items):
			x = self.left + index * 168
			y = self.height - 52
			self.items.append(f'<rect x="{x}" y="{y}" width="14" height="14" fill="{color}"/>')
			self.items.append(f'<text x="{x + 20}" y="{y + 11}" font-family="Arial, sans-serif" font-size="12" fill="#333">{escape_svg(label)}</text>')
		# Close and write the SVG file.
		self.items.append("</svg>")
		self.path.write_text("\n".join(self.items) + "\n")


def escape_svg(value: str) -> str:
	# Text goes directly into SVG XML, so special XML characters must be escaped.
	return (
		value
		.replace("&", "&amp;")
		.replace("<", "&lt;")
		.replace(">", "&gt;")
	)


def get_single_value(rows: list[dict], column: str) -> str:
	# Plot subtitles assume one variant per plot.
	# If a caller passes mixed rows, say so instead of picking an arbitrary one.
	values = sorted({str(row[column]) for row in rows if column in row})
	if len(values) == 1:
		return values[0]
	if not values:
		return ""
	return "multiple variants"


def format_variant_parameters(variant: str) -> str:
	# Turn long internal variant identifiers into thesis-readable plot subtitles.
	# Match longest names first so compound names like mu_plus_lambda stay whole.
	known_parts = {
		"selection": {
			"tournament": "tournament",
		},
		"survival": {
			"mu_plus_lambda": "mu+lambda",
			"mu_comma_lambda": "mu,lambda",
		},
		"initial": {
			"identity_rules": "identity rules",
			"random_rules": "random rules",
		},
		"comparison": {
			"skip_ahead_comparison": "skip ahead",
			"beat_based_comparison": "beat based",
			"index_aligned_comparison": "index aligned",
		},
		"fitness": {
			"tuple_wise_fitness": "tuple-wise fitness",
			"entry_wise_fitness": "entry-wise fitness",
			"tuple_match": "tuple match (legacy)",
			"entry_match": "entry match (legacy)",
			"tonnetz_distance": "tonnetz distance",
			"pitch_distance": "pitch distance",
		},
	}
	values = {}
	for group_name, parts in known_parts.items():
		for raw_name, label in sorted(parts.items(), key=lambda item: len(item[0]), reverse=True):
			if raw_name in variant:
				values[group_name] = label
				break
	if len(values) == len(known_parts):
		return (
			f"selection={values['selection']}, "
			f"survival={values['survival']}, "
			f"initial={values['initial']}, "
			f"comparison={values['comparison']}, "
			f"fitness={values['fitness']}"
		)
	return variant.replace("_", " ")


def format_axis_value(value: float) -> str:
	# Keep axis labels compact without switching to scientific notation.
	if abs(value) >= 1000.0:
		return f"{value:.0f}"
	if abs(value) >= 10.0:
		return f"{value:.1f}".rstrip("0").rstrip(".")
	return f"{value:.2f}".rstrip("0").rstrip(".")


def create_budget_ticks(max_value: float) -> list[float]:
	# Fitness evaluation budgets are easiest to read in steps of 1000.
	ticks: list[float] = []
	step = 1000.0
	current = 0.0
	while current < max_value:
		ticks.append(current)
		current += step
	# If the real maximum is very close to the last round tick, do not add it.
	# Example: 6042 would visually collide with 6000.
	if max_value - ticks[-1] >= step * 0.2:
		ticks.append(max_value)
	return ticks


def format_run_table_row(row: dict) -> str:
	# Markdown table row for the best/worst run lists.
	return (
		f"| {row['run']} | {row['anchor_type']} | {row['walk_length']} | "
		f"{float(row['best_fitness']):.4g} | {float(row['improvement']):.4g} | "
		f"{float(row['match_rate']):.4g} |"
	)


def format_counter(counter: Counter) -> str:
	# Compact representation for report bullets, e.g. "node=500, triangle=500".
	return ", ".join(
		f"{key}={value}"
		for key, value in sorted(counter.items())
	)


def quantile(values: list[float], q: float) -> float:
	# Linear interpolation quantile.
	# This matches the usual pandas/numpy style closely enough for report tables.
	sorted_values = sorted(values)
	if not sorted_values:
		raise ValueError("Cannot calculate quantile of empty values")
	if len(sorted_values) == 1:
		return sorted_values[0]

	position = (len(sorted_values) - 1) * q
	lower = int(position)
	upper = min(lower + 1, len(sorted_values) - 1)
	fraction = position - lower
	return (
		sorted_values[lower] * (1.0 - fraction)
		+ sorted_values[upper] * fraction
	)


if __name__ == "__main__":
	main()
