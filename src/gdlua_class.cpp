#include "gdlua_class.h"
#include "gdlua_methods.h"

#include "godot_cpp/core/error_macros.hpp"
#include "godot_cpp/core/print_string.hpp"
#include "godot_cpp/core/object.hpp"


/* HELPERS ---------------------------------------------------------------------------------------- */

static bool lua_push_godot_variant(lua_State *L, Variant val) {
    switch (val.get_type()) {
        case Variant::INT:    lua_pushinteger(L, (lua_Integer)val); return true;
        case Variant::FLOAT:  lua_pushnumber(L,  (lua_Number)val);  return true;
        case Variant::BOOL:   lua_pushboolean(L, (bool)val);        return true;
        case Variant::STRING: lua_pushstring(L, String(val).utf8().get_data()); return true;
        case Variant::NIL:    lua_pushnil(L);                       return true;
        default:              return false;
    }
}

static int lua_push_godot_variant_or_error(lua_State *L, Variant val) {
    if (lua_push_godot_variant(L, val)) return 1;

    if (val.get_type() == Variant::OBJECT) {
        godot::Object *obj = val;
        return luaL_error(L, "unsupported return type 'Object' (class: '%s')",
            obj->get_class().utf8().get_data());
    }
    return luaL_error(L, "unsupported return type '%s'",
        Variant::get_type_name(val.get_type()).utf8().get_data());
}

static int resume_wrapper(lua_State *L) {
    const Variant *var = (const Variant *)lua_touserdata(L, lua_upvalueindex(1));
    return lua_push_godot_variant_or_error(L, *var);
}

static Variant lua_get_godot_variant(lua_State *L, int idx) {
    switch (lua_type(L, idx)) {
        case LUA_TBOOLEAN: return Variant((bool)lua_toboolean(L, idx));
        case LUA_TNUMBER:
            if (lua_isinteger(L, idx)) return Variant((int64_t)lua_tointeger(L, idx));
            return Variant((double)lua_tonumber(L, idx));
        case LUA_TSTRING:  return Variant(String(lua_tostring(L, idx)));
        case LUA_TNIL:
        default:           return Variant();
    }
}

/* GODOT BINDINGS --------------------------------------------------------------------------------- */

bool GDLua::log_error = false;
bool GDLua::log_alloc = false;

void GDLua::set_error_logging(bool enable) { log_error = enable; }
bool GDLua::get_error_logging()            { return log_error; }
void GDLua::set_alloc_logging(bool enable) { log_alloc = enable; }
bool GDLua::get_alloc_logging()            { return log_alloc; }

