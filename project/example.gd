extends Node


func _ready() -> void:
	var example := GDLua.new()
	example.print_type(example)
