extends Node



func delay_add(a, b):
	await get_tree().create_timer(1.0).timeout
	return a + b

func _ready() -> void:
	var example := GDLua.new()
	example.register_function("print", print)
	example.register_function("delay_add", delay_add)
	var success = example.execute("print(delay_add(1,2))")
	if !success: print(example.get_error())
	
	for i in range(100):
		if example.is_waiting():
			await get_tree().create_timer(0.2).timeout
			print("waiting...")
			continue
		example.step(1, false)
		if not example.is_running():
			break;
	if example.is_error(): print(example.get_error())
	print("DONE!!!")
	await get_tree().create_timer(0.5).timeout
	get_tree().quit()
