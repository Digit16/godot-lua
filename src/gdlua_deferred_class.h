#pragma once

#include "godot_cpp/classes/ref_counted.hpp"

using namespace godot;

class GDLuaDeferred : public RefCounted {
    GDCLASS(GDLuaDeferred, RefCounted)

protected:
    static void _bind_methods() {}

public:
    GDLuaDeferred() = default;
    ~GDLuaDeferred() = default;
};