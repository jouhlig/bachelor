from __future__ import annotations

import argparse
import json
from pathlib import Path

import pandas as pd


# Diese Spalten werden für die Auswertung verwendet.
# Fehlende Spalten werden einfach ignoriert.
METRICS = [
	"best_fitness",
	"match_rate",
	"pitch_match_rate",
	"duration_match_rate",
	"mean_tonnetz_distance",
	"mean_pitch_distance",
	"duration_error_rate",
	"missing_event_rate",
	"extra_event_rate",
]


def main() -> None:
	parser = argparse.ArgumentParser(
		description="Fasst die Ergebnisse eines EA-Experiments zusammen."
	)
	parser.add_argument(
		"input",
		type=Path,
		help="CSV-Datei oder Ordner mit CSV-Dateien.",
	)
	args = parser.parse_args()

	# Jede Experimentreihe wird getrennt ausgewertet.
	# So werden unterschiedliche Target-Sets nicht miteinander vermischt.
	output_dir = get_output_dir(args.input)
	output_dir.mkdir(parents=True, exist_ok=True)

	data = read_results(args.input)
	data = add_variant_parameters(
		data,
		read_manifest_parameters(args.input),
	)
	final_runs = select_final_generation(data)

	write_csv(final_runs, output_dir / "final_runs.csv")

	variant_summary = summarize(
		final_runs,
		["variant"],
	)
	write_csv(variant_summary, output_dir / "summary_by_variant.csv")

	write_latex_table(
		variant_summary,
		output_dir / "summary_by_variant.tex",
		columns=[
			"survival",
			"initial",
			"comparison",
			"fitness",
			"target_reached_rate",
			"match_rate_mean",
		],
		headers=[
			"Populationsmodell",
			"Initialpopulation",
			"Vergleich",
			"Fitness",
			"Erfolgsrate",
			"Match-Rate",
		],
		caption=(
			"Zusammenfassung der Ergebnisse nach Populationsmodell, "
			"Initialpopulation, Vergleich und Fitness."
		),
		label="tab:summary_by_variant",
		align="llllrr",
	)

	if "anchor_type" in final_runs.columns:
		anchor_summary = summarize(
			final_runs,
			["variant", "anchor_type"],
		)
		write_csv(
			anchor_summary,
			output_dir / "summary_by_variant_and_anchor.csv",
		)

	# summarize by parameters (inital_population, fitness, comparison, survival)
	summary_frames: dict[str, pd.DataFrame] = {}
	for parameter in [
		"initial",
		"fitness",
		"comparison",
		"survival",
	]:
		if parameter not in final_runs.columns:
			continue

		parameter_summary = summarize(
			final_runs,
			[parameter],
		)
		summary_path = output_dir / f"summary_by_{parameter}.csv"
		write_csv(
			parameter_summary,
			summary_path,
		)
		summary_frames[parameter] = pd.read_csv(summary_path)

	# write fitness summary as latex table
	fitness_summary = summary_frames.get("fitness")
	if fitness_summary is not None:
		write_latex_table(
			fitness_summary,
			output_dir / "summary_by_fitness.tex",
			columns=[
				"fitness",
				"target_reached_rate",
				"match_rate_mean",
			],
			headers=[
				"Fitness",
				"Erfolgsrate",
				"Match-Rate",
			],
			caption="Vergleich der Fitnessfunktion.",
			label="tab:fitness_modes",
			align="lrrr",
		)

	# write comparison mode summary as latex table
	comparison_mode_summary = summary_frames.get("comparison")
	if comparison_mode_summary is not None:
		write_latex_table(
			comparison_mode_summary,
			output_dir / "summary_by_comparison_mode.tex",
			columns=[
				"comparison",
				"target_reached_rate",
				"match_rate_mean",
			],
			headers=[
				"Vergleich",
				"Erfolgsrate",
				"Match-Rate",
			],
			caption="Vergleich der Vergleichsmodi.",
			label="tab:comparison_modes",
			align="lrrr",
		)

	# write pop model summary as latex table
	survival_model_summary = summary_frames.get("survival")
	if survival_model_summary is not None:
		write_latex_table(
			survival_model_summary,
			output_dir / "summary_by_population_model.tex",
			columns=[
				"survival",
				"target_reached_rate",
				"match_rate_mean",
			],
			headers=[
				"Populationsmodell",
				"Erfolgsrate",
				"Match-Rate",
			],
			caption="Vergleich der Populationsmodelle.",
			label="tab:population_models",
			align="lrr",
		)

	# write initial population summary as latex table
	initial_population_summary = summary_frames.get("initial")
	if initial_population_summary is not None:
		write_latex_table(
			initial_population_summary,
			output_dir / "summary_by_initial_population.tex",
			columns=[
				"initial",
				"target_reached_rate",
				"match_rate_mean",
			],
			headers=[
				"Initial-Population",
				"Erfolgsrate",
				"Match-Rate",
			],
			caption="Vergleich der Initial-Populationen.",
			label="tab:initial_populations",
			align="lrr",
		)

	filled_data = fill_stopped_runs(data)
	generation_summary = summarize_generations(filled_data)

	# give summary output in terminal
	print(f"Eingelesene Zeilen: {len(data)}")
	print(f"Runs: {len(final_runs)}")
	print(f"Varianten: {final_runs['variant'].nunique()}")
	print(f"Ergebnisse: {output_dir}")

