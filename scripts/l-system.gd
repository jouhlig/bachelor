class_name LSystem
var axiom : String
var rules: Dictionary
var iterations : int

func _init(_axiom: String, _rules: Dictionary, _iterations: int):
	axiom = _axiom
	rules = _rules
	iterations = _iterations

func generate() -> String:
	var current = axiom

	for i in range(iterations):
		var next = ""

		for char in current:
			next += rules.get(char, char)

		current = next
		print("Iteration ", i, " length: ", current.length(), " String: ", current)

	return current
	
