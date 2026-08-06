from __future__ import annotations

import argparse
import csv
from collections import defaultdict
from pathlib import Path


# Plots high-level comparisons for an already combined variant_summary.csv.
# The intended input is a combined variant_summary.csv.

METRIC_LABELS = {
	"best_fitness_median": "Native best fitness median (lower is better)",
	"match_rate_median": "Match-rate median",
	"pitch_match_rate_median": "Pitch-match median",
	"mean_tonnetz_distance_median": "Tonnetz distance median",
	"target_reached": "Targets reached",
}

COLORS = {
	"best_fitness_median": "#526a3f",
	"match_rate_median": "#2f6f9f",
	"pitch_match_rate_median": "#b25545",
	"mean_tonnetz_distance_median": "#6a6f3f",
	"target_reached": "#8a5a99",
}


def main() -> None:
	parser = argparse.ArgumentParser(
		description="Create comparison plots for combined experiment summaries."
	)
	parser.add_argument("input", type=Path, help="combined variant_summary.csv")
	parser.add_argument(
		"--output-dir",
		type=Path,
		default=None,
		help="Directory for SVG plots. Defaults to input parent / plots.",
	)
	args = parser.parse_args()

	rows = read_rows(args.input)
	output_dir = args.output_dir or args.input.parent / "plots"
	output_dir.mkdir(parents=True, exist_ok=True)

	write_grouped_metric_plot(
		output_dir / "comparison_match_pitch.svg",
		rows,
		"comparison",
		["match_rate_median", "pitch_match_rate_median"],
		"Comparison methods",
		"Average median rate",
	)
	write_grouped_metric_plot(
		output_dir / "fitness_match_pitch.svg",
		rows,
		"fitness",
		["match_rate_median", "pitch_match_rate_median"],
		"Fitness variants",
		"Average median rate",
	)
	write_grouped_metric_plot(
		output_dir / "survival_match_pitch.svg",
		rows,
		"survival",
		["match_rate_median", "pitch_match_rate_median"],
		"Survival strategies",
		"Average median rate",
	)
	write_grouped_metric_plot(
		output_dir / "initial_population_match_pitch.svg",
		rows,
		"initial_population",
		["match_rate_median", "pitch_match_rate_median"],
		"Initial populations",
		"Average median rate",
	)
	write_single_metric_plot(
		output_dir / "comparison_best_fitness.svg",
		rows,
		"comparison",
		"best_fitness_median",
		"Native best fitness by comparison method",
	)
	write_single_metric_plot(
		output_dir / "fitness_best_fitness.svg",
		rows,
		"fitness",
		"best_fitness_median",
		"Native best fitness by fitness variant",
	)
	write_single_metric_plot(
		output_dir / "survival_best_fitness.svg",
		rows,
		"survival",
		"best_fitness_median",
		"Native best fitness by survival strategy",
	)
	write_single_metric_plot(
		output_dir / "initial_population_best_fitness.svg",
		rows,
		"initial_population",
		"best_fitness_median",
		"Native best fitness by initial population",
	)
	write_single_metric_plot(
		output_dir / "comparison_targets_reached.svg",
		rows,
		"comparison",
		"target_reached",
		"Targets reached by comparison method",
	)
	write_single_metric_plot(
		output_dir / "fitness_targets_reached.svg",
		rows,
		"fitness",
		"target_reached",
		"Targets reached by fitness variant",
	)
	write_single_metric_plot(
		output_dir / "survival_targets_reached.svg",
		rows,
		"survival",
		"target_reached",
		"Targets reached by survival strategy",
	)
	write_single_metric_plot(
		output_dir / "initial_population_targets_reached.svg",
		rows,
		"initial_population",
		"target_reached",
		"Targets reached by initial population",
	)
	write_heatmap(
		output_dir / "comparison_fitness_match_rate_heatmap.svg",
		rows,
		"comparison",
		"fitness",
		"match_rate_median",
		"Match-rate by comparison and fitness",
	)
	write_heatmap(
		output_dir / "comparison_fitness_best_fitness_heatmap.svg",
		rows,
		"comparison",
		"fitness",
		"best_fitness_median",
		"Native best fitness by comparison and fitness",
	)
	write_heatmap(
		output_dir / "comparison_fitness_targets_reached_heatmap.svg",
		rows,
		"comparison",
		"fitness",
		"target_reached",
		"Targets reached by comparison and fitness",
	)
	write_heatmap(
		output_dir / "survival_initial_match_rate_heatmap.svg",
		rows,
		"survival",
		"initial_population",
		"match_rate_median",
		"Match-rate by survival and initial population",
	)
	write_report(output_dir / "README.md", args.input, output_dir)

	print(f"Wrote plots to {output_dir}")


