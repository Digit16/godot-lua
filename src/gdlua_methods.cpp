#include "gdlua_methods.h"

#include <stdio.h>
#include <cstdlib>

#include "godot_cpp/variant/utility_functions.hpp"
#include "godot_cpp/variant/variant.hpp"
#include "godot_cpp/classes/wrapped.hpp"

void *gdlua_bounded_alloc(void *ud, void *ptr, size_t osize, size_t nsize) {
    gdlua_alloc_data *data = (gdlua_alloc_data *)ud;

    /* if ptr is NULL, osize contains type id of data allocated instead of old size */
    /* reset it to zero to properly represent already allocated size */
    if (ptr == NULL) {
        osize = 0;
    }

    /* if new size is zero, free memory */
    if (nsize == 0) {
        if (ptr) {
            free(ptr);
            if (data) {
                if (data->used < osize) {
                    printf("[Lua alloc warning] Memory underflow on free: used=%zu, freed=%zu\n", data->used, osize);
                    data->used = 0;
                } else {
                    data->used -= osize;
                }
            }
        }
        return NULL;
    }

    /* if expanding allocation, check if memory limit is exceeded */
    if (nsize > osize) {
        size_t diff = nsize - osize;
        if (data && data->size > 0) {
            if (diff > data->size || data->used > data->size - diff) {
                printf("[Lua alloc error] Memory limit exceeded: used=%zu + req=%zu > limit=%zu\n",
                       data->used, diff, data->size);
                return NULL;
            }
        }
    }

    void *new_ptr = realloc(ptr, nsize);
    if (new_ptr == NULL) {
        printf("[Lua alloc error] System realloc failed: requested %zu bytes (used=%zu, limit=%zu)\n",
               nsize, data ? data->used : 0, data ? data->size : 0);
        return NULL;
    }

    if (data) {
        if (nsize > osize) {
            data->used += (nsize - osize);
        } else {
            size_t diff = osize - nsize;
            if (data->used < diff) {
                printf("[Lua alloc warning] Memory underflow on shrink: used=%zu, shrink=%zu\n", data->used, diff);
                data->used = 0;
            } else {
                data->used -= diff;
            }
        }
    }
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
