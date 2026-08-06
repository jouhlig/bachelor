from __future__ import annotations

import argparse
import os
from pathlib import Path

import matplotlib
import pandas as pd


matplotlib.use("Agg")

import matplotlib.pyplot as plt

DEFAULT_EXPERIMENTS = [
	Path("scripts/evolution/experiments/results/0308_experiment_series"),
	Path("scripts/evolution/experiments/results/0408_experiment_series"),
]
EXPERIMENT_LABELS = {
	"0308_experiment_series": "alter Algo",
	"0408_experiment_series": "neuer Algo",
}


def main() -> None:
	parser = argparse.ArgumentParser(
		description="Plottet Ergebnisqualität nach Score-Länge."
	)
	parser.add_argument(
		"experiments",
		type=Path,
		nargs="*",
		help="Experimentordner. Ohne Angabe werden 0308 und 0408 verglichen.",
	)
	parser.add_argument(
		"--output-dir",
		type=Path,
		default=Path("scripts/evolution/experiments/results/plots"),
		help="Ordner für die Plots.",
	)
	args = parser.parse_args()

	experiment_dirs = args.experiments
	if not experiment_dirs:
		experiment_dirs = DEFAULT_EXPERIMENTS

	args.output_dir.mkdir(
		parents=True,
		exist_ok=True,
	)

	data = read_experiments(
		experiment_dirs
	)

	plot_metric(
		data,
		args.output_dir / "score_length_target_reached.pdf",
		"target_reached_rate",
		"Trefferquote in Prozent",
	)
	plot_metric(
		data,
		args.output_dir / "score_length_match_rate.pdf",
		"match_rate_mean",
		"Mittlere Match-Rate",
	)

	print(f"Plots gespeichert in: {args.output_dir}")


def read_experiments(
	experiment_dirs: list[Path],
) -> pd.DataFrame:
	frames = []

	for experiment_dir in experiment_dirs:
		path = experiment_dir / "summary" / "final_runs.csv"

		if not path.exists():
			raise FileNotFoundError(
				f"final_runs.csv nicht gefunden: {path}"
			)

		frame = pd.read_csv(path)
		frame["experiment"] = EXPERIMENT_LABELS.get(
			experiment_dir.name,
			experiment_dir.name,
		)
		frame["target_reached"] = (
			frame["target_reached"]
			.astype(str)
			.str.lower()
			.eq("true")
		)
		frames.append(
			frame
		)

	return pd.concat(
		frames,
		ignore_index=True,
	)


def plot_metric(
	data: pd.DataFrame,
	path: Path,
	metric: str,
	ylabel: str,
) -> None:
	summary = summarize_by_length(
		data
	)

	plt.figure()

	for experiment in summary["experiment"].unique():
		experiment_data = summary[
			summary["experiment"] == experiment
		]

		plt.plot(
			experiment_data["walk_length"],
			experiment_data[metric],
			marker="o",
			label=experiment,
		)

	plt.xlabel(
		"Score-Länge"
	)
	plt.ylabel(
		ylabel
	)
	plt.xlim(left=0)
	plt.legend()
	plt.tight_layout()
	plt.savefig(path)
	plt.close()


def summarize_by_length(
	data: pd.DataFrame,
) -> pd.DataFrame:
	summary = (
		data
		.groupby(["experiment", "walk_length"], as_index=False)
		.agg(
			target_reached_rate=("target_reached", "mean"),
			match_rate_mean=("match_rate", "mean"),
			runs=("run", "count"),
		)
	)
	summary["target_reached_rate"] = (
		summary["target_reached_rate"]
		* 100
	)
	return summary


if __name__ == "__main__":
	main()
