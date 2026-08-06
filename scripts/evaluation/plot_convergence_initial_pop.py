from __future__ import annotations

import pandas as pd

import matplotlib.pyplot as plt

EVALUATIONS_PER_GENERATION = 1
X_TICK_STEP = 5
INITIAL_POPULATIONS = [
	"identity+target",
	"random",
]


def main() -> None:
	parser = argparse.ArgumentParser(
		description="Plottet die Konvergenz nach Initial-Population."
	)
	parser.add_argument(
		"input",
		type=Path,
		help="Pfad zum Experimentordner oder zu summary_by_generation.csv.",
	)
	args = parser.parse_args()

	summary_path = get_summary_path(
		args.input
	)
	plot_dir = summary_path.parent.parent / "plots"

	plot_dir.mkdir(
		parents=True,
		exist_ok=True,
	)

	data = pd.read_csv(
		summary_path
	)
	data["initial"] = data["variant"].apply(
		format_initial_population
	)
	data = data[
		data["initial"].isin(INITIAL_POPULATIONS)
	].copy()

	if data.empty:
		raise ValueError(
			"Keine Summary-Daten für die Initial-Populationen gefunden."
		)

	data["budget"] = (
		data["generation"]
		* EVALUATIONS_PER_GENERATION
	)

	plot_best_fitness(
		data,
		plot_dir / "convergence_initial_population_fitness.pdf",
	)

	plot_match_rate(
		data,
		plot_dir / "convergence_initial_population_match_rate.pdf",
	)

	print(f"Plots gespeichert in: {plot_dir}")


def get_summary_path(
	input_path: Path,
) -> Path:
	if input_path.is_file():
		return input_path

	return input_path / "summary" / "summary_by_generation.csv"


def format_initial_population(
	value: str,
) -> str:
	value = str(value).lower()

	if "identity_target_direction_rules" in value:
		return "identity+target"

	if "identity_rules_with_target_direction" in value:
		return "identity+target"

	if "random_rules" in value:
		return "random"

	return "unknown"


def plot_best_fitness(
	data: pd.DataFrame,
	path: Path,
) -> None:
	plot_metric(
		data,
		path,
		"best_fitness_mean",
		"Mittlere Best-Fitness pro Run",
	)


def plot_match_rate(
	data: pd.DataFrame,
	path: Path,
) -> None:
	plot_metric(
		data,
		path,
		"match_rate_mean",
		"Mittlere Match-Rate",
	)


def plot_metric(
	data: pd.DataFrame,
	path: Path,
	metric: str,
	ylabel: str,
) -> None:
	if metric not in data.columns:
		raise ValueError(
			f"Die Spalte '{metric}' fehlt in den Summary-Daten."
		)

	for initial in INITIAL_POPULATIONS:
		initial_data = data[
			data["initial"] == initial
		]

		summary = (
			initial_data
			.groupby("generation")[metric]
			.mean()
			.reset_index()
		)

		plt.plot(
			summary["generation"],
			summary[metric],
			label=initial,
		)

	plt.xlabel(
		"Generation"
	)
	plt.ylabel(
		ylabel
	)
	plt.xlim(left=0)
	plt.gca().xaxis.set_major_locator(
		MultipleLocator(X_TICK_STEP)
	)
	plt.ylim(bottom =0)
	plt.legend()
	plt.tight_layout()
	plt.savefig(path)
	plt.close()

if __name__ == "__main__":
	main()
