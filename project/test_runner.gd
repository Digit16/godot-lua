extends Node

class DummyTarget extends Object:
	func some_method():
		pass

class AsyncEmitter extends Object:
	@warning_ignore("unused_signal")
	signal completed(result)

func dummy_add(a, b):
	return a + b

func async_add(a, b):
	await get_tree().create_timer(0.05).timeout
	return a + b

func slow_async():
	await get_tree().create_timer(0.2).timeout
	return 999

var total_tests := 0
var passed_tests := 0

func run_to_completion(lua: GDLua, max_steps: int = 100) -> void:
	for _i in range(max_steps):
		if lua.is_waiting():
			await get_tree().create_timer(0.05).timeout
			continue
		lua.step(1, false)
		if not lua.is_running():
			break

func assert_test(test_name: String, condition: bool, err_msg: String = "") -> void:
	total_tests += 1
	if condition:
		passed_tests += 1
		print("  [PASS] %s" % test_name)
	else:
		printerr("  [FAIL] %s - %s" % [test_name, err_msg])

@warning_ignore("redundant_await")
func _ready() -> void:
	print("========================================")
	print("       GDLua Comprehensive Test Suite   ")
	print("========================================")

	# 1. Compilation & Runtime Errors
	test_syntax_error()
	await test_nil_index_error()
	await test_undefined_function_error()
	await test_explicit_panic()
	await test_reset_recovery()

	# 2. Execution Control & Stepping
	test_abort_infinite_loop()
	test_line_stepping()
	test_debug_inspection()
	await test_recompile_while_waiting()

	# 3. Variable Access
	test_global_variables()
	test_global_persistence_across_runs()
	test_reset_wipes_globals()
	test_local_variable_access()

	# 4. Function Binding & Callables
	test_callable_bidirectional()
	test_callable_return_types()
	test_callable_multi_args()
	await test_callable_unsupported_return_type()
	await test_argument_count_mismatch()
	await test_unsupported_argument_type()
	await test_freed_callable()

	# 5. Asynchronous Signals (completed)
	await test_async_signal_resumption()
	await test_async_abort_disconnect()
	test_async_target_freed_safety()

	# 6. Memory Limits & Garbage Collection
	await test_memory_limit_exceeded()
	test_memory_accounting_and_gc()

	# 7. Multi-Instance Isolation
	test_multi_instance_isolation()

	# 8. Function Definition & Environment Isolation
	test_define_function_basic()
	test_define_function_environment_isolation()
	test_define_function_non_persistent_lifecycle()
	test_define_function_hot_reloading()
	test_define_function_syntax_error()
	await test_define_function_async_wait()
	test_define_function_stepping()
	test_define_function_mid_stepping()
	test_define_function_debug_info()
	test_define_function_nested_call_stack()
	test_define_function_runtime_error_line()
	test_define_function_params_and_multi_return()
	test_define_function_mutual_recursion()
	test_define_function_custom_chunk_name()
	test_define_function_arg_table_indexing()

	print("\n========================================")
	print("   RESULTS: %d / %d Tests Passed" % [passed_tests, total_tests])
	print("========================================")

	var success = (passed_tests == total_tests)
	await get_tree().create_timer(0.5).timeout
	get_tree().quit(0 if success else 1)

# -----------------------------------------------------------------------------
# 1. Compilation & Runtime Errors
# -----------------------------------------------------------------------------

func test_syntax_error() -> void:
	var lua := GDLua.new()
	var ok = lua.compile("function 123 +++ ??")
	assert_test("Syntax Error", not ok and lua.is_error(), lua.get_error())

func test_nil_index_error() -> void:
	var lua := GDLua.new()
	lua.compile("local x = nil; x.foo = 10")
	await run_to_completion(lua)
	assert_test("Runtime Nil Index", lua.is_error() and lua.get_error().contains("attempt to index"), lua.get_error())

func test_undefined_function_error() -> void:
	var lua := GDLua.new()
	lua.compile("missing_function(1, 2, 3)")
	await run_to_completion(lua)
	assert_test("Undefined Function Call", lua.is_error() and lua.get_error().contains("attempt to call a nil value"), lua.get_error())

func test_explicit_panic() -> void:
	var lua := GDLua.new()
	lua.compile("error('custom user panic')")
	await run_to_completion(lua)
	assert_test("Explicit Lua error() Call", lua.is_error() and lua.get_error().contains("custom user panic"), lua.get_error())

func test_reset_recovery() -> void:
	var lua := GDLua.new()
	lua.compile("error('state broken')")
	await run_to_completion(lua)
	var had_error = lua.is_error()

	var reset_ok = lua.reset()
	var cleared_error = not lua.is_error()
	var run_ok = lua.compile("val = 100 + 50") and lua.run()
	var val = lua.get_global("val")

	var condition = had_error and reset_ok and cleared_error and run_ok and (val == 150)
	var detail = "had_err=%s, reset_ok=%s, cleared=%s, run_ok=%s, val=%s" % [had_error, reset_ok, cleared_error, run_ok, val]
	assert_test("Reset Error Clearing & Recovery", condition, detail)

