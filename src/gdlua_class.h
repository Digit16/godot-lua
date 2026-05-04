#pragma once

#include "godot_cpp/classes/ref_counted.hpp"
#include "godot_cpp/classes/wrapped.hpp"
#include "godot_cpp/variant/variant.hpp"

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
	GDLua();
	~GDLua() override;

	void register_function(String name, Callable cb);
	bool execute(const String &p_code);

	bool is_valid(); 
	bool is_running();
	bool is_waiting();

	String get_error();
	void clear_error();
	bool is_error();

	size_t get_memory_used();
	size_t get_memory_limit();
	void   set_memory_limit(size_t limit);

	bool reset();
	bool compile(const String &p_code);
	bool step(int steps=1, bool line=false);
	bool run();
	bool abort();
	
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
	godot::Object *_pending_signal_source = nullptr;

	void _resume_coroutine(Variant value);
	void disconnect_pending();
	
	bool start();
	bool close();
	bool close_thread();
	
	void set_error(const String &error);
	void save_lua_error(lua_State *state);

	friend int _lua_callable_dispatch(lua_State *L);
};
