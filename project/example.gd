extends Node


func my_print(text):
	print("myprint was called!")
	print("myprint:", text)

func _ready() -> void:
	var example := GDLua.new()
	example.register_callable("myprint", my_print)
	example.compile_and_run("myprint(false, 2) print('bad')")
	#example.compile_and_run("myprint('test', 'test2')")
	#example.compile_and_run("myprint('test', 2)")
	if example.is_error():
		print(example.get_error())
	print("DONE!!!")
