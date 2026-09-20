extends Node

class DummyTarget extends Object:
	func some_method():
		pass

func dummy_add(a, b):
	return a + b

func _ready() -> void:
	print("========================================")
	print("   GDLua Error Handling Test Suite      ")
	print("========================================")
	
	var total_tests = 0
	var passed_tests = 0
	
	# Helper to step coroutines until halted or error
	var run_steps = func(lua_state: GDLua, max_steps: int = 100) -> bool:
		for i in range(max_steps):
			if lua_state.is_waiting():
				await get_tree().create_timer(0.05).timeout
				continue
			lua_state.step(1, false)
			if not lua_state.is_running():
				break
		return !lua_state.is_error()

	# TEST 1: Syntax / Compile Error
	total_tests += 1
	print("\n[Test 1] Testing Syntax Error...")
	var lua := GDLua.new()
	var compile_ok = lua.compile("function 123 +++ ??")
	if !compile_ok and lua.is_error():
		print("  PASS: Caught syntax error -> '%s'" % lua.get_error())
		passed_tests += 1
	else:
		printerr("  FAIL: Expected compile failure, got: ok=%s, err=%s" % [compile_ok, lua.get_error()])

	# TEST 2: Runtime Exception (Index Nil)
	total_tests += 1
	print("\n[Test 2] Testing Runtime Nil Index...")
	lua.reset()
	lua.compile("local x = nil; x.foo = 10")
	await run_steps.call(lua)
	if lua.is_error() and lua.get_error().contains("attempt to index"):
		print("  PASS: Caught nil index -> '%s'" % lua.get_error())
		passed_tests += 1
	else:
		printerr("  FAIL: Expected nil index error, got: '%s'" % lua.get_error())

	# TEST 3: Calling Undefined Global Function
	total_tests += 1
	print("\n[Test 3] Testing Undefined Function Call...")
	lua.reset()
	lua.compile("missing_function(1, 2, 3)")
	await run_steps.call(lua)
	if lua.is_error() and lua.get_error().contains("attempt to call a nil value"):
		print("  PASS: Caught undefined function error -> '%s'" % lua.get_error())
		passed_tests += 1
	else:
		printerr("  FAIL: Expected nil call error, got: '%s'" % lua.get_error())

	# TEST 4: Callable Argument Count Mismatch
	total_tests += 1
	print("\n[Test 4] Testing Callable Argument Count Mismatch...")
	lua.reset()
	lua.register_function("add", dummy_add)
	lua.compile("add(42)") # passed 1 arg instead of 2
	await run_steps.call(lua)
	if lua.is_error() and lua.get_error().contains("wrong number of arguments"):
		print("  PASS: Caught arg count mismatch -> '%s'" % lua.get_error())
		passed_tests += 1
	else:
		printerr("  FAIL: Expected arg count error, got: '%s'" % lua.get_error())

	# TEST 5: Callable Unsupported Argument Type
	total_tests += 1
	print("\n[Test 5] Testing Unsupported Argument Type (table)...")
	lua.reset()
	lua.register_function("add", dummy_add)
	lua.compile("add({x = 1}, 2)")
	await run_steps.call(lua)
	if lua.is_error() and lua.get_error().contains("unsupported argument type"):
		print("  PASS: Caught unsupported type -> '%s'" % lua.get_error())
		passed_tests += 1
	else:
		printerr("  FAIL: Expected unsupported type error, got: '%s'" % lua.get_error())

	# TEST 6: Explicit Lua error() Call
	total_tests += 1
	print("\n[Test 6] Testing Explicit error() Call...")
	lua.reset()
	lua.compile("error('custom user panic')")
	await run_steps.call(lua)
	if lua.is_error() and lua.get_error().contains("custom user panic"):
		print("  PASS: Caught explicit error -> '%s'" % lua.get_error())
		passed_tests += 1
	else:
		printerr("  FAIL: Expected explicit error, got: '%s'" % lua.get_error())

	# TEST 7: Invalid / Freed Callable
	total_tests += 1
	print("\n[Test 7] Testing Freed Object Callable...")
	lua.reset()
	var dummy = DummyTarget.new()
	var freed_callable = Callable(dummy, "some_method")
	dummy.free()
	lua.register_function("call_freed", freed_callable)
	lua.compile("call_freed()")
	await run_steps.call(lua)
	if lua.is_error() and lua.get_error().contains("callable is invalid or has been freed"):
		print("  PASS: Caught freed callable error -> '%s'" % lua.get_error())
		passed_tests += 1
	else:
		printerr("  FAIL: Expected freed callable error, got: '%s'" % lua.get_error())

	# TEST 8: clear_error() and State Recovery
	total_tests += 1
	print("\n[Test 8] Testing Error Clearing and State Reset...")
	lua.clear_error()
	var clear_ok = !lua.is_error() and lua.get_error().is_empty()
	lua.reset()
	var valid_ok = lua.compile("val = 100 + 50") and lua.run()
	var val_result = lua.get_global("val")
	if clear_ok and valid_ok and val_result == 150:
		print("  PASS: Successfully cleared error and recovered state (val=%s)" % val_result)
		passed_tests += 1
	else:
		printerr("  FAIL: Error recovery failed.")

	# TEST 9: Stepping Infinite Loop & abort()
	total_tests += 1
	print("\n[Test 9] Testing Infinite Loop Stepping & abort()...")
	lua.reset()
	lua.compile("local i = 0; while true do i = i + 1 end")
	lua.step(10, false)
	var was_running = lua.is_running()
	lua.abort()
	var aborted_ok = !lua.is_running()
	if was_running and aborted_ok and !lua.is_error():
		print("  PASS: Step limiter stopped infinite loop, abort() cleanly halted.")
		passed_tests += 1
	else:
		printerr("  FAIL: Abort test failed.")

	# SUMMARY
	print("\n========================================")
	print("   RESULTS: %d / %d Tests Passed        " % [passed_tests, total_tests])
	print("========================================")
	
	assert(passed_tests == total_tests, "Not all error handling tests passed!")
	print("ALL ERROR TESTS COMPLETED SUCCESSFULLY!")
	
	await get_tree().create_timer(0.5).timeout
	get_tree().quit(0 if passed_tests == total_tests else 1)
