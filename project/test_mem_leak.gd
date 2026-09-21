extends Control

@onready var log_label: RichTextLabel = $LogLabel

func log_msg(msg: String) -> void:
	print(msg)
	if log_label:
		pass#log_label.append_text(msg + "\n")

func dummy_callback(a, b):
	return a + b

func _ready() -> void:
	log_msg("========================================")
	log_msg("       GDLua Memory Leak Test Suite     ")
	log_msg("========================================")
	
	await get_tree().process_frame

	var iterations = 5000

	# ----------------------------------------------------
	# TEST 1: Single GDLua Instance Reuse Loop
	# Tests if repeated script execution and table/string creation
	# inside a single Lua state leaks memory or if Lua GC collects it.
	# ----------------------------------------------------
	log_msg("\n[Test 1] Single instance reuse (%d iterations)..." % iterations)
	var lua := GDLua.new()
	var lua_mem_start = lua.get_memory_used()
	var godot_mem_start = OS.get_static_memory_usage()

	for i in range(iterations):
		lua.compile("""
			local t = {}
			for j = 1, 100 do
				t[j] = "val_" .. tostring(j)
			end
			result = #t
			collectgarbage("collect")
		""")
		lua.run()

		if (i + 1) % 10 == 0:
			log_msg("  Iter %2d: lua_used=%d B, godot_mem=%d KB" % [
				i + 1,
				lua.get_memory_used(),
				OS.get_static_memory_usage() / 1024
			])
			await get_tree().process_frame

	var lua_mem_before_gc = lua.get_memory_used()
	lua.compile("collectgarbage('collect')")
	lua.run()
	log_msg("  -> Before final GC: %d B | After final GC: %d B (freed %d B)" % [
		lua_mem_before_gc,
		lua.get_memory_used(),
		lua_mem_before_gc - lua.get_memory_used()
	])
	var lua_mem_end = lua.get_memory_used()
	var godot_mem_end = OS.get_static_memory_usage()
	var lua_delta = lua_mem_end - lua_mem_start
	var godot_delta = (godot_mem_end - godot_mem_start) / 1024
	log_msg("  -> Test 1 Result: Lua delta = %d B, Godot delta = %d KB" % [lua_delta, godot_delta])
	lua = null

	# ----------------------------------------------------
	# TEST 2: Instance Lifecycle Loop (new and free)
	# Tests if GDLua instances leak when repeatedly created and freed.
	# ----------------------------------------------------
	log_msg("\n[Test 2] Creation and destruction loop (%d iterations)..." % iterations)
	godot_mem_start = OS.get_static_memory_usage()

	for i in range(iterations):
		var temp_lua := GDLua.new()
		temp_lua.compile("local x = 10 * 20; val = x + 5")
		temp_lua.run()
		temp_lua = null

		if (i + 1) % 10 == 0:
			log_msg("  Iter %2d: godot_mem=%d KB" % [
				i + 1,
				OS.get_static_memory_usage() / 1024
			])
			await get_tree().process_frame

	godot_mem_end = OS.get_static_memory_usage()
	godot_delta = (godot_mem_end - godot_mem_start) / 1024
	log_msg("  -> Test 2 Result: Godot delta = %d KB" % godot_delta)

	# ----------------------------------------------------
	# TEST 3: Godot Function Binding Call Loop
	# Tests callable invocation across Lua/Godot boundary in a loop.
	# ----------------------------------------------------
	log_msg("\n[Test 3] Godot callback loop (%d iterations)..." % iterations)
	var cb_lua := GDLua.new()
	cb_lua.register_function("add", Callable(self, "dummy_callback"))
	godot_mem_start = OS.get_static_memory_usage()
	lua_mem_start = cb_lua.get_memory_used()

	for i in range(iterations):
		cb_lua.compile("""
			val = add(%d, 10)
			collectgarbage("collect")
		""" % i)
		cb_lua.run()

		if (i + 1) % 10 == 0:
			log_msg("  Iter %2d: lua_used=%d B, godot_mem=%d KB" % [
				i + 1,
				cb_lua.get_memory_used(),
				OS.get_static_memory_usage() / 1024
			])
			await get_tree().process_frame

	cb_lua.compile("collectgarbage('collect')")
	cb_lua.run()

	lua_mem_end = cb_lua.get_memory_used()
	godot_mem_end = OS.get_static_memory_usage()
	lua_delta = lua_mem_end - lua_mem_start
	godot_delta = (godot_mem_end - godot_mem_start) / 1024
	log_msg("  -> Test 3 Result: Lua delta = %d B, Godot delta = %d KB" % [lua_delta, godot_delta])
	cb_lua = null

	log_msg("\n========================================")
	log_msg("      MEMORY LEAK TESTS COMPLETED       ")
	log_msg("========================================")
