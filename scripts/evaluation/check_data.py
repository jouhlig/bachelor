from pathlib import Path
import os

import pandas as pd


INPUT_PATH = Path(os.environ.get("EXPERIMENT_RESULTS", "data/results.csv"))

REQUIRED_COLUMNS = {
	"variant",
	"run",
	"anchor_type",
	"generation",
	"fitness_evaluations",
	"best_fitness",
	"mean_fitness",
	"worst_fitness",
	"match_rate",
	"pitch_match_rate",
	"mean_tonnetz_distance",
	"mean_pitch_distance",
	"duration_error_rate",
	"total_duration_error",
	"missing_beats",
	"extra_beats",
	"target_reached",
}


def main() -> None:
	data = read_results(INPUT_PATH)

	missing_columns = REQUIRED_COLUMNS - set(data.columns)

	if missing_columns:
		raise ValueError(
			f"Diese Spalten fehlen: {sorted(missing_columns)}"
		)

	print("Erste Zeilen:")
	print(data.head())

	print("\nSpalten:")
	print(data.columns.tolist())

	print("\nVarianten:")
	print(data["variant"].value_counts())

	print("\nAnchor-Typen:")
	print(data["anchor_type"].value_counts())

	print("\nAnzahl Runs pro Variante:")
	print(
		data
		.groupby("variant")["run"]
		.nunique()
	)

	print("\nGenerationen pro Lauf:")
	print(
		data
		.groupby(["variant", "run"])["generation"]
		.agg(["min", "max", "count"])
	)

	print("\nFehlende Werte:")
	print(data.isna().sum())

	print("\nUngültige Fitnessreihenfolge:")
	invalid_order = data[
		(data["best_fitness"] > data["mean_fitness"])
		| (data["mean_fitness"] > data["worst_fitness"])
	]

	print(f"{len(invalid_order)} verdächtige Zeilen")

	if not invalid_order.empty:
		print(invalid_order.head(20))


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
