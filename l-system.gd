extends Node
class_name LSystem

func generate(axiom: String, rules: Dictionary, iterations: int) -> String:
	var current = axiom

	for i in range(iterations):
		var next = ""

		for char in current:
			if rules.has(char):
				next += rules[char]
			else:
				next += char

		current = next
		print("Iteration ", i, " length: ", current.length())

	return current