def read_rows(path: Path) -> list[dict]:
	with path.open(newline="") as file:
		reader = csv.DictReader(file)
		rows = []
		for row in reader:
			for key, value in list(row.items()):
				if key in {
					"runs",
					"target_reached",
					"best_fitness_median",
					"match_rate_median",
					"mean_match_rate_median",
					"pitch_match_rate_median",
					"mean_pitch_match_rate_median",
					"duration_match_rate_median",
					"mean_duration_match_rate_median",
					"mean_tonnetz_distance_median",
					"population_mean_tonnetz_distance_median",
					"mean_pitch_distance_median",
					"population_mean_pitch_distance_median",
					"duration_error_rate_median",
					"mean_duration_error_rate_median",
					"total_duration_error_median",
					"mean_total_duration_error_median",
					"missing_event_rate_median",
					"mean_missing_event_rate_median",
					"extra_event_rate_median",
					"mean_extra_event_rate_median",
					"missing_beats_median",
					"mean_missing_beats_median",
					"extra_beats_median",
					"mean_extra_beats_median",
				}:
					row[key] = float(value)
			normalize_row(row)
			rows.append(row)
	return rows


def normalize_row(row: dict) -> None:
	# The 20260803 summary used the older name initial_rules.
	if "initial_population" not in row and "initial_rules" in row:
		row["initial_population"] = row["initial_rules"]


def aggregate_rows(rows: list[dict], group_key: str, metric: str) -> list[dict]:
	groups: dict[str, list[dict]] = defaultdict(list)
	for row in rows:
		groups[str(row[group_key])].append(row)

	result = []
	for label, group_rows in groups.items():
		if metric == "target_reached":
			value = sum(float(row[metric]) for row in group_rows)
		else:
			value = sum(float(row[metric]) for row in group_rows) / len(group_rows)
		result.append({
			"label": label,
			"value": value,
			"count": len(group_rows),
		})

	return sorted(result, key=lambda row: row["label"])


def aggregate_pair(
	rows: list[dict],
	y_key: str,
	x_key: str,
	metric: str,
) -> tuple[list[str], list[str], dict[tuple[str, str], float]]:
	y_labels = sorted({str(row[y_key]) for row in rows})
	x_labels = sorted({str(row[x_key]) for row in rows})
	groups: dict[tuple[str, str], list[dict]] = defaultdict(list)

	for row in rows:
		groups[(str(row[y_key]), str(row[x_key]))].append(row)

	values = {}
	for key, group_rows in groups.items():
		if metric == "target_reached":
			values[key] = sum(float(row[metric]) for row in group_rows)
		else:
			values[key] = sum(float(row[metric]) for row in group_rows) / len(group_rows)

	return y_labels, x_labels, values


def write_grouped_metric_plot(
	path: Path,
	rows: list[dict],
	group_key: str,
	metrics: list[str],
	title: str,
	y_label: str,
) -> None:
	groups = sorted({str(row[group_key]) for row in rows})
	values = {
		metric: {
			row["label"]: float(row["value"])
			for row in aggregate_rows(rows, group_key, metric)
		}
		for metric in metrics
	}
	max_value = max(
		values[metric][group]
		for metric in metrics
		for group in groups
	)

	canvas = SvgCanvas(path, title, 980, 560, f"grouped by {group_key}")
	canvas.axes(0.0, max_value * 1.12, y_label)

	group_width = canvas.plot_width / len(groups)
	bar_width = min(52.0, group_width / (len(metrics) + 1.2))
	for group_index, group in enumerate(groups):
		group_center = canvas.left + group_width * (group_index + 0.5)
		for metric_index, metric in enumerate(metrics):
			x = group_center + (metric_index - (len(metrics) - 1) / 2.0) * bar_width
			canvas.bar(
				x - bar_width * 0.42,
				values[metric][group],
				bar_width * 0.84,
				COLORS[metric],
			)
		canvas.x_label(group_center, group)

	canvas.legend([
		(METRIC_LABELS[metric], COLORS[metric])
		for metric in metrics
	])
	canvas.finish()


