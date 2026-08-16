extends Node

# This class loads the config file when the game starts.

var config: TonnetzConfig

func _ready():
	config = load("res://config/config.tres")