void GDLua::_bind_methods() {
    godot::ClassDB::bind_static_method("GDLua", D_METHOD("set_error_logging", "enable"), &GDLua::set_error_logging);
    godot::ClassDB::bind_static_method("GDLua", D_METHOD("get_error_logging"),           &GDLua::get_error_logging);
    godot::ClassDB::bind_static_method("GDLua", D_METHOD("set_alloc_logging", "enable"), &GDLua::set_alloc_logging);
    godot::ClassDB::bind_static_method("GDLua", D_METHOD("get_alloc_logging"),           &GDLua::get_alloc_logging);

    godot::ClassDB::bind_method(D_METHOD("register_function", "name", "callable"), &GDLua::register_function);
	godot::ClassDB::bind_method(D_METHOD("execute", "code", "chunk_name"),         &GDLua::execute, DEFVAL("chunk"));
    godot::ClassDB::bind_method(D_METHOD("is_valid"),                              &GDLua::is_valid);
    godot::ClassDB::bind_method(D_METHOD("is_running"),                            &GDLua::is_running);
    godot::ClassDB::bind_method(D_METHOD("is_waiting"),                            &GDLua::is_waiting);
    godot::ClassDB::bind_method(D_METHOD("get_error"),                             &GDLua::get_error);
    godot::ClassDB::bind_method(D_METHOD("clear_error"),                           &GDLua::clear_error);
    godot::ClassDB::bind_method(D_METHOD("is_error"),                              &GDLua::is_error);
    godot::ClassDB::bind_method(D_METHOD("get_memory_used"),                       &GDLua::get_memory_used);
    godot::ClassDB::bind_method(D_METHOD("get_memory_limit"),                      &GDLua::get_memory_limit);
    godot::ClassDB::bind_method(D_METHOD("set_memory_limit", "limit"),             &GDLua::set_memory_limit);
    godot::ClassDB::bind_method(D_METHOD("get_global", "name"),                    &GDLua::get_global);
    godot::ClassDB::bind_method(D_METHOD("set_global", "name", "value"),           &GDLua::set_global);
    godot::ClassDB::bind_method(D_METHOD("get_local",  "name"),                    &GDLua::get_local);
    godot::ClassDB::bind_method(D_METHOD("set_local",  "name", "value"),           &GDLua::set_local);
    godot::ClassDB::bind_method(D_METHOD("reset"),                                 &GDLua::reset);
    godot::ClassDB::bind_method(D_METHOD("compile", "code", "chunk_name"),         &GDLua::compile, DEFVAL("chunk"));
    godot::ClassDB::bind_method(D_METHOD("step", "steps", "line"),                 &GDLua::step, DEFVAL(1), DEFVAL(false));
    godot::ClassDB::bind_method(D_METHOD("run"),                                   &GDLua::run);
    godot::ClassDB::bind_method(D_METHOD("abort"),                                 &GDLua::abort);
    godot::ClassDB::bind_method(D_METHOD("get_current_line",   "level"),           &GDLua::get_current_line,   DEFVAL(0));
    godot::ClassDB::bind_method(D_METHOD("get_current_source", "level"),           &GDLua::get_current_source, DEFVAL(0));
    godot::ClassDB::bind_method(D_METHOD("get_debug_info",     "level"),           &GDLua::get_debug_info,     DEFVAL(0));
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
bool GDLua::execute(const String &code, const String &chunk_name) { return compile(code, chunk_name) && run(); }

bool GDLua::is_valid()    { return L != nullptr;}
bool GDLua::is_running()  { return _running;}
bool GDLua::is_waiting()  { return _waiting;}

String GDLua::get_error() { return _error_message;}
void   GDLua::clear_error() { _error_message = "";}
bool   GDLua::is_error() { return !_error_message.is_empty(); }

size_t GDLua::get_memory_used()              { return alloc_data.used; }
size_t GDLua::get_memory_limit()             { return alloc_data.size; }
void   GDLua::set_memory_limit(size_t limit) { alloc_data.size = limit; }

Variant GDLua::get_global(const String &name) {
    ERR_FAIL_COND_V_MSG(L == nullptr, Variant(), "Lua state is not initialized");
    lua_State *state = L_co ? L_co : L;

    lua_getglobal(state, name.utf8().get_data());
    Variant result = lua_get_godot_variant(state, -1);
    lua_pop(state, 1);
    return result;
}

bool GDLua::set_global(const String &name, Variant value) {
    ERR_FAIL_COND_V_MSG(L == nullptr, false, "Lua state is not initialized");
    lua_State *state = L_co ? L_co : L;

    if (lua_push_godot_variant(state, value) == 0)
        lua_pushnil(state);
    lua_setglobal(state, name.utf8().get_data());
    return true;
}

Variant GDLua::get_local(const String &name) {
    ERR_FAIL_COND_V_MSG(L_co == nullptr, Variant(), "No active coroutine thread");
    const char *cname = name.utf8().get_data();

    for (int level = 0; ; level++) {
        lua_Debug ar;
        if (lua_getstack(L_co, level, &ar) == 0) break;

        for (int i = 1; ; i++) {
            const char *local_name = lua_getlocal(L_co, &ar, i);
            if (!local_name) break;
            if (strcmp(local_name, cname) == 0) {
                Variant result = lua_get_godot_variant(L_co, -1);
                lua_pop(L_co, 1);
                return result;
            }
            lua_pop(L_co, 1);
        }
    }
    return Variant();
}

bool GDLua::set_local(const String &name, Variant value) {
    ERR_FAIL_COND_V_MSG(L_co == nullptr, false, "No active coroutine thread");
    const char *cname = name.utf8().get_data();

    for (int level = 0; ; level++) {
        lua_Debug ar;
        if (lua_getstack(L_co, level, &ar) == 0) break;

        for (int i = 1; ; i++) {
            const char *local_name = lua_getlocal(L_co, &ar, i);
            if (!local_name) break;
            if (strcmp(local_name, cname) == 0) {
                lua_pop(L_co, 1); // pop the fetched value
                if (lua_push_godot_variant(L_co, value) == 0)
                    lua_pushnil(L_co);
                lua_setlocal(L_co, &ar, i);
                return true;
            }
            lua_pop(L_co, 1);
        }
    }
    return false;
}

bool GDLua::reset() { return close() && start(); }

bool GDLua::compile(const String &p_code, const String &p_chunk_name) {
    /* throw error if not initialized*/
	ERR_FAIL_COND_V_MSG(L == nullptr, false, "Lua state is not initialized");
    
    /* close thread if previous exists*/
    close_thread();

    /* get ASCII code (utf-8 segments will be treated as next ASCII chars) */ 
    CharString code_utf8 = p_code.utf8();
    const char *code = code_utf8.get_data();

    String name = p_chunk_name.is_empty() ? "chunk" : p_chunk_name;
    CharString name_utf8 = name.utf8();
    const char *chunk_name = name_utf8.get_data();

    /* create new thread */
    L_co = lua_newthread(L);
    L_co_ref = luaL_ref(L, LUA_REGISTRYINDEX);

    /* compile code */
    if (luaL_loadbuffer(L_co, code, code_utf8.length(), chunk_name) != LUA_OK) {
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

int GDLua::get_current_line(int level) {
    if (L_co == nullptr) return -1;
    lua_Debug ar;
    if (lua_getstack(L_co, level, &ar) == 0) return -1;
    if (lua_getinfo(L_co, "l", &ar) == 0) return -1;
    return ar.currentline;
}

String GDLua::get_current_source(int level) {
    if (L_co == nullptr) return String();
    lua_Debug ar;
    if (lua_getstack(L_co, level, &ar) == 0) return String();
    if (lua_getinfo(L_co, "S", &ar) == 0) return String();
    return ar.source ? String(ar.source) : String();
}

Dictionary GDLua::get_debug_info(int level) {
    Dictionary info;
    if (L_co == nullptr) {
        info["valid"] = false;
        return info;
    }

    lua_Debug ar;
    if (lua_getstack(L_co, level, &ar) == 0) {
        info["valid"] = false;
        return info;
    }

    if (lua_getinfo(L_co, "nSlut", &ar) == 0) {
        info["valid"] = false;
        return info;
    }

    info["valid"]             = true;
    info["line"]              = ar.currentline;
    info["source"]            = ar.source ? String(ar.source) : String();
    info["short_source"]      = String(ar.short_src);
    info["function"]          = ar.name ? String(ar.name) : String();
    info["namewhat"]          = ar.namewhat ? String(ar.namewhat) : String();
    info["what"]              = ar.what ? String(ar.what) : String();
    info["line_defined"]      = ar.linedefined;
    info["last_line_defined"] = ar.lastlinedefined;
    info["num_upvalues"]      = (int)ar.nups;
    info["num_params"]        = (int)ar.nparams;
    info["is_vararg"]         = (bool)ar.isvararg;
    info["is_tail_call"]      = (bool)ar.istailcall;

    return info;
}

/* PRIVATE API ------------------------------------------------------------------------------------ */

void GDLua::_resume_coroutine(Variant value) {
    _waiting                  = false;
    _pending_resume           = true;
    _pending_value            = value;
    _pending_signal_source_id = 0;
}

void GDLua::disconnect_pending() {
	if (_pending_signal_source_id != 0) {
		godot::Object *obj = godot::ObjectDB::get_instance(_pending_signal_source_id);
		if (obj && obj->has_signal("completed")) {
			obj->disconnect("completed", callable_mp(this, &GDLua::_resume_coroutine));
		}
		_pending_signal_source_id = 0;
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
	clear_error();
	if (!L) return true;
	close_thread();
	lua_close(L);
	L = nullptr;
	return true;
}

bool GDLua::close_thread() {
	if (L_co == nullptr) return true;
	_running = false;
	_waiting = false;
	_pending_resume = false;
	disconnect_pending();
	lua_closethread(L_co, nullptr);
	luaL_unref(L, LUA_REGISTRYINDEX, L_co_ref);
	L_co_ref = LUA_NOREF;
	L_co = nullptr;
	return true;
}

void GDLua::set_error(const String &error) {
    _error_message = error;
    if (log_error) {
        ERR_PRINT(_error_message);
    }
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
            self->_pending_signal_source_id = obj->get_instance_id();
            obj->connect("completed", callable_mp(self, &GDLua::_resume_coroutine));
            self->_waiting = true;
            return lua_yield(L, 0);
        }
    }

    return lua_push_godot_variant_or_error(L, ret);
}