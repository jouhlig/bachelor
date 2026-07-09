class_name LSystemFactory

static var rng  = RandomNumberGenerator.new()
static var WEIGHTED_SYMBOLS = {
	"horizontal_movement": {
		"weight": 60,
		"symbols": ["l", "r"]
	},
	"step": {
		"weight": 100,
		"symbols": ["s"]
	},
	"speed_change": {
		"weight": 40,
		"symbols": ["1", "2", "4", "8"]
	},
	"empty": {
		"weight": 20,
		"symbols": [""]
	}
}
const TOTAL_WEIGHT: int = 220
# Disabled-symbol backup for WEIGHTED_SYMBOLS:
# "up": {
# 	"weight": 40,
# 	"symbols": ["u"]
# },
# "down": {
# 	"weight": 40,
# 	"symbols": ["d"]
# },
# If these are restored, set TOTAL_WEIGHT back to 300 and re-enable the balancing logic below.
# static var disabled_symbol_unresolved
static func get_random_symbol_weighted()-> String:
	var random_value := randi_range(1, TOTAL_WEIGHT)
	var current := 0
	for category in WEIGHTED_SYMBOLS:
		current += WEIGHTED_SYMBOLS[category]["weight"]
		if random_value <= current:
			var pick = WEIGHTED_SYMBOLS[category]["symbols"].pick_random()
#			if pick == "u":
#				disabled_symbol_unresolved = true
#				WEIGHTED_SYMBOLS["up"]["weight"] -= 10
#				WEIGHTED_SYMBOLS["down"]["weight"] += 10
#			if pick == "d":
#				disabled_symbol_unresolved = false
#				WEIGHTED_SYMBOLS["up"]["weight"] = 40
#				WEIGHTED_SYMBOLS["down"]["weight"] = 40
			return pick
	push_error("No return value for random pick in rule production")
	return ""


static func random(config: TonnetzConfig) -> LSystem:
	rng.randomize()
	var system = new_random_system(config)
	#print("Generated new system: ", system)
	var lsystem = LSystem.new(
		system["axiom"],
		system["rules"],
		system["generated_string"],
		system["iterations"]
	)
	return lsystem

static func new_random_system(config: TonnetzConfig) -> Dictionary:
	rng.randomize()
	var new_rules := {}

	for symbol in LSystem.TERMINALS:
		new_rules[symbol] = generate_rule(config.max_rule_length, config.placement_probability)
	var new_axiom : String = LSystem.TERMINALS.pick_random()
	return {
		"axiom": new_axiom,
		"rules": new_rules,
		"generated_string": LSystem.generate_string(new_axiom, new_rules, config.number_iterations),
		"iterations": config.number_iterations
	}

#generates the right side of a rule for a symbol
static func generate_rule(rule_length: int, placement_probability: float) -> String:
	var result := ""

	for i in range(rule_length):
		if rng.randf() < placement_probability:
			result += get_random_symbol_weighted()
			#print("Yes pick one: ", result)

	# avoid epsilon rule
	if result.is_empty():
		result = LSystem.TERMINALS.pick_random()
		#print("Empty string, picked: ", result)
	return result

func create_lsystem(axiom: String, rules: Dictionary, iterations: int) -> LSystem:
	return LSystem.new(
		axiom,
		rules,
		LSystem.generate_string(axiom, rules, iterations),
		iterations
	)