# -----------------------------------------------------------------------------
# 2. Execution Control & Stepping
# -----------------------------------------------------------------------------

func test_abort_infinite_loop() -> void:
	var lua := GDLua.new()
	lua.compile("local i = 0; while true do i = i + 1 end")
	lua.step(10, false)
	var was_running = lua.is_running()
	lua.abort()
	var aborted_ok = not lua.is_running() and not lua.is_error()
	assert_test("Stepping Loop & abort()", was_running and aborted_ok, "Abort failed")

func test_line_stepping() -> void:
	var lua := GDLua.new()
	lua.compile("a = 10\nb = 20\nc = 30")
	lua.step(1, true)
	var a_init = lua.get_global("a")
	lua.step(1, true)
	var a_val = lua.get_global("a")
	var b_init = lua.get_global("b")
	lua.step(1, true)
	var b_val = lua.get_global("b")
	var c_init = lua.get_global("c")
	lua.run()
	var c_val = lua.get_global("c")

	var ok = (a_init == null) and (a_val == 10) and (b_init == null) and (b_val == 20) and (c_init == null) and (c_val == 30) and not lua.is_running() and not lua.is_error()
	assert_test("Line-Based Stepping (line=true)", ok, "a_init=%s, a=%s, b=%s, c=%s" % [a_init, a_val, b_val, c_val])

func test_recompile_while_waiting() -> void:
	var lua := GDLua.new()
	lua.register_function("slow_async", slow_async)
	lua.compile("slow_async()")
	lua.step(10, false)
	var was_waiting = lua.is_waiting()

	# Re-compile new chunk while previous thread is actively waiting on signal
	var recompile_ok = lua.compile("res = 100 * 2")
	var not_waiting = not lua.is_waiting()
	var is_running = lua.is_running()

	lua.run()
	var res = lua.get_global("res")

	# Wait for original async timer to expire to ensure no dangling signals fire into dead coroutine
	await get_tree().create_timer(0.25).timeout
	var clean_after_timer = not lua.is_running() and not lua.is_error()

	var ok = was_waiting and recompile_ok and not_waiting and is_running and (res == 200) and clean_after_timer
	assert_test("Recompile Cleanly Resets Waiting State", ok, "was_waiting=%s, res=%s, err=%s" % [was_waiting, res, lua.get_error()])

func test_debug_inspection() -> void:
	var lua := GDLua.new()
	var code := """-- line 1
a = 10 -- line 2
b = 20 -- line 3
function test_func(param) -- line 4
	local x = param + 5 -- line 5
	while true do end -- line 6
end -- line 7
test_func(50) -- line 8
"""
	lua.compile(code, "@test_script.lua")

	# Stepping line by line: hook stops before executing line 2
	lua.step(1, true)
	var line_step1 = lua.get_current_line()
	var src_step1 = lua.get_current_source()

	# Step until execution enters test_func's while loop at line 6
	lua.step(15, false)

	# Level 0 is inside test_func at line 6
	var l0_line = lua.get_current_line(0)
	var l0_src = lua.get_current_source(0)
	var l0_info = lua.get_debug_info(0)

	# Level 1 is the caller at line 8
	var l1_line = lua.get_current_line(1)
	var l1_info = lua.get_debug_info(1)

	lua.abort()

	# Test default chunk name and default step arguments (steps=1, line=false)
	var def_lua := GDLua.new()
	def_lua.compile("val = 1")
	def_lua.step() # Default steps=1, line=false
	var def_src = def_lua.get_current_source()
	def_lua.abort()

	var ok = (
		line_step1 == 2 and
		src_step1 == "@test_script.lua" and
		l0_line == 6 and
		l0_src == "@test_script.lua" and
		l0_info.get("valid") == true and
		l0_info.get("line") == 6 and
		l0_info.get("source") == "@test_script.lua" and
		l0_info.get("short_source") == "test_script.lua" and
		l0_info.get("function") == "test_func" and
		l0_info.get("what") == "Lua" and
		l0_info.get("line_defined") == 4 and
		l0_info.get("last_line_defined") == 7 and
		l0_info.get("num_params") == 1 and
		l1_line == 8 and
		l1_info.get("valid") == true and
		l1_info.get("line") == 8 and
		l1_info.get("what") == "main" and
		def_src == "chunk"
	)
	assert_test("Debug Info & Execution Cursor (Line, Source, Stack)", ok, "l0_line=%s, l0_fn=%s, l1_line=%s" % [l0_line, l0_info.get("function"), l1_line])

# -----------------------------------------------------------------------------
# 3. Variable Access
# -----------------------------------------------------------------------------

