extends Node

func _ready() -> void:
	var builder: TonnetzBuilder
	if has_node("TonnetzBuilder"):
		builder = $TonnetzBuilder
	else:
		builder = TonnetzBuilder.new()
		add_child(builder)
	builder.build(5)
