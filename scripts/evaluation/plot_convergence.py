from __future__ import annotations

import argparse
from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd


def main() -> None:
	parser = argparse.ArgumentParser(
		description="Erzeugt Konvergenzplots aus summary_by_generation.csv."
	)
	parser.add_argument(
		"input",
		type=Path,
		help="Pfad zu summary_by_generation.csv.",
	)
	args = parser.parse_args()

	data = pd.read_csv(args.input)

	output_dir = args.input.parent / "plots"
	output_dir.mkdir(
		parents=True,
		exist_ok=True,
	)

	plot_match_rate_by_fitness(
		data,
		output_dir / "convergence_by_fitness.pdf",
	)

	plot_match_rate_by_comparison(
		data,
		output_dir / "convergence_by_comparison.pdf",
	)

	print(f"Plots gespeichert in: {output_dir}")


def plot_match_rate_by_fitness(
	data: pd.DataFrame,
	path: Path,
) -> None:
	for fitness in data["fitness"].unique():
		fitness_data = data[
			data["fitness"] == fitness
		]

		generation_data = (
			fitness_data
			.groupby("generation")["match_rate_mean"]
			.mean()
		)

		plt.plot(
			generation_data.index,
			generation_data.values,
			label=fitness,
		)

	plt.xlabel("Generation")
	plt.ylabel("Mittlere Match-Rate")
	plt.legend()
	plt.tight_layout()
	plt.savefig(path)
	plt.close()


def plot_match_rate_by_comparison(
	data: pd.DataFrame,
	path: Path,
) -> None:
	for comparison in data["comparison"].unique():
		comparison_data = data[
			data["comparison"] == comparison
		]

		generation_data = (
			comparison_data
			.groupby("generation")["match_rate_mean"]
			.mean()
		)

		plt.plot(
			generation_data.index,
			generation_data.values,
			label=comparison,
		)

	plt.xlabel("Generation")
	plt.ylabel("Mittlere Match-Rate")
	plt.legend()
	plt.tight_layout()
	plt.savefig(path)
	plt.close()


if __name__ == "__main__":
	main()