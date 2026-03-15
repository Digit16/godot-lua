#include "gdlua_class.h"

extern "C" {
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
}

void GDLua::_bind_methods() {
	godot::ClassDB::bind_method(D_METHOD("print_type", "variant"), &GDLua::print_type);
}

void GDLua::print_type(const Variant &p_variant) const {
	lua_State *L = luaL_newstate();
    luaL_openlibs(L);
    luaL_dostring(L, "print('Hello from Lua inside Godot extension!')");
    lua_close(L);
	
	print_line(vformat("Type: %d", p_variant.get_type()));
}