def write_single_metric_plot(
	path: Path,
	rows: list[dict],
	group_key: str,
	metric: str,
	title: str,
) -> None:
	data = aggregate_rows(rows, group_key, metric)
	max_value = max(float(row["value"]) for row in data)
	canvas = SvgCanvas(path, title, 980, 560, f"grouped by {group_key}")
	canvas.axes(0.0, max_value * 1.12, METRIC_LABELS[metric])

	group_width = canvas.plot_width / len(data)
	bar_width = min(68.0, group_width * 0.58)
	for index, row in enumerate(data):
		center = canvas.left + group_width * (index + 0.5)
		canvas.bar(center - bar_width / 2.0, float(row["value"]), bar_width, COLORS[metric])
		canvas.value_label(center, float(row["value"]))
		canvas.x_label(center, str(row["label"]))

	canvas.finish()


def write_heatmap(
	path: Path,
	rows: list[dict],
	y_key: str,
	x_key: str,
	metric: str,
	title: str,
) -> None:
	y_labels, x_labels, values = aggregate_pair(rows, y_key, x_key, metric)
	all_values = list(values.values())
	min_value = min(all_values)
	max_value = max(all_values)
	width = 980
	height = 560
	left = 210
	top = 88
	right = 42
	bottom = 96
	cell_width = (width - left - right) / len(x_labels)
	cell_height = (height - top - bottom) / len(y_labels)
	items = [
		f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
		'<rect width="100%" height="100%" fill="#fbfaf7"/>',
		f'<text x="{width / 2:.1f}" y="30" text-anchor="middle" font-family="Arial, sans-serif" font-size="19" fill="#2b2b2b">{escape_svg(title)}</text>',
		f'<text x="{width / 2:.1f}" y="52" text-anchor="middle" font-family="Arial, sans-serif" font-size="12" fill="#555">{escape_svg(METRIC_LABELS[metric])}</text>',
	]

	for y_index, y_label in enumerate(y_labels):
		y = top + y_index * cell_height
		items.append(f'<text x="{left - 12:.1f}" y="{y + cell_height / 2 + 4:.1f}" text-anchor="end" font-family="Arial, sans-serif" font-size="12" fill="#333">{escape_svg(y_label)}</text>')
		for x_index, x_label in enumerate(x_labels):
			x = left + x_index * cell_width
			value = values.get((y_label, x_label), 0.0)
			color = heat_color(value, min_value, max_value)
			items.append(f'<rect x="{x:.1f}" y="{y:.1f}" width="{cell_width - 2:.1f}" height="{cell_height - 2:.1f}" fill="{color}"/>')
			items.append(f'<text x="{x + cell_width / 2:.1f}" y="{y + cell_height / 2 + 4:.1f}" text-anchor="middle" font-family="Arial, sans-serif" font-size="12" fill="#1f1f1f">{format_number(value)}</text>')

	for x_index, x_label in enumerate(x_labels):
		x = left + x_index * cell_width + cell_width / 2
		items.append(f'<text x="{x:.1f}" y="{height - bottom + 28:.1f}" text-anchor="middle" font-family="Arial, sans-serif" font-size="12" fill="#333">{escape_svg(x_label)}</text>')

	items.append("</svg>")
	path.write_text("\n".join(items) + "\n")