func test_global_variables() -> void:
	var lua := GDLua.new()
	lua.set_global("g_int", 42)
	lua.set_global("g_float", 3.14)
	lua.set_global("g_str", "hello godot")
	lua.set_global("g_bool", true)

	lua.compile("res_int = g_int + 8; res_str = g_str .. '!'")
	lua.run()

	var r_int = lua.get_global("res_int")
	var r_str = lua.get_global("res_str")
	var r_float = lua.get_global("g_float")
	var r_bool = lua.get_global("g_bool")

	var ok = (r_int == 50) and (r_str == "hello godot!") and is_equal_approx(r_float, 3.14) and (r_bool == true)
	assert_test("Global Variables Read/Write", ok, "int=%s, str=%s, float=%s, bool=%s" % [r_int, r_str, r_float, r_bool])

func test_global_persistence_across_runs() -> void:
	var lua := GDLua.new()
	lua.compile("score = 10")
	lua.run()
	lua.compile("score = score + 5")
	lua.run()
	var final_score = lua.get_global("score")
	var ok = (final_score == 15) and not lua.is_error()
	assert_test("Global State Persistence Across Consecutive Runs", ok, "score=%s" % final_score)

func test_reset_wipes_globals() -> void:
	var lua := GDLua.new()
	lua.set_global("persisted_var", 999)
	var before_reset = lua.get_global("persisted_var")
	lua.reset()
	var after_reset = lua.get_global("persisted_var")
	var ok = (before_reset == 999) and (after_reset == null) and not lua.is_error()
	assert_test("Reset Clears Global Variables", ok, "before=%s, after=%s" % [before_reset, after_reset])

func test_local_variable_access() -> void:
	test_local_variable_types()
	test_local_variable_stack_levels_and_shadowing()
	test_local_variable_control_flow()
	test_local_variable_nonexistent()

func test_local_variable_types() -> void:
	var lua := GDLua.new()
	lua.compile("""
		local v_int = 123
		local v_float = 45.67
		local v_str = "godot_lua"
		local v_bool = false
		local loop = true
		while loop do end
	""")
	lua.step(100, false)
	var get_initial_ok = (
		lua.get_local("v_int") == 123 and
		is_equal_approx(lua.get_local("v_float"), 45.67) and
		lua.get_local("v_str") == "godot_lua" and
		lua.get_local("v_bool") == false
	)
	var set_ok = (
		lua.set_local("v_int", 999) and
		lua.set_local("v_float", 12.34) and
		lua.set_local("v_str", "updated") and
		lua.set_local("v_bool", true)
	)
	var get_updated_ok = (
		lua.get_local("v_int") == 999 and
		is_equal_approx(lua.get_local("v_float"), 12.34) and
		lua.get_local("v_str") == "updated" and
		lua.get_local("v_bool") == true
	)
	# Setting unsupported type (like Dictionary) falls back to nil per C++ implementation
	var set_unsupported_ok = lua.set_local("v_str", {"key": "val"})
	var get_nil_ok = (lua.get_local("v_str") == null)

	lua.set_local("loop", false)
	lua.step(100, false)

	var ok = get_initial_ok and set_ok and get_updated_ok and set_unsupported_ok and get_nil_ok and not lua.is_running()
	assert_test("Local Variable Types & Nil Fallback", ok, "Types get/set mismatch")

func test_local_variable_stack_levels_and_shadowing() -> void:
	var lua := GDLua.new()
	lua.compile("""
		local function inner()
			local inner_val = 200
			local shadowed = "inner_value"
			local stop_inner = false
			while not stop_inner do end
		end

		local function outer(param_x)
			local outer_val = 100
			local shadowed = "outer_value"
			inner()
			final_outer = outer_val
			final_param = param_x
		end

		outer(42)
	""")
	lua.step(100, false)

	# 1. Level 0 vs Level 1 inspection & shadowing
	var inner_val = lua.get_local("inner_val")
	var outer_val = lua.get_local("outer_val")
	var param_x = lua.get_local("param_x")
	var shadowed_val = lua.get_local("shadowed") # Level 0 must shadow Level 1

	var inspect_ok = (inner_val == 200) and (outer_val == 100) and (param_x == 42) and (shadowed_val == "inner_value")

	# 2. Mutate across frames: modify outer_val and param_x at Level 1, then stop_inner at Level 0
	var set_outer_ok = lua.set_local("outer_val", 888)
	var set_param_ok = lua.set_local("param_x", 777)
	var set_stop_ok = lua.set_local("stop_inner", true)

	# 3. Resume execution to verify outer frame completed using modified values
	lua.run()
	var final_outer = lua.get_global("final_outer")
	var final_param = lua.get_global("final_param")

	var execution_resumed_ok = not lua.is_running() and (final_outer == 888) and (final_param == 777)
	var ok = inspect_ok and set_outer_ok and set_param_ok and set_stop_ok and execution_resumed_ok
	assert_test("Local Variable Call Stack & Shadowing", ok, "inner=%s, outer=%s, param=%s, shadow=%s, final_outer=%s, final_param=%s" % [inner_val, outer_val, param_x, shadowed_val, final_outer, final_param])