# compare tuple vs entry and tonnetz vs pitch distance (fitness)
def summarize_fitness_mode(
	data: pd.DataFrame,
	fitness_values: list[str],
) -> pd.DataFrame:
	filtered_data = data[
		data["fitness"].isin(fitness_values)
	].copy()

	return summarize(
		filtered_data,
		["fitness"],
	)
#write a latex table and save it
def write_latex_table(
	data: pd.DataFrame,
	path: Path,
	columns: list[str],
	headers: list[str],
	caption: str,
	label: str,
	align: str,
) -> None:
	SHORT_NAMES = {
		"mu,lambda": r"$\mu,\lambda$",
		"mu+lambda": r"$\mu+\lambda$",
		"identity": "Id",
		"identity+target": "Id+Target",
		"random": "Rnd",
		"target-step": "TS",
		"beat-based": "Beat",
		"index-based": "Index",
		"skip-ahead": "Skip",
		"entry-wise": "Entry",
		"tuple-wise": "Tuple",
		"pitch-distance": "Pitch-D.",
		"tonnetz-distance": "Tonnetz-D.",
	}

	table = data[columns].copy()

	with path.open("w", encoding="utf-8") as file:
		file.write("\\begingroup\n")
		file.write("\\small\n")
		file.write(f"\\begin{{longtable}}{{{align}}}\n")
		file.write(f"\\caption{{{caption}}}\n")
		file.write(f"\\label{{{label}}}\\\\\n")
		file.write("\\toprule\n")

		file.write(" & ".join(headers) + " \\\\\n")
		file.write("\\midrule\n")

		for _, row in table.iterrows():
			values = []

			for column in columns:
				value = row[column]

				if column.endswith("_rate"):
					values.append(latex_percent(float(value)))
				elif column.endswith("_mean"):
					values.append(latex_percent(float(value)))
				else:
					values.append(short_name(value, SHORT_NAMES))

			file.write(" & ".join(values) + " \\\\\n")

		file.write("\\bottomrule\n")
		file.write("\\end{longtable}\n")
		file.write("\\endgroup\n")

#helper function to get short names for latex tables
def short_name(value: object, names: dict[str, str]) -> str:
	text = str(value)

	if text in names:
		return names[text]

	return escape_latex(text)

#helper function to write percent without messing up latex
def latex_percent(value: float) -> str:
	return f"{value * 100:.1f}\\%"	

#helper function to escsape special characters in latex
def escape_latex(value: object) -> str:
	text = str(value)

	replacements = {
		"&": "\\&",
		"%": "\\%",
		"_": "\\_",
		"#": "\\#",
	}

	for old, new in replacements.items():
		text = text.replace(old, new)

	return text	
	
def read_results(input_path: Path) -> pd.DataFrame:
	files = find_csv_files(input_path)
	frames = []

	for file in files:
		frame = pd.read_csv(file)

		if "variant" not in frame.columns:
			frame["variant"] = variant_from_filename(file)

		frames.append(frame)

	if not frames:
		raise ValueError("Es wurden keine CSV-Daten gefunden.")

	return pd.concat(frames, ignore_index=True)


