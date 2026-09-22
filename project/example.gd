extends Node

func async_wait_step():
	await get_tree().create_timer(1.0).timeout
	return "async_done"

func _ready() -> void:
	var lua := GDLua.new()
	lua.register_function("async_wait_step", async_wait_step)

	var lua_code := """-- Line 1: Setup
local counter = 10 -- Line 2
local factor = 3 -- Line 3

function inner_worker(val) -- Line 5
	local bonus = 5 -- Line 6
	local subtotal = (val * factor) + bonus -- Line 7
	local wait_res = async_wait_step() -- Line 8
	return subtotal -- Line 9
end -- Line 10

function outer_task(start_num) -- Line 12
	local offset = 100 -- Line 13
	local result = inner_worker(start_num) -- Line 14
	return result + offset -- Line 15
end -- Line 16

final_result = outer_task(counter) -- Line 18
"""

	lua.compile(lua_code, "@res://scripts/example_pipeline.lua")

	print("========================================")
	print("       GDLua Breakpoint Debug Demo       ")
	print("========================================")
	print("Tip: Place breakpoints on lines marked with '# [BREAKPOINT]' to inspect variables.\n")

	# -------------------------------------------------------------------------
	# Part 1: Top-level line-by-line stepping & local variable inspection
	# -------------------------------------------------------------------------
	print("--- Part 1: Stepping top-level lines ---")
	while lua.is_running() and lua.get_current_line() < 5:
		lua.step(1, true)
		var cur_line := lua.get_current_line()
		var cur_source := lua.get_current_source()
		var debug_info := lua.get_debug_info()
		var local_counter = lua.get_local("counter")
		var local_factor = lua.get_local("factor")
		# [BREAKPOINT]: Inspect cur_line, cur_source, debug_info, local_counter, local_factor
		print("  Line %d | counter=%s, factor=%s | func='%s'" % [
			cur_line, str(local_counter), str(local_factor), debug_info.get("function", "")
		])

	# -------------------------------------------------------------------------
	# Part 2: Inspecting Call Stack Frames (Level 0 vs Level 1)
	# -------------------------------------------------------------------------
	print("\n--- Part 2: Stepping into nested function call stack ---")
	# Step into outer_task and then into inner_worker until line 8
	while lua.is_running() and lua.get_current_line() < 8:
		lua.step(1, true)
		var frame0_line := lua.get_current_line(0)
		var frame0_info := lua.get_debug_info(0)
		var frame1_line := lua.get_current_line(1)
		var frame1_info := lua.get_debug_info(1)

		var local_bonus = lua.get_local("bonus")
		var local_offset = lua.get_local("offset")
		# [BREAKPOINT]: Inspect Frame 0 (inner_worker) vs Frame 1 (outer_task)
		print("  Frame 0: line %d in '%s()' | Frame 1: line %d in '%s()'" % [
			frame0_line, frame0_info.get("function", ""),
			frame1_line, frame1_info.get("function", "")
		])

	# -------------------------------------------------------------------------
	# Part 3: Inspecting While Paused in Async Wait State
	# -------------------------------------------------------------------------
	print("\n--- Part 3: Inspecting Async Wait State ---")
	if not lua.is_waiting():
		lua.step(1, true)

	var is_waiting := lua.is_waiting()
	var waiting_line := lua.get_current_line()
	var waiting_debug := lua.get_debug_info()
	# [BREAKPOINT]: Inspect state while waiting on async timer
	print("  Waiting on signal: %s | Line: %d | Func: '%s'" % [
		str(is_waiting), waiting_line, waiting_debug.get("function", "")
	])

	# Resume after async completion
	while lua.is_waiting():
		await get_tree().create_timer(0.1).timeout

	# -------------------------------------------------------------------------
	# Part 4: Resuming & Final State Inspection
	# -------------------------------------------------------------------------
	lua.run()
	var final_val = lua.get_global("final_result")
	var is_finished := not lua.is_running()
	# [BREAKPOINT]: Inspect final execution state
	print("\n--- Part 4: Completion ---")
	print("  Finished: %s | final_result: %s (expected: 135)" % [str(is_finished), str(final_val)])
	print("========================================")