func test_local_variable_control_flow() -> void:
	var lua := GDLua.new()
	lua.compile("""
		local keep_running = true
		local iterations = 0
		while keep_running do
			iterations = iterations + 1
		end
		final_iterations = iterations
	""")
	lua.step(15, false)
	var was_running = lua.is_running()
	var initial_iter = lua.get_local("iterations")
	# Inject loop termination via set_local
	var set_exit = lua.set_local("keep_running", false)
	lua.run()
	var stopped_ok = not lua.is_running()
	var final_iter = lua.get_global("final_iterations")

	var ok = was_running and (initial_iter > 0) and set_exit and stopped_ok and (final_iter >= initial_iter)
	assert_test("Local Variable Control Flow Mutation", ok, "init_iter=%s, set_exit=%s, final_iter=%s" % [initial_iter, set_exit, final_iter])

func test_local_variable_nonexistent() -> void:
	var lua := GDLua.new()
	lua.compile("local a = 1; while true do end")
	lua.step(5, false)
	var get_nonexistent = lua.get_local("does_not_exist")
	var set_nonexistent = lua.set_local("does_not_exist", 42)
	lua.abort()

	var ok = (get_nonexistent == null) and (set_nonexistent == false)
	assert_test("Local Variable Nonexistent Handling", ok, "get=%s, set=%s" % [get_nonexistent, set_nonexistent])

# -----------------------------------------------------------------------------
# 4. Function Binding & Callables
# -----------------------------------------------------------------------------

func test_callable_bidirectional() -> void:
	var lua := GDLua.new()
	lua.register_function("multiply", func(a, b): return a * b)
	lua.compile("calc_result = multiply(6, 7)")
	lua.run()
	var result = lua.get_global("calc_result")
	assert_test("Callable Return Value to Lua", result == 42, "result=%s" % result)

func test_callable_return_types() -> void:
	var lua := GDLua.new()
	lua.register_function("get_string", func(): return "hello from godot")
	lua.register_function("get_float", func(): return 3.14159)
	lua.register_function("get_bool", func(): return true)
	lua.register_function("get_null", func(): return null)

	lua.compile("""
		res_str = get_string()
		res_float = get_float()
		res_bool = get_bool()
		res_null = get_null()
	""")
	lua.run()

	var r_str = lua.get_global("res_str")
	var r_float = lua.get_global("res_float")
	var r_bool = lua.get_global("res_bool")
	var r_null = lua.get_global("res_null")

	var ok = (r_str == "hello from godot") and is_equal_approx(r_float, 3.14159) and (r_bool == true) and (r_null == null) and not lua.is_error()
	assert_test("Callable Return Types (String, Float, Bool, Nil)", ok, "str=%s, float=%s, bool=%s, null=%s" % [r_str, r_float, r_bool, r_null])

func test_callable_multi_args() -> void:
	var lua := GDLua.new()
	var captured_args := []
	lua.register_function("take_mixed", func(i, f, s, b, n):
		captured_args.clear()
		captured_args.append_array([i, f, s, b, n])
		return "received"
	)
	lua.compile("status = take_mixed(42, 9.75, 'lua string', false, nil)")
	lua.run()

	var ok = (
		captured_args.size() == 5 and
		captured_args[0] == 42 and
		is_equal_approx(captured_args[1], 9.75) and
		captured_args[2] == "lua string" and
		captured_args[3] == false and
		captured_args[4] == null and
		lua.get_global("status") == "received" and
		not lua.is_error()
	)
	assert_test("Callable Multi-Argument Types Passing", ok, "args=%s, status=%s, err=%s" % [str(captured_args), lua.get_global("status"), lua.get_error()])

func test_callable_unsupported_return_type() -> void:
	var lua := GDLua.new()
	lua.register_function("bad_dict", func(): return {"a": 1})
	lua.compile("bad_dict()")
	await run_to_completion(lua)
	var dict_err_ok = lua.is_error() and lua.get_error().contains("unsupported return type 'Dictionary'")

	lua.reset()
	var dummy := DummyTarget.new()
	lua.register_function("bad_obj", func(): return dummy)
	lua.compile("bad_obj()")
	await run_to_completion(lua)
	dummy.free()
	var obj_err_ok = lua.is_error() and lua.get_error().contains("unsupported return type 'Object'")

	assert_test("Callable Unsupported Return Types", dict_err_ok and obj_err_ok, "dict_err=%s, obj_err=%s" % [dict_err_ok, obj_err_ok])

func test_argument_count_mismatch() -> void:
	var lua := GDLua.new()
	lua.register_function("add", dummy_add)
	lua.compile("add(42)")
	await run_to_completion(lua)
	assert_test("Callable Arg Count Mismatch", lua.is_error() and lua.get_error().contains("wrong number of arguments"), lua.get_error())

func test_unsupported_argument_type() -> void:
	var lua := GDLua.new()
	lua.register_function("add", dummy_add)
	lua.compile("add({x = 1}, 2)")
	await run_to_completion(lua)
	assert_test("Unsupported Arg Type (table)", lua.is_error() and lua.get_error().contains("unsupported argument type"), lua.get_error())

