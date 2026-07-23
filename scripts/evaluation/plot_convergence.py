from pathlib import Path
import os

import matplotlib.pyplot as plt
import pandas as pd


INPUT_PATH = Path(os.environ.get("EXPERIMENT_RESULTS", "data/results.csv"))
OUTPUT_ROOT = INPUT_PATH if INPUT_PATH.is_dir() else Path(".")
PLOT_DIRECTORY = OUTPUT_ROOT / "plots"
PROCESSED_DIRECTORY = OUTPUT_ROOT / "processed"

MAX_GENERATION = 100

REQUIRED_COLUMNS = {
	"variant",
	"run",
	"anchor_type",
	"generation",
	"fitness_evaluations",
	"best_fitness",
}

FINAL_METRICS = [
	"best_fitness",
	"match_rate",
	"pitch_match_rate",
	"mean_tonnetz_distance",
	"mean_pitch_distance",
	"mean_duration_error",
	"total_duration_error",
	"missing_events",
	"extra_events",
]


def complete_run(
	run_data: pd.DataFrame,
	max_generation: int,
) -> pd.DataFrame:
	run_data = (
		run_data
		.sort_values("generation")
		.drop_duplicates(subset="generation", keep="last")
	)
	evaluations_per_generation = int(
		run_data["fitness_evaluations"].iloc[0]
		/ (int(run_data["generation"].iloc[0]) + 1)
	)

	generation_index = pd.RangeIndex(
		start=0,
		stop=max_generation + 1,
		name="generation",
	)

	run_data = (
		run_data
		.set_index("generation")
		.reindex(generation_index)
	)

	for column in FINAL_METRICS:
		if column in run_data.columns:
			run_data[column] = run_data[column].ffill()
	run_data["fitness_evaluations"] = (
		(run_data.index + 1) * evaluations_per_generation
	)

	for column in ["variant", "run", "anchor_type"]:
		run_data[column] = run_data[column].ffill().bfill()

	return run_data.reset_index()


def prepare_data(data: pd.DataFrame) -> pd.DataFrame:
	completed_runs: list[pd.DataFrame] = []

	for _, run_data in data.groupby(
		["variant", "run"],
		sort=False,
	):
		completed_run = complete_run(
			run_data=run_data,
			max_generation=MAX_GENERATION,
		)

		completed_runs.append(completed_run)

	return pd.concat(
		completed_runs,
		ignore_index=True,
	)


def aggregate_walk_data(
	walk_data: pd.DataFrame,
) -> pd.DataFrame:
	summary = (
		walk_data
		.groupby("fitness_evaluations")["best_fitness"]
		.agg(
			median="median",
			q25=lambda values: values.quantile(0.25),
			q75=lambda values: values.quantile(0.75),
			mean="mean",
			minimum="min",
			maximum="max",
			number_of_runs="count",
		)
		.reset_index()
	)

	return summary


def create_plot(
	summary: pd.DataFrame,
	variant: str,
	anchor_type: str,
) -> None:
	figure, axis = plt.subplots(figsize=(8, 4.5))

	axis.plot(
		summary["fitness_evaluations"],
		summary["median"],
		label="Median der besten Fitness",
	)

	axis.fill_between(
		summary["fitness_evaluations"],
		summary["q25"],
		summary["q75"],
		alpha=0.2,
		label="Interquartilsabstand",
	)

	axis.set_xlabel("Fitnessüberprüfungen")
	axis.set_ylabel("Beste Fitness")
	axis.set_title(
		f"Konvergenz: {anchor_type}"
	)

	axis.grid(alpha=0.3)
	axis.legend()

	figure.tight_layout()

	safe_variant = variant.replace("/", "_")
	safe_anchor_type = anchor_type.replace("/", "_")

	output_base = (
		PLOT_DIRECTORY
		/ f"{safe_variant}__{safe_anchor_type}"
	)

	figure.savefig(
		output_base.with_suffix(".pdf"),
		bbox_inches="tight",
	)

	figure.savefig(
		output_base.with_suffix(".png"),
		dpi=300,
		bbox_inches="tight",
	)

	plt.close(figure)

	print(
		f"Plot erstellt: "
		f"{output_base.with_suffix('.pdf')}"
	)


def save_final_metric_summary(prepared_data: pd.DataFrame) -> None:
	final_rows = (
		prepared_data
		.sort_values("generation")
		.groupby(["variant", "run"], sort=False)
		.tail(1)
	)
	summary = (
		final_rows
		.groupby(["variant", "anchor_type"])[FINAL_METRICS]
		.agg(["median", "mean", "std"])
	)
	summary.to_csv(
		PROCESSED_DIRECTORY / "final_metric_summary.csv"
	)


def main() -> None:
	PLOT_DIRECTORY.mkdir(
		parents=True,
		exist_ok=True,
	)

	PROCESSED_DIRECTORY.mkdir(
		parents=True,
		exist_ok=True,
	)

	data = read_results(INPUT_PATH)

	missing_columns = REQUIRED_COLUMNS - set(data.columns)

	if missing_columns:
		raise ValueError(
			f"Fehlende CSV-Spalten: "
			f"{sorted(missing_columns)}"
		)

	prepared_data = prepare_data(data)
	save_final_metric_summary(prepared_data)

	for (variant, anchor_type), walk_data in prepared_data.groupby(
		["variant", "anchor_type"],
		sort=True,
	):
		summary = aggregate_walk_data(walk_data)

		safe_variant = variant.replace("/", "_")
		safe_anchor_type = anchor_type.replace("/", "_")

		summary_file = (
			PROCESSED_DIRECTORY
			/ f"{safe_variant}__{safe_anchor_type}.csv"
		)

		summary.to_csv(
			summary_file,
			index=False,
		)

		create_plot(
			summary=summary,
			variant=variant,
			anchor_type=anchor_type,
		)


def read_results(input_path: Path) -> pd.DataFrame:
	if input_path.is_dir():
		raw_directory = input_path / "raw"
		if raw_directory.is_dir():
			input_path = raw_directory

		files = sorted(input_path.glob("*.csv"))
		if not files:
			raise FileNotFoundError(f"Keine CSV-Dateien gefunden: {input_path}")

		return pd.concat(
			[read_result_file(file) for file in files],
			ignore_index=True,
		)

	return read_result_file(input_path)


def read_result_file(input_file: Path) -> pd.DataFrame:
	data = pd.read_csv(input_file)
	if "variant" not in data.columns:
		data.insert(0, "variant", variant_from_filename(input_file))
	return data


def variant_from_filename(input_file: Path) -> str:
	name = input_file.stem
	prefix = "evolution_results_"
	if name.startswith(prefix):
		return name[len(prefix):]
	return name


if __name__ == "__main__":
	main()