def find_csv_files(input_path: Path) -> list[Path]:
	if input_path.is_file():
		return [input_path]

	raw_dir = input_path / "raw"
	if raw_dir.is_dir():
		input_path = raw_dir

	files = sorted(input_path.glob("*.csv"))

	if not files:
		raise FileNotFoundError(
			f"Keine CSV-Dateien in {input_path} gefunden."
		)

	return files


def get_output_dir(input_path: Path) -> Path:
	if input_path.is_file():
		base_dir = input_path.parent
	elif input_path.name == "raw":
		base_dir = input_path.parent
	else:
		base_dir = input_path

	return base_dir / "summary"


def variant_from_filename(file: Path) -> str:
	name = file.stem
	prefix = "evolution_results_"

	if name.startswith(prefix):
		return name[len(prefix):]

	return name


def read_manifest_parameters(input_path: Path) -> dict[str, dict[str, str]]:
	manifest_path = get_manifest_path(input_path)

	if manifest_path is None:
		return {}

	manifest = json.loads(manifest_path.read_text())
	parameters = {}
	# get variant parameters from manifest
	for experiment in manifest.get("experiments", []):
		parameters[experiment["name"]] = {
			"parent_selection": format_parent_selection(
				experiment.get("parent_selection", "")
			),
			"survival": format_survival_type(
				experiment.get("survival_type", "")
			),
			"initial": format_initial_population(
				experiment.get("initial_population", "")
			),
			"comparison": format_comparison(
				experiment.get("comparison", "")
			),
			"fitness": format_fitness(
				experiment.get("fitness", "")
			),
		}

	return parameters


def get_manifest_path(input_path: Path) -> Path | None:
	if input_path.is_file():
		candidates = [
			input_path.parent.parent / "manifest.json",
			input_path.parent / "manifest.json",
		]
	elif input_path.name == "raw":
		candidates = [input_path.parent / "manifest.json"]
	else:
		candidates = [input_path / "manifest.json"]

	for candidate in candidates:
		if candidate.exists():
			return candidate

	return None


def add_variant_parameters(
	data: pd.DataFrame,
	manifest_parameters: dict[str, dict[str, str]],
) -> pd.DataFrame:
	data = data.copy()

	data["parent_selection"] = data["variant"].apply(
		lambda value: find_parameter(
			value,
			manifest_parameters,
			"parent_selection",
			format_parent_selection,
		)
	)

	data["survival"] = data["variant"].apply(
		lambda value: find_parameter(
			value,
			manifest_parameters,
			"survival",
			format_survival_type,
		)
	)

	data["initial"] = data["variant"].apply(
		lambda value: find_parameter(
			value,
			manifest_parameters,
			"initial",
			format_initial_population,
		)
	)

	data["comparison"] = data["variant"].apply(
		lambda value: find_parameter(
			value,
			manifest_parameters,
			"comparison",
			format_comparison,
		)
	)

	data["fitness"] = data["variant"].apply(
		lambda value: find_parameter(
			value,
			manifest_parameters,
			"fitness",
			format_fitness,
		)
	)

	return data


def find_parameter(
	value: str,
	manifest_parameters: dict[str, dict[str, str]],
	parameter: str,
	fallback: callable,
) -> str:
	value = str(value)

	if value in manifest_parameters:
		return manifest_parameters[value][parameter]

	return fallback(value)


def format_parent_selection(value: str) -> str:
	return find_name(
		value,
		{
			"uniform_random_with_replacement": "random_parent",
			"random_parent": "random_parent",
			"tournament": "tournament_parent",
		},
	)


def format_survival_type(value: str) -> str:
	return find_name(
		value,
		{
			"mu_plus_lambda": "mu+lambda",
			"mu_comma_lambda": "mu,lambda",
		},
	)


def format_initial_population(value: str) -> str:
	return find_name(
		value,
		{
			"identity_target_direction_rules": "identity+target",
			"identity_rules_with_target_direction": "identity+target",
			"identity_rules": "identity",
			"target_step_rules": "target-step",
			"random_rules": "random",
		},
	)


def format_comparison(value: str) -> str:
	return find_name(
		value,
		{
			"skip_ahead_comparison": "skip-ahead",
			"beat_based_comparison": "beat-based",
			"index_aligned_comparison": "index-based",
		},
	)