func test_freed_callable() -> void:
	var lua := GDLua.new()
	var dummy := DummyTarget.new()
	var freed_callable := Callable(dummy, "some_method")
	dummy.free()
	lua.register_function("call_freed", freed_callable)
	lua.compile("call_freed()")
	await run_to_completion(lua)
	assert_test("Freed Object Callable", lua.is_error() and lua.get_error().contains("callable is invalid or has been freed"), lua.get_error())

# -----------------------------------------------------------------------------
# 5. Asynchronous Signals (completed)
# -----------------------------------------------------------------------------

func test_async_signal_resumption() -> void:
	var lua := GDLua.new()
	lua.register_function("async_add", async_add)
	lua.compile("res = async_add(15, 25)")
	await run_to_completion(lua)
	var res = lua.get_global("res")
	assert_test("Async Signal Resumption", not lua.is_error() and (res == 40), "res=%s, err=%s" % [res, lua.get_error()])

func test_async_abort_disconnect() -> void:
	var lua := GDLua.new()
	lua.register_function("slow_async", slow_async)
	lua.compile("val = slow_async()")
	lua.step(10, false)
	var was_waiting = lua.is_waiting()
	lua.abort()
	var aborted_ok = not lua.is_running() and not lua.is_waiting() and not lua.is_error()
	await get_tree().create_timer(0.25).timeout
	var after_delay_ok = not lua.is_running() and not lua.is_waiting() and not lua.is_error()
	assert_test("Async abort() Signal Disconnect", was_waiting and aborted_ok and after_delay_ok, "abort failed")

func test_async_target_freed_safety() -> void:
	var lua := GDLua.new()
	var emitter := AsyncEmitter.new()
	lua.register_function("get_emitter", func(): return emitter)
	lua.compile("get_emitter()")
	lua.step(10, false)
	var was_waiting = lua.is_waiting()
	# Free target object while coroutine is listening
	emitter.free()
	# Abort should resolve target safely via ObjectID without crashing
	lua.abort()
	var aborted_ok = not lua.is_running() and not lua.is_error()
	assert_test("Async Target Freed ObjectDB Safety", was_waiting and aborted_ok, "Target freed crash/failure")

# -----------------------------------------------------------------------------
# 6. Memory Limits & Garbage Collection
# -----------------------------------------------------------------------------

func test_memory_limit_exceeded() -> void:
	var lua := GDLua.new()
	var baseline = lua.get_memory_used()
	lua.set_memory_limit(baseline + 2048)
	lua.compile("local t = {}; for i = 1, 10000 do t[i] = string.rep('A', 100) end")
	await run_to_completion(lua)
	assert_test("Memory Ceiling Limit Enforcement", lua.is_error() and lua.get_error().contains("not enough memory"), lua.get_error())

func test_memory_accounting_and_gc() -> void:
	var lua := GDLua.new()
	var start_mem = lua.get_memory_used()
	lua.compile("t = {}; for i = 1, 200 do t[i] = string.rep('x', 50) end")
	lua.run()
	var peak_mem = lua.get_memory_used()
	var allocated = peak_mem > start_mem

	lua.compile("t = nil; collectgarbage('collect')")
	lua.run()
	var after_gc_mem = lua.get_memory_used()
	var reclaimed = after_gc_mem < peak_mem
	assert_test("Memory Tracking & GC Reclamation", allocated and reclaimed, "start=%d, peak=%d, after_gc=%d" % [start_mem, peak_mem, after_gc_mem])

# -----------------------------------------------------------------------------
# 7. Multi-Instance Isolation
# -----------------------------------------------------------------------------

func test_multi_instance_isolation() -> void:
	var lua1 := GDLua.new()
	var lua2 := GDLua.new()
	lua1.set_global("inst_name", "Instance 1")
	lua2.set_global("inst_name", "Instance 2")
	var val1 = lua1.get_global("inst_name")
	var val2 = lua2.get_global("inst_name")
	assert_test("Multi-Instance Isolation", val1 == "Instance 1" and val2 == "Instance 2", "val1=%s, val2=%s" % [val1, val2])

# -----------------------------------------------------------------------------
# 8. Function Definition & Environment Isolation
# -----------------------------------------------------------------------------

func test_define_function_basic() -> void:
	var lua := GDLua.new()
	var ok = lua.define_function("add", "return arg[1] + arg[2]")
	assert_test("Define Function Basic - Registration", ok, lua.get_error())

	lua.compile("result = add(10, 25)")
	lua.run()
	var res = lua.get_global("result")
	assert_test("Define Function Basic - Execution", res == 35, "Expected 35, got %s, err: %s" % [str(res), lua.get_error()])

