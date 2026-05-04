#include "gdlua_class.h"
#include "gdlua_methods.h"

#include "godot_cpp/core/error_macros.hpp"
#include "godot_cpp/core/print_string.hpp"


/* HELPERS ---------------------------------------------------------------------------------------- */

static int lua_push_godot_variant(lua_State *L, Variant val) {
    switch (val.get_type()) {
        case Variant::INT:    lua_pushinteger(L, (lua_Integer)val); return 1;
        case Variant::FLOAT:  lua_pushnumber(L, (lua_Number)val);   return 1;
        case Variant::BOOL:   lua_pushboolean(L, (bool)val);        return 1;
        case Variant::STRING: lua_pushstring(L, String(val).utf8().get_data()); return 1;
        case Variant::NIL:    return 0;
        default: break;
    }
    
    if (val.get_type() == Variant::OBJECT) {
        godot::Object* obj = val;
        return luaL_error(L, "unsupported return type 'Object' (class: '%s')",
            obj->get_class().utf8().get_data());
        }
    return luaL_error(L, "unsupported return type '%s'",
        Variant::get_type_name(val.get_type()).utf8().get_data());
}

static int resume_wrapper(lua_State *L) {
    const Variant *var = (const Variant *)lua_touserdata(L, lua_upvalueindex(1));
    return lua_push_godot_variant(L, *var);
}

/* GODOT BINDINGS --------------------------------------------------------------------------------- */

void GDLua::_bind_methods() {
    godot::ClassDB::bind_method(D_METHOD("register_function", "name", "callable"), &GDLua::register_function);
	godot::ClassDB::bind_method(D_METHOD("execute", "code"),                       &GDLua::execute);
    godot::ClassDB::bind_method(D_METHOD("is_valid"),                              &GDLua::is_valid);
    godot::ClassDB::bind_method(D_METHOD("is_running"),                            &GDLua::is_running);
    godot::ClassDB::bind_method(D_METHOD("is_waiting"),                            &GDLua::is_waiting);
    godot::ClassDB::bind_method(D_METHOD("get_error"),                             &GDLua::get_error);
    godot::ClassDB::bind_method(D_METHOD("clear_error"),                           &GDLua::clear_error);
    godot::ClassDB::bind_method(D_METHOD("is_error"),                              &GDLua::is_error);
    godot::ClassDB::bind_method(D_METHOD("get_memory_used"),                       &GDLua::get_memory_used);
    godot::ClassDB::bind_method(D_METHOD("get_memory_limit"),                      &GDLua::get_memory_limit);
    godot::ClassDB::bind_method(D_METHOD("set_memory_limit", "limit"),             &GDLua::set_memory_limit);
    godot::ClassDB::bind_method(D_METHOD("reset"),                                 &GDLua::reset);
    godot::ClassDB::bind_method(D_METHOD("compile", "code"),                       &GDLua::compile);
    godot::ClassDB::bind_method(D_METHOD("step", "steps", "line"),                 &GDLua::step);
    godot::ClassDB::bind_method(D_METHOD("run"),                                   &GDLua::run);
    godot::ClassDB::bind_method(D_METHOD("abort"),                                 &GDLua::abort);
}

/* CONSTRUCTOR / DESCRUCTOR ----------------------------------------------------------------------- */

GDLua::GDLua()  { start(); }
GDLua::~GDLua() { close(); }

/* PUBLIC API ------------------------------------------------------------------------------------- */

void GDLua::register_function(String name, Callable cb) {
    Callable *stored = memnew(Callable(cb));
    lua_pushlightuserdata(L, stored);
    lua_pushlightuserdata(L, this);
    lua_pushcclosure(L, _lua_callable_dispatch, 2);
    lua_setglobal(L, name.utf8().get_data());
}

/* Create method that runs given string as lua code */
bool GDLua::execute(const String &code) { return compile(code) && run(); }

bool GDLua::is_valid()    { return L != nullptr;}
bool GDLua::is_running()  { return _running;}
bool GDLua::is_waiting()  { return _waiting;}

String GDLua::get_error() { return _error_message;}
void   GDLua::clear_error() { _error_message = "";}
bool   GDLua::is_error() { return !_error_message.is_empty(); }

size_t GDLua::get_memory_used()              { return alloc_data.used; }
size_t GDLua::get_memory_limit()             { return alloc_data.size; }
void   GDLua::set_memory_limit(size_t limit) { alloc_data.size = limit; }

bool GDLua::reset() { return close() && start(); }

bool GDLua::compile(const String &p_code) {
    /* throw error if not initialized*/
	ERR_FAIL_COND_V_MSG(L == nullptr, false, "Lua state is not initialized");
    
    /* close thread if previous exists*/
    close_thread();

    /* get ASCII code (utf-8 segments will be treated as next ASCII chars) */ 
    CharString code_utf8 = p_code.utf8();
    const char *code = code_utf8.get_data();

    /* create new thread */
    L_co = lua_newthread(L);
    L_co_ref = luaL_ref(L, LUA_REGISTRYINDEX);

    /* compile code */
    if (luaL_loadstring(L_co, code) != LUA_OK) {
        _running = false;
        save_lua_error(L_co);
        return false;
    } 

    _running = true;
    return true;
}

