extends VBoxContainer
@onready var symbol = $Container/Symbol
@onready var production = $Container/Production
@onready var warning = $Warning

@onready var root = get_node("/root/Game")
@onready var config = Config.config
signal production_changed

func setup(_symbol: String, _production : String) -> void:
	symbol.text = _symbol
	production.text = _production
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_production_text_changed(new_text: String) -> void:
	warning.visible = false
	
	var regex := RegEx.new()
	regex.compile("[^lruds1248]")

	var filtered = regex.sub(new_text, "", true)

	if filtered != new_text:
		production.text = filtered
		warning.visible =! warning.visible
		warning.text = "A production can only include the symbols from the alphabet."
	
	var lsystem = root.get_lsystem()
	if (new_text.is_empty()):
		print("EMPTY!")
		production.text = symbol.text
		warning.visible =! warning.visible
		warning.text = "A production cannot be empty."
	print("Productionn rule changed, prod text: ", production.text)
	LSystemFactory.regenerate_rules(lsystem, symbol.text, production.text, config)
	emit_signal("production_changed")
	

	
