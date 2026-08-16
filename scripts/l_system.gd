class_name LSystem

# L-system creation and management

const TERMINALS: Array[String] = ["l", "r", "s", "1", "2", "4", "8"]
# Disabled-symbol backup: add "u" and "d" back to TERMINALS to re-enable those L-system symbols.
# const TERMINALS_WITH_DISABLED_SYMBOLS: Array[String] = ["l", "r", "s", "u", "d", "1", "2", "4", "8"]

var axiom: String
var rules: Dictionary
var generated_string: String
var iterations: int
var color: Color = Color.WHITE
var volume: float = 0.8


func _init(
	_axiom: String,
	_rules: Dictionary,
	_generated_string: String,
	_iterations: int = 4
):
	axiom = _axiom
	rules = _rules
	generated_string = _generated_string
	iterations = _iterations

func regenerate() -> void:
	generated_string = LSystem.generate_string(axiom, rules, iterations)

func set_axiom(new_axiom: String) -> void:
	if new_axiom.is_empty():
		return

	axiom = new_axiom[0]
	regenerate()

func set_iterations(new_iterations: int) -> void:
	iterations = new_iterations
	regenerate()

func set_rule(symbol: String, production: String) -> void:
	rules[symbol] = production
	regenerate()

func apply_generated_state(
	new_axiom: String,
	new_rules: Dictionary,
	new_generated_string: String
) -> void:
	axiom = new_axiom
	rules = new_rules
	generated_string = new_generated_string

func randomize(config: TonnetzConfig) -> void:
	var current_iterations := iterations
	var random_system = LSystemFactory.new_random_system(config)
	iterations = current_iterations
	apply_generated_state(
		random_system["axiom"],
		random_system["rules"],
		LSystem.generate_string(random_system["axiom"], random_system["rules"], iterations)
	)

func duplicate_system() -> LSystem:
	var duplicate = LSystem.new(
		axiom,
		rules.duplicate(true),
		generated_string,
		iterations
	)
	duplicate.color = color
	duplicate.volume = volume
	return duplicate

func set_volume(new_volume: float) -> void:
	volume = clamp(new_volume, 0.0, 1.0)

static func generate_string(axiom: String, rules: Dictionary, iterations: int) -> String:
	var result := axiom
	for generation in range(iterations):
		var next := ""
		for i in range(result.length()):
			var symbol := result[i]
			next += str(rules.get(symbol, symbol))
		result = next
	return result

static func identity_rules() -> Dictionary:
	var result := {}
	for symbol in TERMINALS:
		result[symbol] = symbol
	return result

static func rule_symbol_pattern() -> String:
	var symbols := ""
	for symbol in TERMINALS:
		symbols += symbol
	return "[^" + symbols + "]"
