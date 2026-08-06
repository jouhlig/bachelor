from __future__ import annotations

import argparse
from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd


EVALUATIONS_PER_GENERATION = 120


def main() -> None:
	parser = argparse.ArgumentParser(
		description="Plottet die Konvergenz der besten EA-Variante."
	)
	parser.add_argument(
		"input",
		type=Path,
		help="Pfad zum Ordner der zweiten Experimentreihe.",
	)
	args = parser.parse_args()

	experiment_dir = args.input
	raw_dir = experiment_dir / "raw"
	summary_dir = experiment_dir / "summary"
	plot_dir = experiment_dir / "plots"

	plot_dir.mkdir(
		parents=True,
		exist_ok=True,
	)

	variant_summary = pd.read_csv(
		summary_dir / "summary_by_variant.csv"
	)

	best_variant = find_best_variant(
		variant_summary
	)

	raw_data = read_raw_data(
		raw_dir
	)

	variant_data = raw_data[
		raw_data["variant"] == best_variant
	].copy()

	if variant_data.empty:
		raise ValueError(
			f"Keine Rohdaten für Variante '{best_variant}' gefunden."
		)

	variant_data["budget"] = (
		variant_data["generation"]
		* EVALUATIONS_PER_GENERATION
	)

	plot_fitness(
		variant_data,
		plot_dir / "convergence_best_fitness.pdf",
	)

	plot_hit_rate(
		variant_data,
		plot_dir / "convergence_best_hit_rate.pdf",
	)

	print(f"Beste Variante: {best_variant}")
	print(f"Plots gespeichert in: {plot_dir}")


def find_best_variant(
	variant_summary: pd.DataFrame,
) -> str:
	sorted_variants = variant_summary.sort_values(
		[
			"target_reached_rate",
			"match_rate_mean",
		],
		ascending=[
			False,
			False,
		],
	)

	return str(
		sorted_variants.iloc[0]["variant"]
	)


def read_raw_data(
	raw_dir: Path,
) -> pd.DataFrame:
	files = sorted(
		raw_dir.glob("*.csv")
	)

	if not files:
		raise FileNotFoundError(
			f"Keine CSV-Dateien in {raw_dir} gefunden."
		)

	frames = []

	for file in files:
		frame = pd.read_csv(file)

		if "variant" not in frame.columns:
			frame["variant"] = variant_from_filename(
				file
			)

		frames.append(frame)

	return pd.concat(
		frames,
		ignore_index=True,
	)


def variant_from_filename(
	file: Path,
) -> str:
	name = file.stem
	prefix = "evolution_results_"

	if name.startswith(prefix):
		return name[len(prefix):]

	return name


def plot_fitness(
	data: pd.DataFrame,
	path: Path,
) -> None:
	summary = (
		data
		.groupby("budget")["best_fitness"]
		.agg(
			[
				"mean",
				"median",
			]
		)
		.reset_index()
	)

	plt.figure()

	plt.plot(
		summary["budget"],
		summary["median"],
		label="Median",
	)

	plt.plot(
		summary["budget"],
		summary["mean"],
		label="Mittelwert",
	)

	plt.xlabel(
		"Anzahl der Fitnessauswertungen"
	)
	plt.ylabel(
		"Fitness des besten Individuums"
	)
	plt.xlim(left=0)
	plt.ylim(bottom =  0)
	plt.legend()
	plt.tight_layout()
	plt.savefig(path)
	plt.close()


def plot_hit_rate(
	data: pd.DataFrame,
	path: Path,
) -> None:
	data = data.copy()

	data["target_reached"] = (
		data["target_reached"]
		.astype(str)
		.str.lower()
		.eq("true")
	)

	budgets = sorted(
		data["budget"].unique()
	)
	first_hits = (
		data[data["target_reached"]]
		.groupby("run")["budget"]
		.min()
	)
	run_count = data["run"].nunique()
	hit_rates = []

	for budget in budgets:
		hit_rates.append(
			(first_hits <= budget).sum()
			/ run_count
			* 100
		)

	plt.figure()

	plt.plot(
		budgets,
		hit_rates,
	)

	plt.xlabel(
		"Anzahl der Fitnessauswertungen"
	)
	plt.ylabel(
		"Kumulative Trefferquote in Prozent"
	)
	plt.xlim(left=0)
	plt.ylim(
		0,
		100,
	)
	plt.tight_layout()
	plt.savefig(path)
	plt.close()


if __name__ == "__main__":
	main()
