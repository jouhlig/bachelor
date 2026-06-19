class_name SymbolNode
extends RefCounted

var symbol: String
var generation: int

var parent: SymbolNode = null
var children: Array[SymbolNode] = []
var child_index := -1

var final_start := -1
var final_end := -1

func _init(
	_symbol: String,
	_generation: int,
	_parent: SymbolNode = null,
	_child_index: int = -1
):
	symbol = _symbol
	generation = _generation
	parent = _parent
	child_index = _child_index
