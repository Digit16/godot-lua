#pragma once

#include "godot_cpp/classes/ref_counted.hpp"
#include "godot_cpp/classes/wrapped.hpp"
#include "godot_cpp/variant/variant.hpp"
#include "godot_cpp/variant/dictionary.hpp"
#include "godot_cpp/variant/packed_string_array.hpp"
#include "godot_cpp/variant/array.hpp"

extern "C" {
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
}

#include "gdlua_methods.h"

using namespace godot;


class GDLua : public RefCounted {
	GDCLASS(GDLua, RefCounted)

protected:
	static void _bind_methods();

public:
	static bool log_error;
	static bool log_alloc;

	static void set_error_logging(bool enable);
	static bool get_error_logging();
	static void set_alloc_logging(bool enable);
	static bool get_alloc_logging();

	GDLua();
	~GDLua() override;

	void register_function(String name, Callable cb);
	bool execute(const String &p_code, const String &p_chunk_name = "chunk");

	bool is_valid(); 
	bool is_running();
	bool is_waiting();

	String get_error();
	void clear_error();
	bool is_error();

	size_t get_memory_used();
	size_t get_memory_limit();
	void   set_memory_limit(size_t limit);

	Variant get_global(const String &name);
	bool    set_global(const String &name, Variant value);
	Variant get_local(const String &name);
	bool    set_local(const String &name, Variant value);

	bool reset();
	bool compile(const String &p_code, const String &p_chunk_name = "chunk");
	bool step(int steps=1, bool line=false);
	bool run();
	bool abort();

	bool define_function(const String &name, const String &code, const String &chunk_name = "");

	int        get_current_line(int level = 0);
	String     get_current_source(int level = 0);
	Dictionary get_debug_info(int level = 0);
	
private:
	lua_State *L       = nullptr;
	lua_State *L_co    = nullptr;
	int        L_co_ref = LUA_NOREF;

	gdlua_alloc_data alloc_data = {0, 1000000};

	bool _running        = false;
	bool _waiting        = false;
	bool _pending_resume = false;
	String  _error_message{};
	Variant _pending_value{};
	uint64_t _pending_signal_source_id = 0;

	void _resume_coroutine(Variant value);
	void disconnect_pending();
	
	bool start();
	bool close();
	bool close_thread();
	
	void set_error(const String &error);
	void save_lua_error(lua_State *state);

	friend int _lua_callable_dispatch(lua_State *L);
};