def format_fitness(value: str) -> str:
	return find_name(
		value,
		{
			"tuple_wise_fitness": "tuple-wise",
			"entry_wise_fitness": "entry-wise",
			"tuple_match": "tuple-wise",
			"entry_match": "entry-wise",
			"tonnetz_distance": "tonnetz-distance",
			"pitch_distance": "pitch-distance",
		},
	)


def find_name(value: str, names: dict[str, str]) -> str:
	value = str(value).lower()
	for text, result in names.items():
		if text in value:
			return result

	return "unknown"

def select_final_generation(data: pd.DataFrame) -> pd.DataFrame:
	required_columns = ["variant", "run", "generation"]

	for column in required_columns:
		if column not in data.columns:
			raise ValueError(
				f"Die notwendige Spalte '{column}' fehlt."
			)

	sorted_data = data.sort_values(
		["variant", "run", "generation"]
	)

	final_runs = (
		sorted_data
		.groupby(["variant", "run"], as_index=False)
		.tail(1)
		.copy()
	)

	final_runs["final_generation"] = final_runs["generation"]

	return final_runs


def summarize(
	data: pd.DataFrame,
	group_columns: list[str],
) -> pd.DataFrame:
	metrics = [
		metric
		for metric in METRICS
		if metric in data.columns
	]

	grouped = data.groupby(
		group_columns,
		dropna=False,
	)
	summary = grouped.size().reset_index(name="runs")
	if "variant" in group_columns:
		for parameter in [
			"parent_selection",
			"survival",
			"initial",
			"comparison",
			"fitness",
		]:
			if parameter in data.columns:
				values = (
					grouped[parameter]
					.first()
					.reset_index(name=parameter)
				)
				summary = summary.merge(
					values,
					on=group_columns,
				)
	if "target_reached" in data.columns:
		reached = (
			grouped["target_reached"]
			.mean()
			.reset_index(name="target_reached_rate")
		)
		summary = summary.merge(
			reached,
			on=group_columns,
		)

	for metric in metrics:
		metric_summary = (
			grouped[metric]
			.agg(["mean", "median", "std"])
			.reset_index()
			.rename(
				columns={
					"mean": f"{metric}_mean",
					"median": f"{metric}_median",
					"std": f"{metric}_std",
				}
			)
		)

		summary = summary.merge(
			metric_summary,
			on=group_columns,
		)

	return summary

def fill_stopped_runs(data: pd.DataFrame) -> pd.DataFrame:
	max_generation = int(data["generation"].max())

	filled_runs = []

	for (_, _), run_data in data.groupby(["variant", "run"]):
		run_data = run_data.sort_values("generation").copy()

		last_generation = int(run_data["generation"].max())
		last_row = run_data.iloc[-1]

		filled_runs.append(run_data)

		for generation in range(last_generation + 1, max_generation + 1):
			new_row = last_row.copy()
			new_row["generation"] = generation
			filled_runs.append(pd.DataFrame([new_row]))

	return pd.concat(filled_runs, ignore_index=True)

def summarize_generations(data: pd.DataFrame) -> pd.DataFrame:
	if "generation" not in data.columns:
		return pd.DataFrame()

	group_columns = [
		"variant", 
		"generation",
		"fitness",
        "comparison",
		"initial",
        "survival"
	]

	if "anchor_type" in data.columns:
		group_columns.append("anchor_type")

	metrics = [
		metric
		for metric in [
			"best_fitness",
			"match_rate",
			"pitch_match_rate",
		]
		if metric in data.columns
	]

	grouped = data.groupby(
		group_columns,
		dropna=False,
	)

	summary = grouped.size().reset_index(name="runs")

	for metric in metrics:
		metric_summary = (
			grouped[metric]
			.agg(["mean", "median"])
			.reset_index()
			.rename(
				columns={
					"mean": f"{metric}_mean",
					"median": f"{metric}_median",
				}
			)
		)

		summary = summary.merge(
			metric_summary,
			on=group_columns,
		)

	return summary


def write_csv(data: pd.DataFrame, path: Path) -> None:
	if data.empty:
		return

	data.to_csv(
		path,
		index=False,
	)


if __name__ == "__main__":
	main()