func test_define_function_environment_isolation() -> void:
	var lua := GDLua.new()
	var ok_a = lua.define_function("func_a", "x = 99; return x")
	var ok_b = lua.define_function("func_b", "return x")
	assert_test("Define Function Isolation - Setup", ok_a and ok_b, lua.get_error())

	lua.compile("res_a = func_a(); res_b = func_b()")
	lua.run()
	var res_a = lua.get_global("res_a")
	var res_b = lua.get_global("res_b")
	var global_x = lua.get_global("x")

	var isolated = (res_a == 99) and (res_b == null) and (global_x == null)
	assert_test("Define Function Isolation - Global Protection", isolated, "res_a=%s, res_b=%s, global_x=%s, err: %s" % [str(res_a), str(res_b), str(global_x), lua.get_error()])

func test_define_function_non_persistent_lifecycle() -> void:
	var lua := GDLua.new()
	lua.define_function("counter", "val = (val or 0) + 1; return val")

	lua.compile("c1 = counter(); c2 = counter()")
	lua.run()
	var c1 = lua.get_global("c1")
	var c2 = lua.get_global("c2")
	# Since local state resets each invocation, both c1 and c2 should be 1
	assert_test("Define Function Non-Persistent State", c1 == 1 and c2 == 1, "c1=%s, c2=%s" % [str(c1), str(c2)])

func test_define_function_hot_reloading() -> void:
	var lua := GDLua.new()
	lua.define_function("calc", "return arg[1] + arg[2]")
	lua.compile("r1 = calc(3, 4)")
	lua.run()
	var r1 = lua.get_global("r1")

	# Live redefine calc to multiplication
	lua.define_function("calc", "return arg[1] * arg[2]")
	lua.compile("r2 = calc(3, 4)")
	lua.run()
	var r2 = lua.get_global("r2")

	assert_test("Define Function Hot Reloading", r1 == 7 and r2 == 12, "r1=%s, r2=%s" % [str(r1), str(r2)])

func test_define_function_syntax_error() -> void:
	var lua := GDLua.new()
	var ok = lua.define_function("bad_func", "return arg[1] +")
	var err = lua.get_error()
	assert_test("Define Function Syntax Error Handling", not ok and err.contains("bad_func.lua"), "ok=%s, err=%s" % [str(ok), err])

func test_define_function_async_wait() -> void:
	var lua := GDLua.new()
	lua.register_function("async_add", async_add)
	lua.define_function("run_async", "return async_add(arg[1], arg[2])")

	lua.compile("res = run_async(40, 60)")
	await run_to_completion(lua)
	var res = lua.get_global("res")
	assert_test("Define Function Async Continuation Yielding", res == 100, "Expected 100, got %s" % str(res))

func test_define_function_stepping() -> void:
	var lua := GDLua.new()
	var fn_code := """local x = arg[1] + 1
local y = arg[2] * 2
return x + y"""
	var ok = lua.define_function("fn_calc", fn_code)
	assert_test("Define Function Stepping - Registration", ok, "Failed to define fn_calc")

	var caller_code := "res = fn_calc(10, 20)"
	lua.compile(caller_code, "@main.lua")

	# Step 1: Pauses before caller line 1
	lua.step(100, true)
	var s1_src = lua.get_current_source()
	var s1_line = lua.get_current_line()

	# Step 2: Enters fn_calc line 1 (local x = arg[1] + 1)
	lua.step(100, true)
	var s2_src = lua.get_current_source()
	var s2_line = lua.get_current_line()

	# Step 3: Enters fn_calc line 2 (local y = arg[2] * 2)
	lua.step(100, true)
	var s3_src = lua.get_current_source()
	var s3_line = lua.get_current_line()
	var x_val = lua.get_local("x")

	# Step 4: Enters fn_calc line 3 (return x + y)
	lua.step(100, true)
	var s4_src = lua.get_current_source()
	var s4_line = lua.get_current_line()
	var y_val = lua.get_local("y")

	# Run to completion
	lua.run()
	var res = lua.get_global("res")

	var cond = (
		s1_src == "@main.lua" and s1_line == 1 and
		s2_src == "fn_calc.lua" and s2_line == 1 and
		s3_src == "fn_calc.lua" and s3_line == 2 and x_val == 11 and
		s4_src == "fn_calc.lua" and s4_line == 3 and y_val == 40 and
		res == 51 and not lua.is_running() and not lua.is_error()
	)
	var detail = "s1=(%s:%d), s2=(%s:%d), s3=(%s:%d, x=%s), s4=(%s:%d, y=%s), res=%s, err=%s" % [
		s1_src, s1_line, s2_src, s2_line, s3_src, s3_line, str(x_val), s4_src, s4_line, str(y_val), str(res), lua.get_error()
	]
	assert_test("Define Function Line Stepping & Local Inspection", cond, detail)

