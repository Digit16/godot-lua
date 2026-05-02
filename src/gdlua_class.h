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

	lua_State *L = nullptr;
	lua_State *L_co = nullptr;
	int L_co_ref = LUA_NOREF;

	gdlua_alloc_data alloc_data = {0, 1000000};

	bool _running = false;
	String error_message = String("");

	bool _waiting = false;
	bool _pending_resume = false;
	Variant _pending_value;

	void _resume_coroutine(Variant value);

	friend int lua_callable_dispatch(lua_State *L);

public:
	GDLua();
	~GDLua() override;

	void register_function(String name, Callable cb);

	bool execute(const String &p_code);

	bool is_valid(); 
	bool is_running();

	String get_error();
	void clear_error();
	bool is_error();

	bool reset();
	
	bool compile(const String &p_code);
	bool step(int steps=1, bool line=false);
	bool run();
	bool abort();
	
private:
	bool start();
	bool close();

	void set_error(const String &error);
	bool close_thread();
	void save_lua_error(lua_State *state);
};
