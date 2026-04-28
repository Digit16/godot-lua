#pragma once

extern "C" {
#include "lua.h"
}

typedef struct {
    size_t used;
    size_t size;
} gdlua_alloc_data;


void *gdlua_bounded_alloc(void *ud, void *ptr, size_t osize, size_t nsize);

void yield_hook(lua_State *L, lua_Debug *ar);

int yield_values(lua_State *L);

int lua_godot_print(lua_State* L);