func test_define_function_mid_stepping() -> void:
	var lua := GDLua.new()
	lua.define_function("dyn_func", "return 10")

	var caller_code := """v1 = dyn_func()
v2 = dyn_func()
v3 = brand_new_func(5)"""
	lua.compile(caller_code, "@caller.lua")

	# Step 1: Pauses before line 1
	lua.step(100, true)

	# Step 2: Enters dyn_func
	lua.step(100, true)
	var in_fn_src = lua.get_current_source()
	var in_fn_line = lua.get_current_line()

	# Step 3: Finishes dyn_func and pauses before caller line 2
	lua.step(100, true)
	var v1 = lua.get_global("v1")
	var v2_before = lua.get_global("v2")
	var caller_line2 = lua.get_current_line()
	var caller_src2 = lua.get_current_source()
	var is_paused_midway = lua.is_running()

	# While paused mid-execution:
	# 1. Hot-reload existing dyn_func to return 999 instead of 10
	var redef_ok = lua.define_function("dyn_func", "return 999")
	# 2. Define brand-new function that didn't exist when caller was compiled
	var def_new_ok = lua.define_function("brand_new_func", "return arg[1] * 100")

	# Resume execution of the SAME running thread to completion
	lua.run()
	var v2 = lua.get_global("v2")
	var v3 = lua.get_global("v3")
	var finished_ok = not lua.is_running() and not lua.is_error()

	var cond = (
		in_fn_src == "dyn_func.lua" and in_fn_line == 1 and
		v1 == 10 and
		v2_before == null and
		caller_line2 == 2 and caller_src2 == "@caller.lua" and
		is_paused_midway and
		redef_ok and def_new_ok and
		v2 == 999 and
		v3 == 500 and
		finished_ok
	)
	var detail = "in_fn=(%s:%d), v1=%s, line2=(%s:%d), v2=%s, v3=%s, err=%s" % [
		in_fn_src, in_fn_line, str(v1), caller_src2, caller_line2, str(v2), str(v3), lua.get_error()
	]
	assert_test("Define Function Mid-Stepping Definition & Hot-Reload", cond, detail)

func test_define_function_debug_info() -> void:
	var lua := GDLua.new()
	var code := """local x = arg[1] + 1
local y = arg[2] + 2
return x + y"""
	lua.define_function("dbg_calc", code)
	lua.compile("res = dbg_calc(10, 20)", "@main.lua")

	# Step 1: Pauses before main.lua:1
	lua.step(100, true)
	# Step 2: Enters dbg_calc line 1
	lua.step(100, true)
	# Step 3: Enters dbg_calc line 2
	lua.step(100, true)

	var info0 = lua.get_debug_info(0)

	lua.run()
	var res = lua.get_global("res")

	var ok = (
		info0.get("valid") == true and
		info0.get("source") == "dbg_calc.lua" and
		info0.get("short_source") == "[string \"dbg_calc.lua\"]" and
		info0.get("what") == "main" and
		info0.get("line_defined") == 0 and
		info0.get("last_line_defined") == 0 and
		info0.get("line") == 2 and
		res == 33 and not lua.is_running() and not lua.is_error()
	)
	var detail = "valid=%s, src=%s, short_src=%s, what=%s, line=%s, def=%s-%s, res=%s, err=%s" % [
		info0.get("valid"), info0.get("source"), info0.get("short_source"), info0.get("what"), info0.get("line"),
		info0.get("line_defined"), info0.get("last_line_defined"), str(res), lua.get_error()
	]
	assert_test("Define Function Debug Info Inspection", ok, detail)

func test_define_function_nested_call_stack() -> void:
	var lua := GDLua.new()
	var code_b := """local q = arg[1] * 2
return q"""
	var code_a := """local p = func_b(arg[1])
return p + 1"""

	lua.define_function("func_b", code_b)
	lua.define_function("func_a", code_a)

	lua.compile("out = func_a(5)", "@main.lua")

	# Step 1: Pauses before main.lua:1
	lua.step(100, true)
	# Step 2: Enters func_a line 1
	lua.step(100, true)
	# Step 3: Enters func_b line 1
	lua.step(100, true)

	var l0_src = lua.get_current_source(0)
	var l0_line = lua.get_current_line(0)

	var found_func_a = false
	var func_a_line = -1
	var found_main = false
	var main_line = -1

	for lvl in range(1, 10):
		var src = lua.get_current_source(lvl)
		var ln = lua.get_current_line(lvl)
		if src == "func_a.lua":
			found_func_a = true
			func_a_line = ln
		elif src == "@main.lua":
			found_main = true
			main_line = ln

	lua.run()
	var out = lua.get_global("out")

	var ok = (
		l0_src == "func_b.lua" and l0_line == 1 and
		found_func_a and func_a_line == 1 and
		found_main and main_line == 1 and
		out == 11 and not lua.is_running() and not lua.is_error()
	)
	var detail = "l0=(%s:%d), func_a=(%s:%d), main=(%s:%d), out=%s, err=%s" % [
		l0_src, l0_line, str(found_func_a), func_a_line, str(found_main), main_line, str(out), lua.get_error()
	]
	assert_test("Define Function Multi-Level Call Stack", ok, detail)

