class_name LSystemSpawnController
extends RefCounted

var builder: TonnetzBuilder
var tonnetz_world: Node2D
var config: TonnetzConfig
var drag_origin_anchor = null

func _init(
	new_builder: TonnetzBuilder,
	new_tonnetz_world: Node2D,
	new_config: TonnetzConfig
) -> void:
	builder = new_builder
	tonnetz_world = new_tonnetz_world
	config = new_config

func begin_drag(click_pos: Vector2, _color: Color) -> void:
	cancel_drag()
	drag_origin_anchor = builder.get_nearest_spawn_anchor(click_pos)

func cancel_drag() -> void:
	drag_origin_anchor = null

func release_drag(_click_pos: Vector2) -> Dictionary:
	if not drag_origin_anchor:
		return {}

	var origin_anchor = drag_origin_anchor
	cancel_drag()
	return {"origin": origin_anchor}