bool GDLua::step(int steps, bool line) {
    /* skip if not running */
    if (!_running) return true;
    if (_waiting) return true;

    /* throw error if no thread exists */
    ERR_FAIL_COND_V_MSG(L_co == nullptr, false, "Lua uninitialized state is in running state");

    /* configure hook mask */
    int mask = 0;
    if (steps > 0) mask |= LUA_MASKCOUNT;
    if (line) mask |= LUA_MASKLINE;
    lua_sethook(L_co, yield_hook, mask, steps);

    /* run until hook or yield */
    int argc = 0;
    if (_pending_resume) {
        _pending_resume = false;

        lua_pushlightuserdata(L_co, &_pending_value);
        lua_pushcclosure(L_co, resume_wrapper, 1);
        
        if (lua_pcall(L_co, 0, 1, 0) != LUA_OK) {
            /* add debug info to error */
            luaL_where(L_co, 1);
            lua_pushvalue(L_co, -2);
            lua_concat(L_co, 2); 
            save_lua_error(L_co);
            _running = false;
            return false;
        }
        argc = 1;
    }
    int nresults = 0;
    int status = lua_resume(L_co, NULL, argc, &nresults);

    /* check run status */
    if (status == LUA_YIELD) {
        /* ignore all yielded values */
        lua_pop(L_co, nresults);
    } else if (status == LUA_OK) {
        /* process stopped successfully */
        _running = false;
    } else {
        /* process failed with an error */
        _running = false;
        save_lua_error(L_co);
        return false;
    }

    /* return success */
    return true;
}

bool GDLua::run()   { return step(-1, false); }
bool GDLua::abort() { return close_thread(); }

/* PRIVATE API ------------------------------------------------------------------------------------ */

void GDLua::_resume_coroutine(Variant value) {
    _waiting        = false;
    _pending_resume = true;
    _pending_value  = value;
}

void GDLua::disconnect_pending() {
    if (_pending_signal_source && _pending_signal_source->has_signal("completed")) {
        _pending_signal_source->disconnect("completed", callable_mp(this, &GDLua::_resume_coroutine));
        _pending_signal_source = nullptr;
    }
}

bool GDLua::start() {
    if (L) return true;
    L = lua_newstate(gdlua_bounded_alloc, &alloc_data, 0);
    if (!L) { set_error("failed to create lua state"); return false; }
    luaopen_base(L);
    return true;
}

bool GDLua::close() {
	if (!L) return true;
    disconnect_pending();
    lua_close(L);
    L = nullptr;
    return true;
}

bool GDLua::close_thread() {
    if (L_co == nullptr) return true;
    _running = false;
    disconnect_pending();
    bool ok = lua_closethread(L_co, nullptr) == LUA_OK;
    if (!ok) save_lua_error(L_co);
    luaL_unref(L, LUA_REGISTRYINDEX, L_co_ref);
    L_co_ref = LUA_NOREF;
    L_co = nullptr;
    return ok;
}

void GDLua::set_error(const String &error) {
    _error_message = error;
    ERR_PRINT(_error_message);
}

void GDLua::save_lua_error(lua_State *state) {
    if (state == nullptr) {
        set_error("unknown");
        return;
    }
    const char *err = lua_tostring(state, -1);
    set_error(err ? err : "unknown");
    lua_pop(state, 1);
}

int _lua_callable_dispatch(lua_State *L) {
    Callable *cb   = (Callable *)lua_touserdata(L, lua_upvalueindex(1));
    GDLua    *self = (GDLua *)   lua_touserdata(L, lua_upvalueindex(2));

    if (!cb || !cb->is_valid()) {
        return luaL_error(L, "callable is invalid or has been freed");
    }

    int expected = cb->get_argument_count();
    int argc     = lua_gettop(L);

    if (expected >= 0 && argc != expected) {
        return luaL_error(L, "wrong number of arguments (expected %d, got %d)", expected, argc);
    }

    Array godot_args;
    for (int i = 1; i <= argc; i++) {
        if      (lua_isnumber(L, i))  { godot_args.push_back(lua_tonumber(L, i)); }
        else if (lua_isstring(L, i))  { godot_args.push_back(String(lua_tostring(L, i))); }
        else if (lua_isboolean(L, i)) { godot_args.push_back((bool)lua_toboolean(L, i)); }
        else if (lua_isnil(L, i))     { godot_args.push_back(Variant()); }
        else return luaL_error(L, "unsupported argument type '%s' at index %d",
                luaL_typename(L, i), i);
    }

    Variant ret = cb->callv(godot_args);

    if (ret.get_type() == Variant::OBJECT) {
        godot::Object* obj = ret;
        if (obj->has_signal("completed")) {
            self->_pending_signal_source = obj;
            obj->connect("completed", callable_mp(self, &GDLua::_resume_coroutine));
            self->_waiting = true;
            return lua_yield(L, 0);
        }
    }

    return lua_push_godot_variant(L, ret);
}