func test_define_function_runtime_error_line() -> void:
	var lua := GDLua.new()
	var code := """local a = 1
local obj = nil
obj.trigger_crash = 42
return a"""
	lua.define_function("crash_func", code)
	lua.compile("crash_func()", "@caller.lua")

	lua.run()

	var is_err = lua.is_error()
	var err_msg = lua.get_error()

	var exact_line = err_msg.contains("[string \"crash_func.lua\"]:3:") and err_msg.contains("attempt to index a nil value")
	assert_test("Define Function 1:1 Runtime Error Line", is_err and exact_line, "err=%s" % err_msg)

func test_define_function_params_and_multi_return() -> void:
	var lua := GDLua.new()
	var code := """local count = arg.n
return arg[1] or "default", (arg[2] or 0) * 10, count"""

	lua.define_function("multi_test", code)

	# Call 1: Fewer args than declared (arg[1] provided, arg[2] omitted -> nil)
	lua.compile("r1, r2, r3 = multi_test('hello')")
	lua.run()
	var r1 = lua.get_global("r1")
	var r2 = lua.get_global("r2")
	var r3 = lua.get_global("r3")

	# Call 2: Extra args passed
	lua.compile("e1, e2, e3 = multi_test('val', 5, 'ignore', 10, 20, 30)")
	lua.run()
	var e1 = lua.get_global("e1")
	var e2 = lua.get_global("e2")
	var e3 = lua.get_global("e3")

	var ok = (
		r1 == "hello" and r2 == 0 and r3 == 1 and
		e1 == "val" and e2 == 50 and e3 == 6 and
		not lua.is_error()
	)
	var detail = "r1=%s, r2=%s, r3=%s, e1=%s, e2=%s, e3=%s, err=%s" % [
		str(r1), str(r2), str(r3), str(e1), str(e2), str(e3), lua.get_error()
	]
	assert_test("Define Function Parameter Mismatches & Multi-Return", ok, detail)

func test_define_function_mutual_recursion() -> void:
	var lua := GDLua.new()
	var code_even := """if arg[1] == 0 then return true end
return is_odd(arg[1] - 1)"""
	var code_odd := """if arg[1] == 0 then return false end
return is_even(arg[1] - 1)"""

	lua.define_function("is_even", code_even)
	lua.define_function("is_odd", code_odd)

	lua.compile("e4 = is_even(4); o4 = is_odd(4); e5 = is_even(5); o5 = is_odd(5)")
	lua.run()

	var e4 = lua.get_global("e4")
	var o4 = lua.get_global("o4")
	var e5 = lua.get_global("e5")
	var o5 = lua.get_global("o5")

	var ok = (e4 == true) and (o4 == false) and (e5 == false) and (o5 == true) and not lua.is_error()
	var detail = "e4=%s, o4=%s, e5=%s, o5=%s, err=%s" % [str(e4), str(o4), str(e5), str(o5), lua.get_error()]
	assert_test("Define Function Mutual Recursion", ok, detail)

func test_define_function_custom_chunk_name() -> void:
	var lua := GDLua.new()
	var code := "return 42"
	var custom_name := "@sensors/radar.lua"
	var ok = lua.define_function("read_radar", code, custom_name)

	lua.compile("val = read_radar()", "@system.lua")

	# Step 1: main line 1
	lua.step(100, true)
	# Step 2: enters read_radar
	lua.step(100, true)
	var active_src = lua.get_current_source()

	lua.run()
	var val = lua.get_global("val")

	var cond = ok and (active_src == custom_name) and (val == 42) and not lua.is_error()
	assert_test("Define Function Custom Chunk Name", cond, "ok=%s, src=%s, val=%s, err=%s" % [ok, active_src, str(val), lua.get_error()])

func test_define_function_arg_table_indexing() -> void:
	var lua := GDLua.new()
	var code := """
	return arg[1], arg[2], arg[3], arg[0], arg[4], arg.n, (arg[1] + arg[2] + arg[3])
	"""
	var ok = lua.define_function("sum3", code)
	assert_test("Define Function arg[] 1-based Indexing - Registration", ok, lua.get_error())

	lua.compile("r1, r2, r3, r0, r4, rn, total = sum3(10, 20, 30)")
	lua.run()

	var r0 = lua.get_global("r0")
	var r1 = lua.get_global("r1")
	var r2 = lua.get_global("r2")
	var r3 = lua.get_global("r3")
	var r4 = lua.get_global("r4")
	var rn = lua.get_global("rn")
	var total = lua.get_global("total")

	var cond = (
		r0 == null and
		r1 == 10 and
		r2 == 20 and
		r3 == 30 and
		r4 == null and
		rn == 3 and
		total == 60 and
		not lua.is_error()
	)
	var detail = "arg[0]=%s, arg[1]=%s, arg[2]=%s, arg[3]=%s, arg[4]=%s, arg.n=%s, total=%s, err=%s" % [
		str(r0), str(r1), str(r2), str(r3), str(r4), str(rn), str(total), lua.get_error()
	]
	assert_test("Define Function arg[1], arg[2], arg[3] Access & 1-Based Table Indexing", cond, detail)
