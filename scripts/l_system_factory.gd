class_name LSystemFactory

static var symbols : Array[String]= ["l","r","s","u","d","1","2","4","8"]
static var rng  = RandomNumberGenerator.new()
static var WEIGHTED_SYMBOLS = {
	"horizontal_movement": {
		"weight": 60,
		"symbols": ["l", "r"]
	},
	"up": {
		"weight": 40,
		"symbols": ["u"]
	},
	"down": {
		"weight": 40,
		"symbols": ["d"]
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
const TOTAL_WEIGHT: int = 260
#if pen up was drawn, probability should go up to pick pen down 
static var pen_up_symbol_unresolved
static func get_random_symbol_weighted()-> String:
	var random_value := randi_range(1, TOTAL_WEIGHT)
	var current := 0
	for category in WEIGHTED_SYMBOLS:
		current += WEIGHTED_SYMBOLS[category]["weight"]
		if random_value <= current:
			var pick = WEIGHTED_SYMBOLS[category]["symbols"].pick_random()
			if pick == "u":
				pen_up_symbol_unresolved = true
				WEIGHTED_SYMBOLS["up"]["weight"] -= 10
				WEIGHTED_SYMBOLS["down"]["weight"] += 10
			if pick == "d":
				pen_up_symbol_unresolved = false
				WEIGHTED_SYMBOLS["up"]["weight"] =40
				WEIGHTED_SYMBOLS["down"]["weight"] =40
			return pick
	push_error("No return value for random pick in rule production")
	return ""
#takes character after character and substitutes them according to production rules for number of iterations
static func generate_string(axiom: String, rules: Dictionary, iterations: int) -> String:
	var current_string = axiom
	for i in range(iterations):
		var next = ""
		for char in current_string:
			next += rules.get(char, char)
		current_string = next
		print("Iteration ", i, " length: ", current_string.length(), " String: ", current_string)
	return current_string

static func random(config: TonnetzConfig) -> LSystem:
	rng.randomize()
	var system = new_random_system(config)
	print("Generated new system: ", system)
	var lsystem = LSystem.new(
		system["axiom"],
		system["rules"],
		system["generated_string"],
		system["iterations"]
	)
	return lsystem

static func new_random_system(config: TonnetzConfig) -> Dictionary:
	var new_rules := {}

	for symbol in symbols:
		new_rules[symbol] = generate_rule(config.max_rule_length, config.placement_probability)
	var new_axiom : String = symbols.pick_random()
	var generated_string = generate_string(new_axiom, new_rules, config.number_iterations)
	return {
		"axiom": new_axiom,
		"rules": new_rules,
		"generated_string": generated_string,
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
		result = symbols.pick_random()
		#print("Empty string, picked: ", result)
	return result
	
static func regenerate_string(lsystem: LSystem, iterations: int) -> void:
	lsystem.iterations = iterations
	lsystem.generated_string = generate_string(
		lsystem.axiom,
		lsystem.rules,
		iterations
	)
static func regenerate_rules(lsystem: LSystem, symbol: String, production: String, config: TonnetzConfig) -> void:
	print(symbol, ", ", production,  ", ")
	lsystem.rules[symbol] = production

	regenerate_string(
		lsystem,
		lsystem.iterations
	)	
