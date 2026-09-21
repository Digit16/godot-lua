#include "gdlua_methods.h"

#include <stdio.h>
#include <corecrt_malloc.h>

#include "godot_cpp/variant/utility_functions.hpp"
#include "godot_cpp/variant/variant.hpp"
#include "godot_cpp/classes/wrapped.hpp"

gdlua_alloc_data data_val = {0, 100000};
gdlua_alloc_data *data = &data_val;

void *gdlua_bounded_alloc(void *ud, void *ptr, size_t osize, size_t nsize) {
    // gdlua_alloc_data *data = (gdlua_alloc_data *)ud;
	printf("[Lua alloc] osize=%zu nsize=%zu used=%zu max=%zu\n",
       osize, nsize, data->used, data->size);

    /* if ptr is NULL, osize contains type id of data allocated instead of old size */
    /* reset it to zero to properly represent already allocated size */
    if (ptr == NULL) { osize = 0; }

    /* if new size is zero, free memory */
    if (nsize == 0) {
        if (ptr) {
            // free(ptr);
            // data->used -= osize;
        }
        return NULL;
    }

    /* this also fails if reducing size of allocation and used memory is already over limit */
    // if (data->used + (nsize - osize) > data->size) { return NULL; }

    void *new_ptr = realloc(ptr, nsize);
    // if (new_ptr) { data->used += nsize - osize; }
    return new_ptr;
}

void yield_hook(lua_State *L, lua_Debug *ar) {
    if (ar->event == LUA_HOOKLINE || ar->event == LUA_HOOKCOUNT) {
        lua_yield(L, 0);  /* safe: yielding from line or count hook */
    }
}

int yield_values(lua_State *L) {
    const int nargs = lua_gettop(L);
    lua_yield(L, nargs);
    return 0;
}

int lua_godot_print(lua_State* L) {
    using namespace godot;

    int nargs = lua_gettop(L);

    String output;

    for (int i = 1; i <= nargs; i++) {
        if (lua_isstring(L, i)) {
            output += lua_tostring(L, i);
        } else if (lua_isnumber(L, i)) {
            output += String::num(lua_tonumber(L, i));
        } else if (lua_isboolean(L, i)) {
            output += lua_toboolean(L, i) ? "true" : "false";
        } else {
            output += "[unsupported]";
        }

        if (i < nargs)
            output += " ";
    }

    UtilityFunctions::print(output);
    return 0;
}