class SvgCanvas:
	def __init__(self, path: Path, title: str, width: int, height: int, subtitle: str) -> None:
		self.path = path
		self.width = width
		self.height = height
		self.left = 86
		self.right = 34
		self.top = 78
		self.bottom = 118
		self.plot_width = self.width - self.left - self.right
		self.plot_height = self.height - self.top - self.bottom
		self.min_y = 0.0
		self.max_y = 1.0
		self.items = [
			f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
			'<rect width="100%" height="100%" fill="#fbfaf7"/>',
			f'<text x="{width / 2:.1f}" y="30" text-anchor="middle" font-family="Arial, sans-serif" font-size="19" fill="#2b2b2b">{escape_svg(title)}</text>',
			f'<text x="{width / 2:.1f}" y="52" text-anchor="middle" font-family="Arial, sans-serif" font-size="12" fill="#555">{escape_svg(subtitle)}</text>',
		]

	def axes(self, min_y: float, max_y: float, y_label: str) -> None:
		self.min_y = min_y
		self.max_y = max(max_y, min_y + 0.01)
		x0 = self.left
		x1 = self.width - self.right
		y0 = self.top
		y1 = self.height - self.bottom
		self.items.append(f'<line x1="{x0}" y1="{y1}" x2="{x1}" y2="{y1}" stroke="#333" stroke-width="1"/>')
		self.items.append(f'<line x1="{x0}" y1="{y0}" x2="{x0}" y2="{y1}" stroke="#333" stroke-width="1"/>')
		for index in range(6):
			value = self.min_y + (self.max_y - self.min_y) * index / 5
			y = self.scale_y(value)
			self.items.append(f'<line x1="{x0}" y1="{y:.1f}" x2="{x1}" y2="{y:.1f}" stroke="#e3ded2" stroke-width="1"/>')
			self.items.append(f'<text x="{x0 - 10}" y="{y + 4:.1f}" text-anchor="end" font-family="Arial, sans-serif" font-size="11" fill="#555">{format_number(value)}</text>')
		self.items.append(f'<text x="22" y="{(y0 + y1) / 2:.1f}" text-anchor="middle" transform="rotate(-90 22 {(y0 + y1) / 2:.1f})" font-family="Arial, sans-serif" font-size="13" fill="#333">{escape_svg(y_label)}</text>')

	def scale_y(self, value: float) -> float:
		fraction = (value - self.min_y) / (self.max_y - self.min_y)
		return self.height - self.bottom - fraction * self.plot_height

	def bar(self, x: float, value: float, width: float, color: str) -> None:
		y = self.scale_y(value)
		baseline = self.scale_y(0.0)
		height = max(0.0, baseline - y)
		self.items.append(f'<rect x="{x:.1f}" y="{y:.1f}" width="{width:.1f}" height="{height:.1f}" fill="{color}"/>')

	def x_label(self, x: float, label: str) -> None:
		self.items.append(f'<text x="{x:.1f}" y="{self.height - self.bottom + 26:.1f}" text-anchor="middle" font-family="Arial, sans-serif" font-size="12" fill="#333">{escape_svg(label)}</text>')

	def value_label(self, x: float, value: float) -> None:
		self.items.append(f'<text x="{x:.1f}" y="{self.scale_y(value) - 6:.1f}" text-anchor="middle" font-family="Arial, sans-serif" font-size="11" fill="#333">{format_number(value)}</text>')

	def legend(self, entries: list[tuple[str, str]]) -> None:
		x = self.left
		y = self.height - 38
		for label, color in entries:
			self.items.append(f'<rect x="{x}" y="{y - 10}" width="14" height="14" fill="{color}"/>')
			self.items.append(f'<text x="{x + 20}" y="{y + 1}" font-family="Arial, sans-serif" font-size="12" fill="#333">{escape_svg(label)}</text>')
			x += 190

	def finish(self) -> None:
		self.items.append("</svg>")
		self.path.write_text("\n".join(self.items) + "\n")


def heat_color(value: float, min_value: float, max_value: float) -> str:
	if max_value <= min_value:
		fraction = 0.5
	else:
		fraction = (value - min_value) / (max_value - min_value)
	low = (234, 231, 216)
	high = (76, 122, 132)
	r = round(low[0] + (high[0] - low[0]) * fraction)
	g = round(low[1] + (high[1] - low[1]) * fraction)
	b = round(low[2] + (high[2] - low[2]) * fraction)
	return f"#{r:02x}{g:02x}{b:02x}"


def format_number(value: float) -> str:
	if abs(value - int(value)) < 0.001:
		return str(int(round(value)))
	if abs(value) < 1:
		return f"{value:.3f}".rstrip("0").rstrip(".")
	return f"{value:.1f}".rstrip("0").rstrip(".")


def escape_svg(value: str) -> str:
	return (
		str(value)
		.replace("&", "&amp;")
		.replace("<", "&lt;")
		.replace(">", "&gt;")
	)


def write_report(path: Path, input_path: Path, output_dir: Path) -> None:
	plots = sorted(
		plot
		for plot in output_dir.glob("*.svg")
	)
	lines = [
		"# Comparison Plots",
		"",
		f"Input: `{input_path}`",
		"",
		"`best_fitness` is the native fitness optimized by each variant; lower is better.",
		"Distance metrics such as `mean_tonnetz_distance` are diagnostic metrics, not full fitness values.",
		"",
	]
	for plot in plots:
		lines.append(f"- `{plot.name}`")
	path.write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
	main()
