extends Node


func delay_add(a, b):
	await get_tree().create_timer(1.0).timeout
	return a + b

func _ready() -> void:
	var code := GDLua.new()
	code.register_function("print", print)
	code.register_function("delay_add", delay_add)
	var success = code.execute("my = {['print'] = print}")
	#code.set_global("print", null);
	if !success:
		print(code.get_error())
	code.set_global("val", 5)
	success = code.execute("my.print(delaay_add(2, 5))")
	if !success:
		print(code.get_error())
	
	
	for i in range(100):
		if code.is_waiting():
			await get_tree().create_timer(0.1).timeout
			continue
		code.run()
		if not code.is_running():
			break
	
	print("DONE!!!")
	await get_tree().create_timer(11.5).timeout
	get_tree().quit()
