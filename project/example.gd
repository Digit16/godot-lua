extends Node


func my_print(text):
	print("myprint was called!")
	print("myprint:", text)

func my_add(a, b):
	var res = a + b
	#return a + b
	await get_tree().create_timer(1.0).timeout
	#return res;
	return res

func _ready() -> void:
	var example := GDLua.new()
	example.register_function("print", my_print)
	example.register_function("my_print", my_print)
	example.register_function("myadd", my_add)
	var success = example.execute("print(myadd(1,2))")
	if !success: print(example.get_error())
	
	for i in range(100):
		await get_tree().create_timer(0.1).timeout
		example.step(1, false)
		if not example.is_running():
			break;
	if example.is_error(): print(example.get_error())
	print("DONE!!!")
	await get_tree().create_timer(0.5).timeout
	get_tree().quit()
