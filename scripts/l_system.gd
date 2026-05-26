class_name LSystem
var axiom : String
var rules: Dictionary
var generated_string: String
var iterations: int

func _init(_axiom: String, _rules: Dictionary, _generated_string: String, _iterations: int = 4):
	axiom = _axiom
	rules = _rules
	generated_string = _generated_string
	iterations = _iterations
	
